import logging

import requests
import uuid
from decimal import Decimal
from django.conf import settings
from django.db import transaction as db_transaction
from bookings.models import Job
from accounts.models import User
from .models import Wallet, Transaction, AppSettings

logger = logging.getLogger(__name__)


def send_sms(phone_number, message):
    """Send SMS notification via eBulkSMS API."""
    if not phone_number:
        logger.warning("Cannot send SMS: no phone number provided")
        return False

    url = 'https://api.ebulksms.com:443/sendsms'
    payload = {
        'username': settings.EBULKSMS_USERNAME,
        'apikey': settings.EBULKSMS_API_KEY,
        'sender': settings.EBULKSMS_SENDER_NAME,
        'messagetext': message,
        'flash': 0,
        'recipients': [phone_number],
    }

    try:
        response = requests.post(url, json=payload, timeout=10)
        result = response.json()

        if result.get('response_code') == 'SUCCESS':
            return True
        else:
            logger.warning("SMS sending failed for %s: %s", phone_number, result.get('response_message'))
            return False
    except Exception as e:
        logger.error("SMS sending error: %s", e)
        return False


@db_transaction.atomic
def process_escrow_release(job):
    """Release escrow funds for a completed job.

    Credits artisan wallet with (escrow_amount - commission), credits admin wallet
    with commission. Returns (artisan_payout, commission_amount).

    Uses select_for_update for wallet rows to prevent race conditions.
    Guarantees admin wallet exists via get_or_create.
    """
    # Refresh the commission rate — now returns Decimal
    commission_rate = AppSettings.get_commission_rate()
    escrow_amount = job.escrow_held_amount
    commission_amount = escrow_amount * commission_rate
    artisan_payout = escrow_amount - commission_amount

    admin_user = User.objects.filter(role=User.Role.ADMIN, is_active=True).first()
    if not admin_user:
        raise ValueError(
            "No active admin user found. Create an admin user before releasing escrow. "
            "Run: python manage.py setup_admin --username admin --password <password>"
        )

    # Use select_for_update + get_or_create to guarantee wallet existence and prevent race conditions
    admin_wallet, _ = Wallet.objects.select_for_update().get_or_create(user=admin_user)
    artisan_wallet, _ = Wallet.objects.select_for_update().get_or_create(user=job.artisan.user)

    # Credit artisan — direct Decimal arithmetic (no str conversion needed)
    artisan_wallet.balance += artisan_payout
    artisan_wallet.save(update_fields=['balance', 'updated_at'])

    # Credit admin commission
    admin_wallet.balance += commission_amount
    admin_wallet.save(update_fields=['balance', 'updated_at'])

    # Create ESCROW_RELEASE transaction for artisan payout
    Transaction.objects.create(
        wallet=artisan_wallet,
        amount=artisan_payout,
        transaction_type=Transaction.Type.ESCROW_RELEASE,
        status=Transaction.Status.COMPLETED,
        reference=f"RELEASE-{job.id}-{uuid.uuid4().hex[:8]}",
        job=job,
        description=f"Escrow release for Job #{job.id} (artisan payout)"
    )

    # Create COMMISSION transaction for admin
    Transaction.objects.create(
        wallet=admin_wallet,
        amount=commission_amount,
        transaction_type=Transaction.Type.COMMISSION,
        status=Transaction.Status.COMPLETED,
        reference=f"COMM-{job.id}-{uuid.uuid4().hex[:8]}",
        job=job,
        description=f"Commission for Job #{job.id}"
    )

    # Reset escrow amount on job
    job.escrow_held_amount = Decimal('0.00')
    job.save(update_fields=['escrow_held_amount', 'updated_at'])

    return artisan_payout, commission_amount


