import logging
import time

import requests as requests_lib
import uuid
import hmac
import hashlib
import json
from decimal import Decimal
from django.conf import settings
from django.db import transaction as db_transaction
from bookings.models import Job
from accounts.models import User
from .models import Wallet, Transaction, AppSettings, PandascrowEscrow

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
        response = requests_lib.post(url, json=payload, timeout=10)
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
        response = requests_lib.post(url, json=data, headers=headers, timeout=10)
        result = response.json()

        if response.status_code == 201 and result.get('status'):
            return result['data']['recipient_code']
        else:
            logger.error("Paystack create recipient failed: %s", result.get('message', 'Unknown error'))
            return None
    except requests_lib.RequestException as e:
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
        response = requests_lib.post(url, json=data, headers=headers, timeout=15)
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
    except requests_lib.RequestException as e:
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
        response = requests_lib.get(url, headers=headers, timeout=10)
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
    except requests_lib.RequestException as e:
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
                transfer_code=result.get('transfer_code', ''),
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


# ========================
# Pandascrow Escrow Integration
# ========================

class PandascrowAPIError(Exception):
    """Custom exception for Pandascrow API failures."""

    def __init__(self, message, status_code=None, response_data=None):
        self.status_code = status_code
        self.response_data = response_data or {}
        super().__init__(message)


# Module-level token cache for Pandascrow authentication
_pandascrow_token_cache = {'token': None, 'expires_at': 0}


def is_pandascrow_configured():
    """Check if Pandascrow is properly configured (has client ID and secret)."""
    return bool(settings.PANDASCROW_CLIENT_ID and settings.PANDASCROW_CLIENT_SECRET)


def get_pandascrow_auth_token():
    """Authenticate with Pandascrow and return an access token.

    Uses module-level cache with 55-minute TTL (tokens typically last 60 min).
    Re-authenticates automatically when the token expires.
    """
    global _pandascrow_token_cache

    # Return cached token if still valid
    if _pandascrow_token_cache['token'] and time.time() < _pandascrow_token_cache['expires_at']:
        return _pandascrow_token_cache['token']

    if not is_pandascrow_configured():
        raise PandascrowAPIError("Pandascrow is not configured. Set PANDASCROW_CLIENT_ID and PANDASCROW_CLIENT_SECRET.")

    url = f"{settings.PANDASCROW_API_URL}/login"
    data = {
        'uuid': settings.PANDASCROW_CLIENT_ID,
        'password': settings.PANDASCROW_CLIENT_SECRET,
    }
    headers = {'Content-Type': 'application/json'}

    try:
        response = requests_lib.post(url, json=data, headers=headers, timeout=15)
        result = response.json()

        # Pandascrow may return token in different response shapes
        # Try common patterns: data.access_token, access_token, token
        if response.status_code == 200:
            token = None
            if isinstance(result.get('data'), dict):
                token = result['data'].get('access_token') or result['data'].get('token')
            if not token:
                token = result.get('access_token') or result.get('token')

            if token:
                # Cache for 55 minutes
                _pandascrow_token_cache['token'] = token
                _pandascrow_token_cache['expires_at'] = time.time() + 3300  # 55 minutes
                return token
            else:
                # If login succeeded but no token, try using the secret key directly as Bearer token
                # (Some Pandascrow setups use the secret key directly)
                logger.info("Pandascrow login returned no access token — using secret key as Bearer token")
                _pandascrow_token_cache['token'] = settings.PANDASCROW_CLIENT_SECRET
                _pandascrow_token_cache['expires_at'] = time.time() + 3300
                return settings.PANDASCROW_CLIENT_SECRET
        else:
            error_msg = result.get('message', result.get('error', 'Authentication failed'))
            raise PandascrowAPIError(
                f"Pandascrow authentication failed: {error_msg}",
                status_code=response.status_code,
                response_data=result,
            )
    except requests_lib.RequestException as e:
        raise PandascrowAPIError(f"Pandascrow auth request failed: {e}")


def pandascrow_api_request(method, endpoint, data=None, retry_on_auth=True):
    """Make an authenticated request to the Pandascrow API.

    Args:
        method: HTTP method ('get', 'post', 'put', 'patch', 'delete')
        endpoint: API endpoint path (e.g., '/escrow/initialize')
        data: Request body dict for POST/PUT/PATCH
        retry_on_auth: Whether to retry once on 401 (re-authenticate)

    Returns:
        Parsed JSON response dict

    Raises:
        PandascrowAPIError on failure
    """
    token = get_pandascrow_auth_token()
    url = f"{settings.PANDASCROW_API_URL}{endpoint}"
    headers = {
        'Authorization': f"Bearer {token}",
        'Content-Type': 'application/json',
    }

    try:
        if method.lower() == 'get':
            response = requests_lib.get(url, headers=headers, timeout=15)
        elif method.lower() == 'post':
            response = requests_lib.post(url, json=data, headers=headers, timeout=15)
        elif method.lower() == 'put':
            response = requests_lib.put(url, json=data, headers=headers, timeout=15)
        elif method.lower() == 'patch':
            response = requests_lib.patch(url, json=data, headers=headers, timeout=15)
        elif method.lower() == 'delete':
            response = requests_lib.delete(url, headers=headers, timeout=15)
        else:
            raise PandascrowAPIError(f"Unsupported HTTP method: {method}")

        # Handle 401 by re-authenticating and retrying once
        if response.status_code == 401 and retry_on_auth:
            global _pandascrow_token_cache
            _pandascrow_token_cache['token'] = None  # Clear cached token
            return pandascrow_api_request(method, endpoint, data, retry_on_auth=False)

        result = response.json() if response.content else {}

        if response.status_code >= 400:
            error_msg = result.get('message', result.get('error', f'HTTP {response.status_code}'))
            raise PandascrowAPIError(
                f"Pandascrow API error: {error_msg}",
                status_code=response.status_code,
                response_data=result,
            )

        return result

    except requests_lib.RequestException as e:
        raise PandascrowAPIError(f"Pandascrow API request failed: {e}")


