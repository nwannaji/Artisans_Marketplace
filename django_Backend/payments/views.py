import logging
import uuid
import os

import requests
from django.conf import settings
from django.shortcuts import get_object_or_404
from django.db import transaction as db_transaction
from django.db.models import Q
from decimal import Decimal, InvalidOperation
from rest_framework import generics, permissions, status, serializers as drf_serializers
from rest_framework.response import Response
from rest_framework.views import APIView
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters

from accounts.models import User
from accounts.permissions import IsAdminRole
from payments.utils import send_sms, process_escrow_release, process_withdrawal, create_transfer_recipient
from .models import Wallet, Transaction, AppSettings, BankAccount
from .serializers import WalletSerializer, TransactionSerializer, AppSettingsSerializer, BankAccountSerializer, WithdrawalSerializer

from bookings.models import Job
from bookings.serializers import JobSerializer

logger = logging.getLogger(__name__)


class WalletDetailAPIView(generics.RetrieveAPIView):
    queryset = Wallet.objects.all()
    serializer_class = WalletSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
        return wallet


class TransactionListCreateAPIView(generics.ListCreateAPIView):
    queryset = Transaction.objects.all()
    serializer_class = TransactionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Filter transactions for the logged-in user's wallet
        user = self.request.user
        return Transaction.objects.filter(wallet=user.wallet).select_related('wallet__user', 'job')

    def perform_create(self, serializer):
        wallet = self.request.user.wallet
        amount = serializer.validated_data['amount']
        transaction_type = serializer.validated_data['transaction_type']

        # SECURITY: Use select_for_update and atomic transaction for withdrawals
        if transaction_type == Transaction.Type.WITHDRAWAL:
            with db_transaction.atomic():
                wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
                if wallet.balance < amount:
                    raise drf_serializers.ValidationError("Insufficient funds for withdrawal.")
                wallet.balance -= amount
                wallet.save(update_fields=['balance', 'updated_at'])

        serializer.save(wallet=wallet)


class TransactionUpdateAPIView(generics.UpdateAPIView):
    queryset = Transaction.objects.all()
    serializer_class = TransactionSerializer
    permission_classes = [IsAdminRole]  # Admin can update transaction status

    def get_object(self):
        # Capture the original status before the update
        obj = super().get_object()
        self._original_status = obj.status
        return obj

    def perform_update(self, serializer):
        instance = serializer.save()

        if instance.status == Transaction.Status.COMPLETED:
            # Credit the wallet only for DEPOSIT completions
            # SECURITY: Only credit if the status transitioned FROM non-COMPLETED.
            # This prevents double-crediting if the Paystack callback already
            # processed this transaction (which also sets status to COMPLETED).
            if instance.transaction_type == Transaction.Type.DEPOSIT:
                if getattr(self, '_original_status', None) != Transaction.Status.COMPLETED:
                    with db_transaction.atomic():
                        wallet = Wallet.objects.select_for_update().get(pk=instance.wallet.pk)
                        wallet.balance += instance.amount
                        wallet.save(update_fields=['balance', 'updated_at'])

        return instance


class AppSettingsRetrieveUpdateAPIView(generics.RetrieveUpdateAPIView):
    queryset = AppSettings.objects.all()
    serializer_class = AppSettingsSerializer
    permission_classes = [IsAdminRole]  # Only admin can update settings

    def get_object(self):
        # Retrieve a setting by key
        key = self.kwargs.get('key')
        return AppSettings.objects.get(key=key)