@db_transaction.atomic
def process_escrow_refund(job, refund_amount):
    """Refund escrow funds back to the client (customer) when a dispute is resolved.

    Credits the customer wallet with refund_amount and creates a REFUND transaction.
    If the refund_amount is less than the total escrow, the remainder is also released
    to the artisan (minus commission).

    Uses select_for_update for wallet rows to prevent race conditions.
    """
    # Use select_for_update to prevent race conditions
    customer_wallet, _ = Wallet.objects.select_for_update().get_or_create(user=job.customer)

    # Refund to customer
    customer_wallet.balance += Decimal(str(refund_amount))
    customer_wallet.save(update_fields=['balance', 'updated_at'])

    Transaction.objects.create(
        wallet=customer_wallet,
        amount=refund_amount,
        transaction_type=Transaction.Type.REFUND,
        status=Transaction.Status.COMPLETED,
        reference=f"REFUND-{job.id}-{uuid.uuid4().hex[:8]}",
        job=job,
        description=f"Refund for Job #{job.id} (dispute resolution)"
    )

    # If escrow amount exceeds refund, release remaining to artisan
    remaining_escrow = job.escrow_held_amount - refund_amount
    if remaining_escrow > Decimal('0.00'):
        commission_rate = AppSettings.get_commission_rate()
        commission_on_remaining = remaining_escrow * commission_rate
        artisan_payout = remaining_escrow - commission_on_remaining

        if job.artisan:
            artisan_wallet, _ = Wallet.objects.select_for_update().get_or_create(user=job.artisan.user)
            artisan_wallet.balance += artisan_payout
            artisan_wallet.save(update_fields=['balance', 'updated_at'])

            admin_user = User.objects.filter(role=User.Role.ADMIN, is_active=True).first()
            if admin_user:
                admin_wallet, _ = Wallet.objects.select_for_update().get_or_create(user=admin_user)
                admin_wallet.balance += commission_on_remaining
                admin_wallet.save(update_fields=['balance', 'updated_at'])

            Transaction.objects.create(
                wallet=artisan_wallet,
                amount=artisan_payout,
                transaction_type=Transaction.Type.ESCROW_RELEASE,
                status=Transaction.Status.COMPLETED,
                reference=f"RELEASE-PARTIAL-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Partial escrow release for Job #{job.id} (dispute resolution)"
            )

            Transaction.objects.create(
                wallet=admin_wallet,
                amount=commission_on_remaining,
                transaction_type=Transaction.Type.COMMISSION,
                status=Transaction.Status.COMPLETED,
                reference=f"COMM-PARTIAL-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Partial commission for Job #{job.id} (dispute resolution)"
            )

    # Reset escrow amount on job — always zero after distribution
    job.escrow_held_amount = Decimal('0.00')
    job.save(update_fields=['escrow_held_amount', 'updated_at'])


# ========================
# Paystack Transfer (Bank Payout) Integration
# ========================

def create_transfer_recipient(bank_code, account_number, account_name):
    """Create a Paystack transfer recipient for an artisan's bank account.

    Returns the recipient_code on success, or None on failure.
    This should be called when an artisan adds or verifies their bank account.

    Docs: https://paystack.com/docs/transfers/transfer-recipient
    """
    url = f"{settings.PAYSTACK_API_URL}/transferrecipient"
    headers = {
        'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
        'Content-Type': 'application/json',
    }
    data = {
        'type': 'nuban',
        'name': account_name,
        'bank_code': bank_code,
        'account_number': account_number,
        'currency': 'NGN',
    }

    try:
        response = requests.post(url, json=data, headers=headers, timeout=10)
        result = response.json()

        if response.status_code == 201 and result.get('status'):
            return result['data']['recipient_code']
        else:
            logger.error("Paystack create recipient failed: %s", result.get('message', 'Unknown error'))
            return None
    except requests.RequestException as e:
        logger.error("Paystack create recipient request failed: %s", e)
        return None


def initiate_paystack_transfer(amount, recipient_code, reference, reason=''):
    """Initiate a Paystack transfer to pay an artisan's bank account.

    This debits the platform's Paystack balance and sends money to the
    artisan's verified bank account.

    Args:
        amount: Decimal amount in Naira (will be converted to kobo)
        recipient_code: Paystack transfer recipient code
        reference: Unique reference for this transfer
        reason: Optional description

    Returns:
        dict with 'success' (bool) and 'transfer_code' or 'error' (str)
    """
    url = f"{settings.PAYSTACK_API_URL}/transfer"
    headers = {
        'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
        'Content-Type': 'application/json',
    }
    data = {
        'source': 'balance',  # Transfer from Paystack balance
        'amount': int(amount * 100),  # Convert Naira to kobo
        'recipient': recipient_code,
        'reference': reference,
        'reason': reason or f"Withdrawal ref: {reference}",
    }

    try:
        response = requests.post(url, json=data, headers=headers, timeout=15)
        result = response.json()

        if response.status_code == 200 and result.get('status'):
            return {
                'success': True,
                'transfer_code': result['data']['transfer_code'],
                'reference': result['data']['reference'],
            }
        else:
            error_msg = result.get('message', 'Unknown Paystack error')
            logger.error("Paystack transfer initiation failed: %s", error_msg)
            return {
                'success': False,
                'error': error_msg,
            }
    except requests.RequestException as e:
        logger.error("Paystack transfer request failed: %s", e)
        return {
            'success': False,
            'error': f"Transfer service unavailable: {str(e)}",
        }