def pandascrow_initialize_escrow(job, amount, customer, artisan):
    """Create a one-time escrow on Pandascrow for a job.

    Args:
        job: The Job instance
        amount: Decimal escrow amount in NGN
        customer: The User (customer) who will pay
        artisan: The ArtisanProfile instance who will receive payment

    Returns:
        Tuple of (escrow_id, payment_url) on success

    Raises:
        PandascrowAPIError on failure
    """
    commission_rate = AppSettings.get_commission_rate()
    # Pandascrow expects partner_escrow_fee as a percentage string (e.g., "10" for 10%)
    partner_fee_percentage = str(int(commission_rate * 100))

    data = {
        'uuid': str(customer.id),  # Use customer's local ID as identifier
        'escrow_type': 'onetime',
        'initiator_role': 'buyer',
        'initiator_id': str(customer.id),
        'receiver_id': str(artisan.user.id),
        'title': f"Job #{job.id} - {job.description[:50]}",
        'currency': 'NGN',
        'amount': float(amount),
        'description': job.description,
        'inspection_period': '3',
        'delivery_date': job.scheduled_time.strftime('%Y-%m-%d'),
        'how_dispute_is_handled': 'platform',
        'who_pay_fees': 'both',  # Platform fee split between buyer and seller
        'partner_escrow_fee': partner_fee_percentage,
        'callback_url': settings.PANDASCROW_CALLBACK_URL,
        'buyer_details': {
            'name': customer.get_full_name() or customer.username,
            'email': customer.email,
            'phone': getattr(customer, 'phone_number', ''),
        },
        'seller_details': {
            'name': artisan.user.get_full_name() or artisan.user.username,
            'email': artisan.user.email,
            'phone': getattr(artisan.user, 'phone_number', ''),
        },
    }

    # Remove None values
    data = {k: v for k, v in data.items() if v is not None and v != ''}

    try:
        result = pandascrow_api_request('post', '/escrow/initialize', data=data)
    except PandascrowAPIError:
        raise
    except Exception as e:
        raise PandascrowAPIError(f"Failed to initialize Pandascrow escrow: {e}")

    escrow_data = result.get('data', result)
    escrow_id = escrow_data.get('escrow_id') or escrow_data.get('id')
    payment_url = escrow_data.get('payment_url') or escrow_data.get('authorization_url')

    if not escrow_id:
        raise PandascrowAPIError(
            "Pandascrow escrow initialization succeeded but no escrow_id returned",
            response_data=result,
        )

    logger.info(
        "Pandascrow escrow initialized: escrow_id=%s, job_id=%s, amount=%s",
        escrow_id, job.id, amount
    )
    return escrow_id, payment_url


def pandascrow_complete_escrow(escrow_id, otp=None):
    """Mark a Pandascrow escrow as complete.

    Args:
        escrow_id: The Pandascrow escrow identifier
        otp: Optional OTP code if Pandascrow requires it for confirmation

    Returns:
        Response data dict from Pandascrow

    Raises:
        PandascrowAPIError on failure
    """
    data = {
        'escrow_id': escrow_id,
    }
    if otp:
        data['otp'] = otp

    try:
        result = pandascrow_api_request('post', '/escrow/complete', data=data)
        logger.info("Pandascrow escrow completed: escrow_id=%s", escrow_id)
        return result
    except PandascrowAPIError:
        raise
    except Exception as e:
        raise PandascrowAPIError(f"Failed to complete Pandascrow escrow: {e}")


def pandascrow_cancel_escrow(escrow_id):
    """Cancel a Pandascrow escrow (used for refunds/disputes).

    Args:
        escrow_id: The Pandascrow escrow identifier

    Returns:
        Response data dict from Pandascrow

    Raises:
        PandascrowAPIError on failure
    """
    try:
        result = pandascrow_api_request('post', f'/escrow/{escrow_id}/cancel', data={})
        logger.info("Pandascrow escrow cancelled: escrow_id=%s", escrow_id)
        return result
    except PandascrowAPIError:
        raise
    except Exception as e:
        raise PandascrowAPIError(f"Failed to cancel Pandascrow escrow: {e}")


def pandascrow_get_escrow(escrow_id):
    """Fetch escrow details from Pandascrow.

    Args:
        escrow_id: The Pandascrow escrow identifier

    Returns:
        Escrow data dict from Pandascrow

    Raises:
        PandascrowAPIError on failure
    """
    try:
        result = pandascrow_api_request('get', f'/escrow/{escrow_id}')
        return result.get('data', result)
    except PandascrowAPIError:
        raise
    except Exception as e:
        raise PandascrowAPIError(f"Failed to fetch Pandascrow escrow: {e}")


def verify_pandascrow_webhook_signature(payload, signature):
    """Verify the HMAC-SHA256 signature of a Pandascrow webhook payload.

    Args:
        payload: Raw request body bytes
        signature: Value of the X-Pandascrow-Signature header

    Returns:
        True if the signature is valid, False otherwise
    """
    if not settings.PANDASCROW_WEBHOOK_SECRET:
        logger.warning("Pandascrow webhook secret not configured — skipping signature verification")
        return False

    expected_signature = hmac.new(
        settings.PANDASCROW_WEBHOOK_SECRET.encode('utf-8'),
        payload,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(signature, expected_signature)