class EscrowFundJobAPIView(APIView):
    """Client funds a job, placing the amount in escrow."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        user = request.user
        if user.role != User.Role.CUSTOMER:
            return Response(
                {"error": "Only customers can fund jobs"},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            job = Job.objects.get(pk=pk)
        except Job.DoesNotExist:
            return Response(
                {"error": "Job not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        if job.customer != user:
            return Response(
                {"error": "You can only fund your own jobs"},
                status=status.HTTP_403_FORBIDDEN
            )

        if job.status not in [Job.Status.ACCEPTED, Job.Status.IN_PROGRESS]:
            return Response(
                {"error": "Job must be in ACCEPTED or IN_PROGRESS status to fund"},
                status=status.HTTP_400_BAD_REQUEST
            )

        amount = request.data.get('amount')
        if amount:
            try:
                amount = Decimal(str(amount))
                if amount <= 0:
                    raise ValueError
            except (InvalidOperation, ValueError):
                return Response(
                    {"error": "Amount must be a positive number"},
                    status=status.HTTP_400_BAD_REQUEST
                )
        else:
            amount = job.agreed_price

        MINIMUM_ESCROW = Decimal('100.00')  # Minimum ₦100

        if amount < MINIMUM_ESCROW:
            return Response(
                {"error": f"Minimum escrow amount is ₦{MINIMUM_ESCROW}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        with db_transaction.atomic():
            # Lock both the wallet AND the job row to prevent race conditions
            wallet = Wallet.objects.select_for_update().get(user=user)
            job = Job.objects.select_for_update().get(pk=job.pk)

            # Re-check escrow after acquiring lock (prevents double-fund)
            if job.escrow_held_amount and job.escrow_held_amount > 0:
                return Response(
                    {"error": "Job already funded"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if wallet.balance < amount:
                return Response(
                    {"error": "Insufficient funds"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            wallet.balance -= amount
            wallet.save(update_fields=['balance', 'updated_at'])

            reference = f"ESCROW-{job.id}-{uuid.uuid4().hex[:8]}"
            Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.ESCROW_HOLD,
                status=Transaction.Status.COMPLETED,
                reference=reference,
                job=job,
                description=f"Escrow hold for Job #{job.id}"
            )

            job.escrow_held_amount = amount
            job.save(update_fields=['escrow_held_amount', 'updated_at'])

        return Response({
            "message": "Job funded successfully. Amount held in escrow.",
            "escrow_amount": str(amount),
            "job_id": job.id,
        })


class EscrowReleaseJobAPIView(APIView):
    """Client confirms job completion, releasing escrow to artisan minus commission."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        user = request.user
        if user.role != User.Role.CUSTOMER:
            return Response(
                {"error": "Only customers can confirm completion"},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            job = Job.objects.get(pk=pk)
        except Job.DoesNotExist:
            return Response(
                {"error": "Job not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        if job.customer != user:
            return Response(
                {"error": "Not your job"},
                status=status.HTTP_403_FORBIDDEN
            )

        if job.status not in [Job.Status.IN_PROGRESS, Job.Status.AWAITING_REVIEW, Job.Status.COMPLETED]:
            return Response(
                {"error": "Job must be in IN_PROGRESS, AWAITING_REVIEW, or COMPLETED status to release escrow"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not job.escrow_held_amount or job.escrow_held_amount <= 0:
            return Response(
                {"error": "No escrow held for this job"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not job.artisan:
            return Response(
                {"error": "No artisan assigned"},
                status=status.HTTP_400_BAD_REQUEST
            )

        with db_transaction.atomic():
            artisan_payout, commission_amount = process_escrow_release(job)

            # Mark job as completed (if not already)
            if job.status != Job.Status.COMPLETED:
                job.status = Job.Status.COMPLETED
                job.save()

        return Response({
            "message": "Job completed. Escrow released to artisan.",
            "artisan_payout": str(artisan_payout),
            "commission_amount": str(commission_amount),
            "commission_rate": f"{AppSettings.get_commission_rate() * 100}%",
        })


class PaystackPaymentCallbackView(APIView):
    """Handle Paystack payment callback.

    SECURITY: This endpoint verifies payment with Paystack's API before
    crediting the wallet. Uses idempotency check on the transaction reference
    to prevent double-crediting.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, *args, **kwargs):
        reference = request.data.get('reference')

        if not reference:
            return Response({'error': 'Reference is required'}, status=status.HTTP_400_BAD_REQUEST)

        # Verify the payment with Paystack API
        url = f"{settings.PAYSTACK_API_URL}/transaction/verify/{reference}"
        headers = {
            'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
        }

        try:
            response = requests.get(url, headers=headers, timeout=10)
            result = response.json()
        except requests.RequestException:
            logger.error("Paystack verification request failed for reference: %s", reference)
            return Response(
                {'error': 'Payment verification service unavailable'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE
            )

        if response.status_code == 200 and result['data']['status'] == 'success':
            with db_transaction.atomic():
                try:
                    transaction = Transaction.objects.select_for_update().get(reference=reference)
                except Transaction.DoesNotExist:
                    return Response({'error': 'Transaction not found'}, status=status.HTTP_404_NOT_FOUND)

                # SECURITY: Idempotency check — prevent double-crediting
                if transaction.status == Transaction.Status.COMPLETED:
                    return Response({'status': 'Payment already processed'})

                transaction.status = Transaction.Status.COMPLETED
                transaction.save(update_fields=['status'])

                # Credit the wallet — this is the ONLY place wallet is credited for deposits
                wallet = Wallet.objects.select_for_update().get(pk=transaction.wallet.pk)
                wallet.balance += transaction.amount
                wallet.save(update_fields=['balance', 'updated_at'])

            # Notify user about successful payment
            self.send_payment_notification(wallet.user, transaction)

            return Response({'status': 'Payment successful'})
        else:
            # Mark transaction as failed
            Transaction.objects.filter(reference=reference).update(
                status=Transaction.Status.FAILED
            )
            logger.warning("Paystack verification failed for reference: %s", reference)
            return Response({'error': 'Payment verification failed'}, status=status.HTTP_400_BAD_REQUEST)

    def send_payment_notification(self, user, transaction):
        try:
            message = (
                f"Hi {user.username}, your payment of ₦{transaction.amount} was successful.\n"
                f"Reference: {transaction.reference}\n"
                "Thank you for your patronage."
            )
            send_sms(user.phone_number, message)
        except Exception:
            logger.warning("Failed to send payment notification to user %s", user.pk)


class DepositAPIView(APIView):
    """Customer deposits funds into their wallet via Paystack."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        amount = request.data.get('amount')

        if not amount:
            return Response(
                {"error": "Amount is required"},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            amount = Decimal(str(amount))
            if amount <= 0:
                raise ValueError
        except (InvalidOperation, ValueError):
            return Response(
                {"error": "Amount must be a positive number"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # SECURITY: Amount validation — cap at reasonable limits
        if amount > Decimal('1000000'):
            return Response(
                {"error": "Amount exceeds maximum deposit limit"},
                status=status.HTTP_400_BAD_REQUEST
            )

        wallet, _ = Wallet.objects.get_or_create(user=user)

        # Create a PENDING deposit transaction
        reference = f"DEPOSIT-{user.id}-{uuid.uuid4().hex[:8]}"
        transaction = Transaction.objects.create(
            wallet=wallet,
            amount=amount,
            transaction_type=Transaction.Type.DEPOSIT,
            status=Transaction.Status.PENDING,
            reference=reference,
            description=f"Wallet deposit of ₦{amount}"
        )

        # Initialize Paystack payment
        url = f"{settings.PAYSTACK_API_URL}/transaction/initialize"
        headers = {
            'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
            'Content-Type': 'application/json',
        }
        data = {
            'amount': int(amount * 100),  # Convert to kobo
            'email': user.email,
            'reference': reference,
            'callback_url': os.environ.get('PAYSTACK_CALLBACK_URL', 'http://localhost:8000/api/paystack/callback/'),
        }

        try:
            response = requests.post(url, json=data, headers=headers, timeout=10)
            result = response.json()

            if response.status_code == 200:
                return Response({
                    'message': 'Deposit initialized',
                    'authorization_url': result['data']['authorization_url'],
                    'reference': reference,
                    'amount': str(amount),
                })
            else:
                transaction.status = Transaction.Status.FAILED
                transaction.save(update_fields=['status'])
                return Response(
                    {'error': 'Payment initialization failed. Please try again.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
        except requests.RequestException:
            transaction.status = Transaction.Status.FAILED
            transaction.save(update_fields=['status'])
            return Response(
                {'error': 'Payment service unavailable'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE
            )


class AdminEscrowListView(generics.ListAPIView):
    """Admin views all jobs with held escrow."""
    serializer_class = JobSerializer
    permission_classes = [IsAdminRole]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    ordering_fields = ['created_at', 'escrow_held_amount']
    ordering = ['-created_at']

    def get_queryset(self):
        return Job.objects.filter(
            escrow_held_amount__gt=0
        ).select_related('customer', 'artisan', 'artisan__user', 'admin_approved_by')


class AdminEscrowReleaseAPIView(APIView):
    """Admin releases escrow for a job, crediting the artisan minus commission."""
    permission_classes = [IsAdminRole]

    def post(self, request, pk):
        with db_transaction.atomic():
            try:
                job = Job.objects.select_for_update().get(pk=pk)
            except Job.DoesNotExist:
                return Response(
                    {"error": "Job not found"},
                    status=status.HTTP_404_NOT_FOUND
                )

            if not job.escrow_held_amount or job.escrow_held_amount <= 0:
                return Response(
                    {"error": "No escrow held for this job"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not job.artisan:
                return Response(
                    {"error": "No artisan assigned to this job"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if job.status not in [Job.Status.IN_PROGRESS, Job.Status.COMPLETED]:
                return Response(
                    {"error": "Job must be IN_PROGRESS or COMPLETED to release escrow"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            artisan_payout, commission_amount = process_escrow_release(job)

            # Mark job as completed if not already
            job.refresh_from_db()
            if job.status != Job.Status.COMPLETED:
                job.status = Job.Status.COMPLETED
                job.save(update_fields=['status', 'updated_at'])

        return Response({
            "message": "Escrow released successfully by admin.",
            "artisan_payout": str(artisan_payout),
            "commission_amount": str(commission_amount),
            "commission_rate": f"{AppSettings.get_commission_rate() * 100}%",
        })


class AdminEscrowRefundAPIView(APIView):
    """Admin refunds escrow to the customer (full or partial)."""
    permission_classes = [IsAdminRole]

    def post(self, request, pk):
        with db_transaction.atomic():
            try:
                job = Job.objects.select_for_update().get(pk=pk)
            except Job.DoesNotExist:
                return Response(
                    {"error": "Job not found"},
                    status=status.HTTP_404_NOT_FOUND
                )

            if not job.escrow_held_amount or job.escrow_held_amount <= 0:
                return Response(
                    {"error": "No escrow held for this job"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            refund_amount = request.data.get('refund_amount')
            if refund_amount is not None:
                refund_amount = Decimal(str(refund_amount))
            else:
                # Default to full refund
                refund_amount = job.escrow_held_amount

            if refund_amount <= 0:
                return Response(
                    {"error": "Refund amount must be positive"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if refund_amount > job.escrow_held_amount:
                return Response(
                    {"error": f"Refund amount cannot exceed escrow held (₦{job.escrow_held_amount})"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            from payments.utils import process_escrow_refund
            process_escrow_refund(job, refund_amount)

        return Response({
            "message": "Escrow refunded successfully by admin.",
            "refund_amount": str(refund_amount),
            "remaining_escrow": str(job.escrow_held_amount),
        })


class PaystackWebhookView(APIView):
    """Handle Paystack webhook events for async payment confirmation.

    This endpoint is called by Paystack's servers (not the user's browser),
    so it does NOT require authentication. Instead, it verifies Paystack's
    HMAC signature to ensure the request is genuine.

    Supports:
    - charge.success: Credits wallet for completed deposits
    - charge.failed: Marks transaction as failed
    """
    permission_classes = []  # No auth required — Paystack calls this server-to-server
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        # Verify Paystack signature
        paystack_signature = request.headers.get('x-paystack-signature', '')
        if not paystack_signature:
            logger.warning("Paystack webhook: missing signature header")
            return Response({'error': 'Missing signature'}, status=status.HTTP_401_UNAUTHORIZED)

        # Compute expected signature
        import hmac
        import hashlib
        secret = settings.PAYSTACK_SECRET_KEY
        expected_signature = hmac.new(
            secret.encode('utf-8'),
            request.body,
            hashlib.sha512
        ).hexdigest()

        if not hmac.compare_digest(paystack_signature, expected_signature):
            logger.warning("Paystack webhook: invalid signature")
            return Response({'error': 'Invalid signature'}, status=status.HTTP_401_UNAUTHORIZED)

        payload = request.data
        event = payload.get('event', '')
        data = payload.get('data', {})

        if event == 'charge.success':
            return self._handle_charge_success(data)
        elif event == 'charge.failed':
            return self._handle_charge_failed(data)
        else:
            # Acknowledge other events but don't process
            logger.info("Paystack webhook: unhandled event '%s'", event)
            return Response({'status': 'acknowledged'})

    def _handle_charge_success(self, data):
        """Process a successful charge from Paystack webhook."""
        reference = data.get('reference', '')
        amount_kobo = data.get('amount', 0)
        status = data.get('status', '')

        if not reference:
            logger.warning("Paystack webhook: charge.success missing reference")
            return Response({'error': 'Missing reference'}, status=status.HTTP_400_BAD_REQUEST)

        # Verify with Paystack API for extra security
        url = f"{settings.PAYSTACK_API_URL}/transaction/verify/{reference}"
        headers = {'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}"}

        try:
            response = requests.get(url, headers=headers, timeout=10)
            result = response.json()
        except requests.RequestException:
            logger.error("Paystack webhook: verification request failed for %s", reference)
            return Response({'error': 'Verification failed'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        if response.status_code != 200 or result.get('data', {}).get('status') != 'success':
            logger.warning("Paystack webhook: verification failed for %s", reference)
            return Response({'error': 'Verification failed'}, status=status.HTTP_400_BAD_REQUEST)

        with db_transaction.atomic():
            try:
                transaction = Transaction.objects.select_for_update().get(reference=reference)
            except Transaction.DoesNotExist:
                logger.warning("Paystack webhook: transaction not found for %s", reference)
                return Response({'error': 'Transaction not found'}, status=status.HTTP_404_NOT_FOUND)

            # Idempotency check
            if transaction.status == Transaction.Status.COMPLETED:
                logger.info("Paystack webhook: transaction %s already processed", reference)
                return Response({'status': 'already processed'})

            # Verify amount matches (in kobo)
            expected_amount_kobo = int(transaction.amount * 100)
            if amount_kobo != expected_amount_kobo:
                logger.error(
                    "Paystack webhook: amount mismatch for %s — expected %d kobo, got %d kobo",
                    reference, expected_amount_kobo, amount_kobo
                )
                return Response({'error': 'Amount mismatch'}, status=status.HTTP_400_BAD_REQUEST)

            transaction.status = Transaction.Status.COMPLETED
            transaction.save(update_fields=['status'])

            # Credit the wallet
            wallet = Wallet.objects.select_for_update().get(pk=transaction.wallet.pk)
            wallet.balance += transaction.amount
            wallet.save(update_fields=['balance', 'updated_at'])

        # Send notification (outside transaction to avoid rollback on failure)
        try:
            message = (
                f"Hi {wallet.user.username}, your payment of ₦{transaction.amount} was successful.\n"
                f"Reference: {transaction.reference}\n"
                "Thank you for your patronage."
            )
            send_sms(wallet.user.phone_number, message)
        except Exception:
            logger.warning("Failed to send webhook payment notification to user %s", wallet.user.pk)

        logger.info("Paystack webhook: successfully processed deposit for %s", reference)
        return Response({'status': 'success'})

    def _handle_charge_failed(self, data):
        """Mark a failed charge transaction."""
        reference = data.get('reference', '')

        if reference:
            updated = Transaction.objects.filter(
                reference=reference,
                status=Transaction.Status.PENDING
            ).update(status=Transaction.Status.FAILED)
            if updated:
                logger.info("Paystack webhook: marked transaction %s as FAILED", reference)

        return Response({'status': 'acknowledged'})


# ========================
# Bank Account Management
# ========================

class BankAccountListCreateAPIView(generics.ListCreateAPIView):
    """List or add bank accounts for the authenticated artisan.

    GET  /api/payments/bank-accounts/       — list user's bank accounts
    POST /api/payments/bank-accounts/       — add a new bank account
    """
    serializer_class = BankAccountSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return BankAccount.objects.filter(user=self.request.user).order_by('-is_default', '-created_at')

    def perform_create(self, serializer):
        bank_account = serializer.save(user=self.request.user)

        # If this is the user's first bank account or marked as default, set it
        user_accounts = BankAccount.objects.filter(user=self.request.user)
        if user_accounts.count() == 1 or bank_account.is_default:
            # Unset other defaults
            user_accounts.exclude(pk=bank_account.pk).update(is_default=False)
            bank_account.is_default = True
            bank_account.save(update_fields=['is_default'])

        # Attempt to create Paystack transfer recipient for auto-payout
        if not bank_account.paystack_recipient_code:
            recipient_code = create_transfer_recipient(
                bank_code=bank_account.bank_code,
                account_number=bank_account.account_number,
                account_name=bank_account.account_name,
            )
            if recipient_code:
                bank_account.paystack_recipient_code = recipient_code
                bank_account.is_verified = True
                bank_account.save(update_fields=['paystack_recipient_code', 'is_verified', 'updated_at'])
                logger.info(
                    "Paystack recipient created for bank account %s (user %s)",
                    bank_account.pk, self.request.user.pk
                )
            else:
                logger.warning(
                    "Failed to create Paystack recipient for bank account %s (user %s) — will need manual verification",
                    bank_account.pk, self.request.user.pk
                )


class BankAccountDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    """Get, update, or delete a specific bank account.

    GET    /api/payments/bank-accounts/<pk>/     — retrieve a bank account
    PATCH  /api/payments/bank-accounts/<pk>/     — update a bank account
    DELETE /api/payments/bank-accounts/<pk>/     — delete a bank account
    """
    serializer_class = BankAccountSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return BankAccount.objects.filter(user=self.request.user)

    def perform_update(self, serializer):
        bank_account = serializer.save()

        # If marked as default, unset others
        if bank_account.is_default:
            BankAccount.objects.filter(
                user=self.request.user
            ).exclude(pk=bank_account.pk).update(is_default=False)

        # Re-create Paystack recipient if bank details changed
        if 'bank_code' in serializer.validated_data or 'account_number' in serializer.validated_data:
            bank_account.paystack_recipient_code = ''
            bank_account.is_verified = False
            recipient_code = create_transfer_recipient(
                bank_code=bank_account.bank_code,
                account_number=bank_account.account_number,
                account_name=bank_account.account_name,
            )
            if recipient_code:
                bank_account.paystack_recipient_code = recipient_code
                bank_account.is_verified = True
            bank_account.save(update_fields=['paystack_recipient_code', 'is_verified', 'updated_at'])

    def perform_destroy(self, instance):
        # If deleting the default account, promote another
        was_default = instance.is_default
        instance.delete()
        if was_default:
            next_account = BankAccount.objects.filter(user=self.request.user).first()
            if next_account:
                next_account.is_default = True
                next_account.save(update_fields=['is_default'])


class BankAccountVerifyAPIView(APIView):
    """Verify a bank account via Paystack and create a transfer recipient.

    POST /api/payments/bank-accounts/<pk>/verify/
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        try:
            bank_account = BankAccount.objects.get(pk=pk, user=request.user)
        except BankAccount.DoesNotExist:
            return Response(
                {"error": "Bank account not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        if bank_account.is_verified:
            return Response(
                {"message": "Bank account already verified"},
                status=status.HTTP_200_OK
            )

        # Create/refresh Paystack transfer recipient
        recipient_code = create_transfer_recipient(
            bank_code=bank_account.bank_code,
            account_number=bank_account.account_number,
            account_name=bank_account.account_name,
        )

        if recipient_code:
            bank_account.paystack_recipient_code = recipient_code
            bank_account.is_verified = True
            bank_account.save(update_fields=['paystack_recipient_code', 'is_verified', 'updated_at'])
            return Response({
                "message": "Bank account verified successfully",
                "is_verified": True,
                "recipient_code": recipient_code,
            })
        else:
            return Response(
                {"error": "Bank account verification failed. Please check your bank details."},
                status=status.HTTP_400_BAD_REQUEST
            )


class WithdrawalAPIView(APIView):
    """Initiate a withdrawal from the authenticated user's wallet to their bank account.

    POST /api/payments/withdraw/
    Body: { "amount": 5000.00, "bank_account_id": 1 }
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = WithdrawalSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        amount = serializer.validated_data['amount']
        bank_account_id = serializer.validated_data.get('bank_account_id')

        # Resolve bank account if provided
        bank_account = None
        if bank_account_id:
            try:
                bank_account = BankAccount.objects.get(pk=bank_account_id, user=request.user)
            except BankAccount.DoesNotExist:
                return Response(
                    {"error": "Bank account not found"},
                    status=status.HTTP_404_NOT_FOUND
                )
        else:
            # Use the user's default bank account
            bank_account = BankAccount.objects.filter(
                user=request.user, is_default=True
            ).first()

        result = process_withdrawal(
            user=request.user,
            amount=amount,
            bank_account=bank_account,
        )

        if result.get('success'):
            response_data = {
                "message": result['message'],
                "reference": result['transaction'].reference,
                "amount": str(result['transaction'].amount),
                "status": result['transaction'].status,
            }
            if 'transfer_code' in result:
                response_data['transfer_code'] = result['transfer_code']
            return Response(response_data, status=status.HTTP_201_CREATED)
        else:
            return Response(
                {"error": result.get('error', 'Withdrawal failed')},
                status=status.HTTP_400_BAD_REQUEST
            )