def verify_paystack_transfer(transfer_code):
    """Verify the status of a Paystack transfer.

    Returns:
        dict with 'success' (bool), 'status' (str), and 'amount' (Decimal) or 'error' (str)
    """
    url = f"{settings.PAYSTACK_API_URL}/transfer/verify/{transfer_code}"
    headers = {
        'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
    }

    try:
        response = requests.get(url, headers=headers, timeout=10)
        result = response.json()

        if response.status_code == 200 and result.get('status'):
            data = result['data']
            return {
                'success': True,
                'status': data.get('status', 'unknown'),
                'amount': Decimal(str(data.get('amount', 0))) / 100,  # Kobo to Naira
                'reference': data.get('reference', ''),
            }
        else:
            return {
                'success': False,
                'error': result.get('message', 'Verification failed'),
            }
    except requests.RequestException as e:
        logger.error("Paystack transfer verification failed: %s", e)
        return {
            'success': False,
            'error': f"Verification service unavailable: {str(e)}",
        }


@db_transaction.atomic
def process_withdrawal(user, amount, bank_account=None):
    """Process a withdrawal request from an artisan to their bank account.

    This function:
    1. Deducts the amount from the user's wallet (with row lock)
    2. Creates a PENDING TRANSFER_OUT transaction
    3. If a verified bank_account with a paystack_recipient_code is provided,
       immediately initiates the Paystack transfer
    4. If no verified bank account, the withdrawal stays PENDING until an admin
       manually processes it

    Args:
        user: The User requesting the withdrawal
        amount: Decimal amount to withdraw
        bank_account: Optional BankAccount instance for Paystack transfer

    Returns:
        dict with 'success' (bool), 'transaction' (Transaction), and 'message' (str)
    """
    from .models import BankAccount

    # Lock wallet row
    try:
        wallet = Wallet.objects.select_for_update().get(user=user)
    except Wallet.DoesNotExist:
        return {'success': False, 'error': 'Wallet not found'}

    MIN_WITHDRAWAL = Decimal('100.00')  # Minimum ₦100

    if amount < MIN_WITHDRAWAL:
        return {'success': False, 'error': f'Minimum withdrawal amount is ₦{MIN_WITHDRAWAL}'}

    if wallet.balance < amount:
        return {'success': False, 'error': 'Insufficient funds'}

    # Deduct from wallet
    wallet.balance -= amount
    wallet.save(update_fields=['balance', 'updated_at'])

    reference = f"WDR-{user.id}-{uuid.uuid4().hex[:8]}"

    # Determine if we can auto-transfer via Paystack
    if bank_account and bank_account.is_verified and bank_account.paystack_recipient_code:
        # Initiate Paystack transfer immediately
        result = initiate_paystack_transfer(
            amount=amount,
            recipient_code=bank_account.paystack_recipient_code,
            reference=reference,
            reason=f"Withdrawal for {user.username}"
        )

        if result['success']:
            # Transfer initiated — mark as PENDING (will be COMPLETED on webhook callback)
            transaction = Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.TRANSFER_OUT,
                status=Transaction.Status.PENDING,
                reference=reference,
                description=f"Bank transfer to {bank_account.account_name} ({bank_account.account_number[-4:]})"
            )
            return {
                'success': True,
                'transaction': transaction,
                'message': f'Withdrawal of ₦{amount} initiated. Transfer to bank account in progress.',
                'transfer_code': result.get('transfer_code'),
            }
        else:
            # Paystack transfer failed — still record as PENDING for admin review
            logger.warning("Paystack transfer failed for withdrawal %s: %s", reference, result.get('error'))
            transaction = Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.TRANSFER_OUT,
                status=Transaction.Status.PENDING,
                reference=reference,
                description=f"Bank transfer to {bank_account.account_name} (awaiting manual processing)"
            )
            return {
                'success': True,
                'transaction': transaction,
                'message': f'Withdrawal of ₦{amount} recorded. Bank transfer pending admin processing.',
            }
    else:
        # No verified bank account — record as PENDING for admin to process manually
        transaction = Transaction.objects.create(
            wallet=wallet,
            amount=amount,
            transaction_type=Transaction.Type.TRANSFER_OUT,
            status=Transaction.Status.PENDING,
            reference=reference,
            description="Bank transfer (awaiting bank account verification)"
        )
        return {
            'success': True,
            'transaction': transaction,
            'message': f'Withdrawal of ₦{amount} recorded. Please verify your bank account to enable automatic transfers.',
        }