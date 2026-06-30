import logging
import uuid
import os
import json as json_module
import hmac
import hashlib

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
from payments.utils import (
    send_sms, process_escrow_release, process_escrow_refund,
    process_withdrawal, create_transfer_recipient,
    is_pandascrow_configured, pandascrow_initialize_escrow,
    pandascrow_complete_escrow, pandascrow_cancel_escrow,
    pandascrow_get_escrow, verify_pandascrow_webhook_signature,
    PandascrowAPIError,
)
from .models import Wallet, Transaction, AppSettings, BankAccount, PandascrowEscrow
from .serializers import (
    WalletSerializer, TransactionSerializer, AppSettingsSerializer,
    BankAccountSerializer, WithdrawalSerializer, EscrowFundSerializer,
    EscrowReleaseOtpSerializer, PandascrowEscrowSerializer,
)

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
        wallet, _ = Wallet.objects.get_or_create(user=user)
        return Transaction.objects.filter(wallet=wallet).select_related('wallet__user', 'job')

    def perform_create(self, serializer):
        # SECURITY: Users can only create WITHDRAWAL requests directly.
        # DEPOSIT transactions are created via Paystack, ESCROW transactions
        # via the escrow endpoints, and COMMISSION/REFUND/TRANSFER_OUT by the system.
        transaction_type = serializer.validated_data.get('transaction_type')
        if transaction_type != Transaction.Type.WITHDRAWAL:
            raise drf_serializers.ValidationError(
                f"Cannot create {transaction_type} transactions directly. "
                "Use the appropriate endpoint (e.g., /deposit/, /escrow/<id>/fund/)."
            )

        wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
        amount = serializer.validated_data['amount']

        # SECURITY: Use select_for_update and atomic transaction for withdrawals
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

    # SECURITY: Only allow access to whitelisted settings keys
    ALLOWED_KEYS = ['commission_rate']

    def get_object(self):
        key = self.kwargs.get('key')
        if key not in self.ALLOWED_KEYS:
            from django.http import Http404
            raise Http404("Setting not found")
        return AppSettings.objects.get(key=key)


class EscrowFundJobAPIView(APIView):
    """Client funds a job, placing the amount in escrow.

    If Pandascrow is configured, creates a Pandascrow escrow and returns
    a payment URL for the customer to complete funding externally.
    If Pandascrow is not configured, falls back to the legacy internal
    wallet escrow flow (debit wallet, create ESCROW_HOLD transaction).
    """
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

        if job.status not in [Job.Status.PENDING, Job.Status.ADMIN_APPROVED,
                              Job.Status.ACCEPTED, Job.Status.IN_PROGRESS]:
            return Response(
                {"error": "Escrow can only be funded for active jobs. "
                          "This job is {}.".format(job.get_status_display())},
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
            agreed_price = job.agreed_price or Decimal('0')
            if agreed_price > 0:
                tolerance = agreed_price * Decimal('0.01')
                if amount < (agreed_price - tolerance):
                    return Response(
                        {"error": f"Escrow amount ({amount}) is less than the agreed price ({agreed_price}). "
                                  "Contact support if you need to adjust the escrow amount."},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                if amount > (agreed_price + tolerance):
                    return Response(
                        {"error": f"Escrow amount ({amount}) exceeds the agreed price ({agreed_price}). "
                                  "Contact support if you need to adjust the escrow amount."},
                        status=status.HTTP_400_BAD_REQUEST
                    )
        else:
            amount = job.agreed_price

        MINIMUM_ESCROW = Decimal('100.00')
        if amount < MINIMUM_ESCROW:
            return Response(
                {"error": f"Minimum escrow amount is ₦{MINIMUM_ESCROW}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Check if this job already has a Pandascrow escrow
        existing_pandascrow = getattr(job, 'pandascrow_escrow', None)

        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=job.pk)

            # Re-check escrow after acquiring lock (prevents double-fund)
            if job.escrow_held_amount and job.escrow_held_amount > 0:
                return Response(
                    {"error": "Job already funded"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if existing_pandascrow and existing_pandascrow.status in (
                PandascrowEscrow.Status.INITIALIZED,
                PandascrowEscrow.Status.FUNDED,
            ):
                # Already has an active Pandascrow escrow — return the existing payment URL
                return Response({
                    "message": "Escrow already initialized on Pandascrow.",
                    "escrow_amount": str(amount),
                    "job_id": job.id,
                    "pandascrow_escrow_id": existing_pandascrow.escrow_id,
                    "payment_url": existing_pandascrow.payment_url,
                    "requires_pandascrow_payment": True,
                })

            # Route to Pandascrow or internal escrow based on configuration.
            # If Pandascrow is configured but unavailable, fall back to internal wallet.
            if is_pandascrow_configured():
                try:
                    return self._fund_via_pandascrow(request, job, amount, user)
                except PandascrowAPIError as e:
                    logger.warning(
                        "Pandascrow fund failed for job %s, falling back to internal wallet: %s",
                        job.id, str(e),
                    )
                    # Fall back to internal wallet escrow
                    return self._fund_via_internal_wallet(request, job, amount, user)

    def _fund_via_pandascrow(self, request, job, amount, user):
        """Create escrow on Pandascrow and return payment URL."""
        if not job.artisan:
            # No artisan assigned yet — Pandascrow requires both parties.
            # Raise so the caller can fall back to internal wallet escrow.
            raise PandascrowAPIError("No artisan assigned to this job")

        inspection_period = request.data.get('inspection_period', 3)

        try:
            escrow_id, payment_url = pandascrow_initialize_escrow(
                job=job,
                amount=amount,
                customer=user,
                artisan=job.artisan,
            )
        except PandascrowAPIError as e:
            logger.error("Pandascrow escrow initialization failed for job %s: %s", job.id, str(e))
            raise  # Let the caller fall back to internal wallet

        # Create local PandascrowEscrow record
        pandascrow_escrow = PandascrowEscrow.objects.create(
            job=job,
            escrow_id=escrow_id,
            status=PandascrowEscrow.Status.INITIALIZED,
            amount=amount,
            currency='NGN',
            inspection_period=inspection_period,
            payment_url=payment_url or '',
            buyer_details={
                'name': user.get_full_name() or user.username,
                'email': user.email,
                'phone': getattr(user, 'phone_number', ''),
            },
            seller_details={
                'name': job.artisan.user.get_full_name() or job.artisan.user.username,
                'email': job.artisan.user.email,
                'phone': getattr(job.artisan.user, 'phone_number', ''),
            },
        )

        # Create a PENDING transaction to track this escrow
        wallet, _ = Wallet.objects.get_or_create(user=user)
        Transaction.objects.create(
            wallet=wallet,
            amount=amount,
            transaction_type=Transaction.Type.PANDASCROW_FUND,
            status=Transaction.Status.PENDING,
            reference=f"PESCROW-{job.id}-{uuid.uuid4().hex[:8]}",
            job=job,
            description=f"Pandascrow escrow funding for Job #{job.id}"
        )

        # Set escrow_held_amount on job for backward compatibility
        job.escrow_held_amount = amount
        job.save(update_fields=['escrow_held_amount', 'updated_at'])

        return Response({
            "message": "Escrow initialized on Pandascrow. Complete payment via the payment URL.",
            "escrow_amount": str(amount),
            "job_id": job.id,
            "pandascrow_escrow_id": escrow_id,
            "payment_url": payment_url,
            "requires_pandascrow_payment": True,
        })

    def _fund_via_internal_wallet(self, request, job, amount, user):
        """Legacy internal wallet escrow — debit customer wallet and hold internally."""
        wallet, _ = Wallet.objects.select_for_update().get_or_create(user=user)

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
    """Client confirms job completion, releasing escrow to artisan.

    If the job has a Pandascrow escrow, calls Pandascrow's complete API
    (may require OTP). If no Pandascrow escrow, uses the legacy internal
    wallet release flow (credits artisan wallet minus commission).
    """
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

        # Route to Pandascrow or internal escrow based on escrow type
        pandascrow_escrow = getattr(job, 'pandascrow_escrow', None)
        if pandascrow_escrow:
            return self._release_via_pandascrow(request, job, pandascrow_escrow)
        else:
            return self._release_via_internal_wallet(job)

    def _release_via_pandascrow(self, request, job, pandascrow_escrow):
        """Release escrow via Pandascrow API."""
        if pandascrow_escrow.status not in (
            PandascrowEscrow.Status.FUNDED,
            PandascrowEscrow.Status.INITIALIZED,
        ):
            return Response(
                {"error": f"Cannot release escrow in status '{pandascrow_escrow.get_status_display()}'"},
                status=status.HTTP_400_BAD_REQUEST
            )

        otp = request.data.get('otp')

        try:
            result = pandascrow_complete_escrow(
                escrow_id=pandascrow_escrow.escrow_id,
                otp=otp,
            )
        except PandascrowAPIError as e:
            error_msg = str(e)
            # If OTP is required, return a specific response
            if 'otp' in error_msg.lower() or e.status_code == 400:
                return Response({
                    "error": "OTP required to complete escrow release",
                    "otp_required": True,
                    "escrow_id": pandascrow_escrow.escrow_id,
                }, status=status.HTTP_400_BAD_REQUEST)
            logger.error("Pandascrow escrow completion failed for escrow %s: %s",
                        pandascrow_escrow.escrow_id, error_msg)
            return Response(
                {"error": "Escrow release failed. Please try again or contact support."},
                status=status.HTTP_502_BAD_GATEWAY
            )

        # Update local status optimistically (webhook will confirm)
        with db_transaction.atomic():
            pandascrow_escrow = PandascrowEscrow.objects.select_for_update().get(
                pk=pandascrow_escrow.pk
            )
            pandascrow_escrow.status = PandascrowEscrow.Status.COMPLETED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])

            job.escrow_held_amount = Decimal('0.00')
            if job.status != Job.Status.COMPLETED:
                job.status = Job.Status.COMPLETED
                job.save(update_fields=['status', 'escrow_held_amount', 'updated_at'])
            else:
                job.save(update_fields=['escrow_held_amount', 'updated_at'])

            # Create a PANDASCROW_RELEASE transaction for record-keeping
            wallet, _ = Wallet.objects.get_or_create(user=job.customer)
            Transaction.objects.create(
                wallet=wallet,
                amount=pandascrow_escrow.amount,
                transaction_type=Transaction.Type.PANDASCROW_RELEASE,
                status=Transaction.Status.COMPLETED,
                reference=f"PRELEASE-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Pandascrow escrow released for Job #{job.id}"
            )

        return Response({
            "message": "Escrow released successfully via Pandascrow.",
            "escrow_amount": str(pandascrow_escrow.amount),
            "job_id": job.id,
            "pandascrow_escrow_id": pandascrow_escrow.escrow_id,
        })

    def _release_via_internal_wallet(self, job):
        """Legacy internal wallet escrow release."""
        with db_transaction.atomic():
            artisan_payout, commission_amount = process_escrow_release(job)

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
        ).select_related('customer', 'artisan', 'artisan__user', 'admin_approved_by', 'pandascrow_escrow')


class AdminEscrowReleaseAPIView(APIView):
    """Admin releases escrow for a job. Routes to Pandascrow or internal based on escrow type."""
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

            pandascrow_escrow = getattr(job, 'pandascrow_escrow', None)

            if pandascrow_escrow:
                # Release via Pandascrow
                try:
                    result = pandascrow_complete_escrow(escrow_id=pandascrow_escrow.escrow_id)
                except PandascrowAPIError as e:
                    logger.error("Admin Pandascrow escrow release failed for escrow %s: %s",
                                pandascrow_escrow.escrow_id, str(e))
                    return Response(
                        {"error": "Escrow release failed via Pandascrow. Please try again."},
                        status=status.HTTP_502_BAD_GATEWAY
                    )

                pandascrow_escrow.status = PandascrowEscrow.Status.COMPLETED
                pandascrow_escrow.save(update_fields=['status', 'updated_at'])

                job.escrow_held_amount = Decimal('0.00')
                if job.status != Job.Status.COMPLETED:
                    job.status = Job.Status.COMPLETED
                    job.save(update_fields=['status', 'escrow_held_amount', 'updated_at'])
                else:
                    job.save(update_fields=['escrow_held_amount', 'updated_at'])

                return Response({
                    "message": "Escrow released successfully via Pandascrow by admin.",
                    "escrow_amount": str(pandascrow_escrow.amount),
                    "pandascrow_escrow_id": pandascrow_escrow.escrow_id,
                })
            else:
                # Legacy internal wallet release
                artisan_payout, commission_amount = process_escrow_release(job)
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
    """Admin refunds escrow. Routes to Pandascrow cancel or internal refund based on escrow type."""
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

            pandascrow_escrow = getattr(job, 'pandascrow_escrow', None)

            if pandascrow_escrow:
                # Cancel/refund via Pandascrow
                try:
                    result = pandascrow_cancel_escrow(escrow_id=pandascrow_escrow.escrow_id)
                except PandascrowAPIError as e:
                    logger.error("Admin Pandascrow escrow refund failed for escrow %s: %s",
                                pandascrow_escrow.escrow_id, str(e))
                    return Response(
                        {"error": "Escrow refund failed via Pandascrow. Please try again."},
                        status=status.HTTP_502_BAD_GATEWAY
                    )

                pandascrow_escrow.status = PandascrowEscrow.Status.REFUNDED
                pandascrow_escrow.save(update_fields=['status', 'updated_at'])

                refund_amount = job.escrow_held_amount
                job.escrow_held_amount = Decimal('0.00')
                job.save(update_fields=['escrow_held_amount', 'updated_at'])

                # Create a PANDASCROW_REFUND transaction for record-keeping
                wallet, _ = Wallet.objects.get_or_create(user=job.customer)
                Transaction.objects.create(
                    wallet=wallet,
                    amount=refund_amount,
                    transaction_type=Transaction.Type.PANDASCROW_REFUND,
                    status=Transaction.Status.COMPLETED,
                    reference=f"PREFUND-{job.id}-{uuid.uuid4().hex[:8]}",
                    job=job,
                    description=f"Pandascrow escrow refund for Job #{job.id}"
                )

                return Response({
                    "message": "Escrow refunded successfully via Pandascrow by admin.",
                    "refund_amount": str(refund_amount),
                    "pandascrow_escrow_id": pandascrow_escrow.escrow_id,
                })
            else:
                # Legacy internal wallet refund
                refund_amount = request.data.get('refund_amount')
                if refund_amount is not None:
                    refund_amount = Decimal(str(refund_amount))
                else:
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

    SECURITY: This view bypasses DRF's parser system and reads the raw
    request body directly for HMAC verification and JSON parsing. This
    prevents DRF parsers from consuming request.body before the HMAC
    check, which could cause signature mismatches or bypass attempts.

    Supports:
    - charge.success: Credits wallet for completed deposits
    - charge.failed: Marks transaction as failed
    """
    permission_classes = []  # No auth required — Paystack calls this server-to-server
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        # SECURITY: Use raw request.body directly for HMAC verification
        # instead of request.data, which has been parsed by DRF and may
        # not match the exact bytes Paystack signed.
        import json
        import hmac
        import hashlib

        raw_body = request.body

        # Verify Paystack signature against the raw body
        paystack_signature = request.headers.get('x-paystack-signature', '')
        if not paystack_signature:
            logger.warning("Paystack webhook: missing signature header")
            return Response({'error': 'Missing signature'}, status=status.HTTP_401_UNAUTHORIZED)

        secret = settings.PAYSTACK_SECRET_KEY
        expected_signature = hmac.new(
            secret.encode('utf-8'),
            raw_body,
            hashlib.sha512
        ).hexdigest()

        if not hmac.compare_digest(paystack_signature, expected_signature):
            logger.warning("Paystack webhook: invalid signature")
            return Response({'error': 'Invalid signature'}, status=status.HTTP_401_UNAUTHORIZED)

        # Parse the raw body as JSON (bypassing DRF's parser entirely)
        try:
            payload = json.loads(raw_body)
        except (json.JSONDecodeError, ValueError):
            logger.warning("Paystack webhook: invalid JSON body")
            return Response({'error': 'Invalid JSON'}, status=status.HTTP_400_BAD_REQUEST)

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


class PaystackTransferWebhookView(APIView):
    """Handle Paystack transfer webhook events for withdrawal status updates.

    This endpoint receives transfer.success, transfer.failed, and transfer.reversed
    events from Paystack to update withdrawal transaction statuses.

    Like the charge webhook, this does NOT require authentication — Paystack calls
    this server-to-server. HMAC signature verification ensures authenticity.
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        # SECURITY: Verify HMAC signature against raw body
        import json as json_module
        import hmac
        import hashlib

        raw_body = request.body

        paystack_signature = request.headers.get('x-paystack-signature', '')
        if not paystack_signature:
            logger.warning("Paystack transfer webhook: missing signature header")
            return Response({'error': 'Missing signature'}, status=status.HTTP_401_UNAUTHORIZED)

        secret = settings.PAYSTACK_SECRET_KEY
        expected_signature = hmac.new(
            secret.encode('utf-8'),
            raw_body,
            hashlib.sha512
        ).hexdigest()

        if not hmac.compare_digest(paystack_signature, expected_signature):
            logger.warning("Paystack transfer webhook: invalid signature")
            return Response({'error': 'Invalid signature'}, status=status.HTTP_401_UNAUTHORIZED)

        # Parse raw body (bypass DRF parsers)
        try:
            payload = json_module.loads(raw_body)
        except (json_module.JSONDecodeError, ValueError):
            logger.warning("Paystack transfer webhook: invalid JSON body")
            return Response({'error': 'Invalid JSON'}, status=status.HTTP_400_BAD_REQUEST)

        event = payload.get('event', '')
        data = payload.get('data', {})

        if event == 'transfer.success':
            return self._handle_transfer_success(data)
        elif event == 'transfer.failed':
            return self._handle_transfer_failed(data)
        elif event == 'transfer.reversed':
            return self._handle_transfer_reversed(data)
        else:
            logger.info("Paystack transfer webhook: unhandled event '%s'", event)
            return Response({'status': 'acknowledged'})

    def _handle_transfer_success(self, data):
        """Mark a TRANSFER_OUT transaction as COMPLETED when Paystack confirms success."""
        transfer_code = data.get('transfer_code', '')
        reference = data.get('reference', '')

        # Try to find transaction by reference first, then by transfer_code
        transaction = None
        if reference:
            try:
                transaction = Transaction.objects.get(reference=reference)
            except Transaction.DoesNotExist:
                pass

        if transaction is None and transfer_code:
            try:
                transaction = Transaction.objects.get(transfer_code=transfer_code)
            except Transaction.DoesNotExist:
                pass

        if transaction is None:
            logger.warning(
                "Paystack transfer webhook: no matching transaction for ref=%s, code=%s",
                reference, transfer_code
            )
            return Response({'status': 'no matching transaction'})

        # Idempotency check
        if transaction.status == Transaction.Status.COMPLETED:
            logger.info("Paystack transfer webhook: transaction %s already completed", transaction.reference)
            return Response({'status': 'already processed'})

        if transaction.transaction_type != Transaction.Type.TRANSFER_OUT:
            logger.warning(
                "Paystack transfer webhook: transaction %s is type %s, not TRANSFER_OUT",
                transaction.reference, transaction.transaction_type
            )
            return Response({'status': 'ignored'})

        transaction.status = Transaction.Status.COMPLETED
        if transfer_code:
            transaction.transfer_code = transfer_code
        transaction.save(update_fields=['status', 'transfer_code'])

        # Verify amount matches (in kobo) for extra security
        amount_kobo = data.get('amount', 0)
        expected_amount_kobo = int(transaction.amount * 100)
        if amount_kobo and amount_kobo != expected_amount_kobo:
            logger.error(
                "Paystack transfer webhook: AMOUNT MISMATCH for %s — expected %d kobo, got %d kobo. "
                "Transaction was already marked COMPLETED — manual review required.",
                transaction.reference, expected_amount_kobo, amount_kobo
            )
            # Don't revert — flag for manual review
        else:
            logger.info(
                "Paystack transfer webhook: withdrawal %s completed successfully (₦%s)",
                transaction.reference, transaction.amount
            )

        # Notify user via SMS
        try:
            user = transaction.wallet.user
            message = (
                f"Hi {user.username}, your withdrawal of ₦{transaction.amount} has been "
                f"completed successfully. Reference: {transaction.reference}"
            )
            send_sms(user.phone_number, message)
        except Exception:
            logger.warning("Failed to send withdrawal completion SMS to user %s", transaction.wallet.user.pk)

        return Response({'status': 'success'})

    def _handle_transfer_failed(self, data):
        """Mark a TRANSFER_OUT transaction as FAILED and refund the wallet."""
        transfer_code = data.get('transfer_code', '')
        reference = data.get('reference', '')

        transaction = None
        if reference:
            try:
                transaction = Transaction.objects.get(reference=reference)
            except Transaction.DoesNotExist:
                pass

        if transaction is None and transfer_code:
            try:
                transaction = Transaction.objects.get(transfer_code=transfer_code)
            except Transaction.DoesNotExist:
                pass

        if transaction is None:
            logger.warning(
                "Paystack transfer webhook (failed): no matching transaction for ref=%s, code=%s",
                reference, transfer_code
            )
            return Response({'status': 'no matching transaction'})

        if transaction.status == Transaction.Status.FAILED:
            logger.info("Paystack transfer webhook: transaction %s already marked FAILED", transaction.reference)
            return Response({'status': 'already processed'})

        with db_transaction.atomic():
            transaction.status = Transaction.Status.FAILED
            if transfer_code:
                transaction.transfer_code = transfer_code
            transaction.save(update_fields=['status', 'transfer_code'])

            # Refund the wallet — the transfer failed so money should go back
            wallet = Wallet.objects.select_for_update().get(pk=transaction.wallet.pk)
            wallet.balance += transaction.amount
            wallet.save(update_fields=['balance', 'updated_at'])

            # Create a REFUND transaction
            Transaction.objects.create(
                wallet=wallet,
                amount=transaction.amount,
                transaction_type=Transaction.Type.REFUND,
                status=Transaction.Status.COMPLETED,
                reference=f"REFUND-{transaction.reference}",
                description=f"Refund for failed withdrawal {transaction.reference}"
            )

        logger.info(
            "Paystack transfer webhook: withdrawal %s FAILED — ₦%s refunded to wallet",
            transaction.reference, transaction.amount
        )

        # Notify user
        try:
            user = transaction.wallet.user
            message = (
                f"Hi {user.username}, your withdrawal of ₦{transaction.amount} failed. "
                f"The amount has been refunded to your wallet. Reference: {transaction.reference}"
            )
            send_sms(user.phone_number, message)
        except Exception:
            logger.warning("Failed to send withdrawal failure SMS to user %s", transaction.wallet.user.pk)

        return Response({'status': 'processed'})

    def _handle_transfer_reversed(self, data):
        """Handle a reversed transfer — refund the wallet."""
        # Reversal is treated similarly to failure
        return self._handle_transfer_failed(data)


# ========================
# Pandascrow Webhook & Escrow Status
# ========================

class PandascrowWebhookView(APIView):
    """Handle Pandascrow webhook events for escrow status updates.

    This endpoint receives escrow.paid, escrow.completed, and escrow.cancelled
    events from Pandascrow to update local escrow status.

    Like the Paystack webhook, this does NOT require authentication — Pandascrow
    calls this server-to-server. HMAC-SHA256 signature verification ensures authenticity.
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request, *args, **kwargs):
        raw_body = request.body

        # Verify Pandascrow signature
        pandascrow_signature = request.headers.get('X-Pandascrow-Signature', '')
        if not pandascrow_signature:
            logger.warning("Pandascrow webhook: missing signature header")
            return Response({'error': 'Missing signature'}, status=status.HTTP_401_UNAUTHORIZED)

        if not verify_pandascrow_webhook_signature(raw_body, pandascrow_signature):
            logger.warning("Pandascrow webhook: invalid signature")
            return Response({'error': 'Invalid signature'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            payload = json_module.loads(raw_body)
        except (json_module.JSONDecodeError, ValueError):
            logger.warning("Pandascrow webhook: invalid JSON body")
            return Response({'error': 'Invalid JSON'}, status=status.HTTP_400_BAD_REQUEST)

        event = payload.get('event', '')
        data = payload.get('data', {})

        if event == 'escrow.paid':
            return self._handle_escrow_paid(data)
        elif event == 'escrow.completed':
            return self._handle_escrow_completed(data)
        elif event == 'escrow.cancelled':
            return self._handle_escrow_cancelled(data)
        else:
            logger.info("Pandascrow webhook: unhandled event '%s'", event)
            return Response({'status': True, 'message': 'acknowledged'})

    def _handle_escrow_paid(self, data):
        """Process escrow.paid — customer has paid into the escrow."""
        escrow_id = data.get('escrow_id') or data.get('data', {}).get('escrow_id') if isinstance(data.get('data'), dict) else data.get('escrow_id')

        if not escrow_id:
            logger.warning("Pandascrow webhook: escrow.paid missing escrow_id")
            return Response({'error': 'Missing escrow_id'}, status=status.HTTP_400_BAD_REQUEST)

        with db_transaction.atomic():
            try:
                pandascrow_escrow = PandascrowEscrow.objects.select_for_update().get(escrow_id=escrow_id)
            except PandascrowEscrow.DoesNotExist:
                logger.warning("Pandascrow webhook: escrow.paid — no PandascrowEscrow found for %s", escrow_id)
                return Response({'error': 'Escrow not found'}, status=status.HTTP_404_NOT_FOUND)

            # Idempotency check
            if pandascrow_escrow.status == PandascrowEscrow.Status.FUNDED:
                logger.info("Pandascrow webhook: escrow %s already marked as FUNDED", escrow_id)
                return Response({'status': True, 'message': 'already processed'})

            pandascrow_escrow.status = PandascrowEscrow.Status.FUNDED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])

            # Update the PANDASCROW_FUND transaction to COMPLETED
            Transaction.objects.filter(
                job=pandascrow_escrow.job,
                transaction_type=Transaction.Type.PANDASCROW_FUND,
                status=Transaction.Status.PENDING,
            ).update(status=Transaction.Status.COMPLETED)

            job = pandascrow_escrow.job
            # Notify artisan
            try:
                artisan_user = job.artisan.user if job.artisan else None
                if artisan_user:
                    message = (
                        f"Hi {artisan_user.username}, escrow payment of ₦{pandascrow_escrow.amount} "
                        f"has been received for Job #{job.id}. You can now begin work."
                    )
                    send_sms(getattr(artisan_user, 'phone_number', ''), message)
            except Exception:
                logger.warning("Failed to send escrow.paid notification for job %s", job.id)

        logger.info("Pandascrow webhook: escrow %s paid successfully", escrow_id)
        return Response({'status': True, 'message': 'processed'})

    def _handle_escrow_completed(self, data):
        """Process escrow.completed — escrow has been completed and funds disbursed."""
        escrow_id = data.get('escrow_id') or data.get('data', {}).get('escrow_id') if isinstance(data.get('data'), dict) else data.get('escrow_id')

        if not escrow_id:
            logger.warning("Pandascrow webhook: escrow.completed missing escrow_id")
            return Response({'error': 'Missing escrow_id'}, status=status.HTTP_400_BAD_REQUEST)

        with db_transaction.atomic():
            try:
                pandascrow_escrow = PandascrowEscrow.objects.select_for_update().get(escrow_id=escrow_id)
            except PandascrowEscrow.DoesNotExist:
                logger.warning("Pandascrow webhook: escrow.completed — no PandascrowEscrow found for %s", escrow_id)
                return Response({'error': 'Escrow not found'}, status=status.HTTP_404_NOT_FOUND)

            # Idempotency check
            if pandascrow_escrow.status == PandascrowEscrow.Status.COMPLETED:
                logger.info("Pandascrow webhook: escrow %s already marked as COMPLETED", escrow_id)
                return Response({'status': True, 'message': 'already processed'})

            pandascrow_escrow.status = PandascrowEscrow.Status.COMPLETED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])

            # Extract fee info if available
            escrow_data = data.get('escrow_data', data.get('data', {}))
            if isinstance(escrow_data, dict):
                pandascrow_fee = escrow_data.get('pandascrow_fee')
                partner_fee = escrow_data.get('partner_escrow_fee')
                if pandascrow_fee:
                    pandascrow_escrow.pandascrow_fee = Decimal(str(pandascrow_fee))
                if partner_fee:
                    pandascrow_escrow.partner_fee = Decimal(str(partner_fee))
                if pandascrow_fee or partner_fee:
                    pandascrow_escrow.save(update_fields=['pandascrow_fee', 'partner_fee', 'updated_at'])

            job = pandascrow_escrow.job
            job.escrow_held_amount = Decimal('0.00')
            if job.status != Job.Status.COMPLETED:
                job.status = Job.Status.COMPLETED
                job.save(update_fields=['status', 'escrow_held_amount', 'updated_at'])
            else:
                job.save(update_fields=['escrow_held_amount', 'updated_at'])

            # Create PANDASCROW_RELEASE transaction for record-keeping
            wallet, _ = Wallet.objects.get_or_create(user=job.customer)
            Transaction.objects.create(
                wallet=wallet,
                amount=pandascrow_escrow.amount,
                transaction_type=Transaction.Type.PANDASCROW_RELEASE,
                status=Transaction.Status.COMPLETED,
                reference=f"PRELEASE-WH-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Pandascrow escrow completed (webhook) for Job #{job.id}"
            )

        logger.info("Pandascrow webhook: escrow %s completed successfully", escrow_id)
        return Response({'status': True, 'message': 'processed'})

    def _handle_escrow_cancelled(self, data):
        """Process escrow.cancelled — escrow has been cancelled/refunded."""
        escrow_id = data.get('escrow_id') or data.get('data', {}).get('escrow_id') if isinstance(data.get('data'), dict) else data.get('escrow_id')

        if not escrow_id:
            logger.warning("Pandascrow webhook: escrow.cancelled missing escrow_id")
            return Response({'error': 'Missing escrow_id'}, status=status.HTTP_400_BAD_REQUEST)

        with db_transaction.atomic():
            try:
                pandascrow_escrow = PandascrowEscrow.objects.select_for_update().get(escrow_id=escrow_id)
            except PandascrowEscrow.DoesNotExist:
                logger.warning("Pandascrow webhook: escrow.cancelled — no PandascrowEscrow found for %s", escrow_id)
                return Response({'error': 'Escrow not found'}, status=status.HTTP_404_NOT_FOUND)

            # Idempotency check
            if pandascrow_escrow.status in (PandascrowEscrow.Status.CANCELLED, PandascrowEscrow.Status.REFUNDED):
                logger.info("Pandascrow webhook: escrow %s already marked as %s", escrow_id, pandascrow_escrow.status)
                return Response({'status': True, 'message': 'already processed'})

            pandascrow_escrow.status = PandascrowEscrow.Status.REFUNDED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])

            job = pandascrow_escrow.job
            refund_amount = job.escrow_held_amount
            job.escrow_held_amount = Decimal('0.00')
            job.save(update_fields=['escrow_held_amount', 'updated_at'])

            # Create PANDASCROW_REFUND transaction
            wallet, _ = Wallet.objects.get_or_create(user=job.customer)
            Transaction.objects.create(
                wallet=wallet,
                amount=refund_amount or pandascrow_escrow.amount,
                transaction_type=Transaction.Type.PANDASCROW_REFUND,
                status=Transaction.Status.COMPLETED,
                reference=f"PREFUND-WH-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Pandascrow escrow refund (webhook) for Job #{job.id}"
            )

            # Notify customer
            try:
                message = (
                    f"Hi {job.customer.username}, the escrow for Job #{job.id} has been cancelled "
                    f"and ₦{refund_amount or pandascrow_escrow.amount} will be refunded."
                )
                send_sms(getattr(job.customer, 'phone_number', ''), message)
            except Exception:
                logger.warning("Failed to send escrow cancellation SMS for job %s", job.id)

        logger.info("Pandascrow webhook: escrow %s cancelled/refunded", escrow_id)
        return Response({'status': True, 'message': 'processed'})


class EscrowStatusAPIView(APIView):
    """Get the current escrow status for a job, including Pandascrow status if applicable."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        try:
            job = Job.objects.select_related('pandascrow_escrow').get(pk=pk)
        except Job.DoesNotExist:
            return Response({"error": "Job not found"}, status=status.HTTP_404_NOT_FOUND)

        # Basic access check
        user = request.user
        if job.customer != user and (not job.artisan or job.artisan.user != user) and user.role != User.Role.ADMIN:
            return Response({"error": "Not authorized"}, status=status.HTTP_403_FORBIDDEN)

        result = {
            "job_id": job.id,
            "escrow_held_amount": str(job.escrow_held_amount) if job.escrow_held_amount else "0.00",
            "job_status": job.status,
        }

        pandascrow_escrow = getattr(job, 'pandascrow_escrow', None)
        if pandascrow_escrow:
            result["pandascrow_escrow"] = PandascrowEscrowSerializer(pandascrow_escrow).data
            result["escrow_type"] = "pandascrow"
        else:
            result["escrow_type"] = "internal"

        return Response(result)


class EscrowReleaseOtpAPIView(APIView):
    """Submit OTP for Pandascrow escrow release confirmation.

    Some Pandascrow escrow releases require an OTP sent to the buyer's phone/email.
    This endpoint allows the customer to submit that OTP.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        user = request.user
        if user.role != User.Role.CUSTOMER:
            return Response(
                {"error": "Only customers can release escrow"},
                status=status.HTTP_403_FORBIDDEN
            )

        serializer = EscrowReleaseOtpSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        otp = serializer.validated_data['otp']

        try:
            job = Job.objects.get(pk=pk)
        except Job.DoesNotExist:
            return Response({"error": "Job not found"}, status=status.HTTP_404_NOT_FOUND)

        if job.customer != user:
            return Response({"error": "Not your job"}, status=status.HTTP_403_FORBIDDEN)

        pandascrow_escrow = getattr(job, 'pandascrow_escrow', None)
        if not pandascrow_escrow:
            return Response(
                {"error": "This job does not have a Pandascrow escrow"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if pandascrow_escrow.status not in (
            PandascrowEscrow.Status.FUNDED,
            PandascrowEscrow.Status.INITIALIZED,
        ):
            return Response(
                {"error": f"Cannot submit OTP for escrow in status '{pandascrow_escrow.get_status_display()}'"},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            result = pandascrow_complete_escrow(
                escrow_id=pandascrow_escrow.escrow_id,
                otp=otp,
            )
        except PandascrowAPIError as e:
            logger.error("Pandascrow OTP completion failed for escrow %s: %s",
                        pandascrow_escrow.escrow_id, str(e))
            return Response(
                {"error": "OTP verification failed. Please check the code and try again."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Update local status
        with db_transaction.atomic():
            pandascrow_escrow = PandascrowEscrow.objects.select_for_update().get(pk=pandascrow_escrow.pk)
            pandascrow_escrow.status = PandascrowEscrow.Status.COMPLETED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])

            job.escrow_held_amount = Decimal('0.00')
            if job.status != Job.Status.COMPLETED:
                job.status = Job.Status.COMPLETED
                job.save(update_fields=['status', 'escrow_held_amount', 'updated_at'])
            else:
                job.save(update_fields=['escrow_held_amount', 'updated_at'])

            wallet, _ = Wallet.objects.get_or_create(user=job.customer)
            Transaction.objects.create(
                wallet=wallet,
                amount=pandascrow_escrow.amount,
                transaction_type=Transaction.Type.PANDASCROW_RELEASE,
                status=Transaction.Status.COMPLETED,
                reference=f"PRELEASE-OTP-{job.id}-{uuid.uuid4().hex[:8]}",
                job=job,
                description=f"Pandascrow escrow released (OTP) for Job #{job.id}"
            )

        return Response({
            "message": "Escrow released successfully.",
            "escrow_amount": str(pandascrow_escrow.amount),
            "job_id": job.id,
            "pandascrow_escrow_id": pandascrow_escrow.escrow_id,
        })


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