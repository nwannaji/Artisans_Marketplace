from rest_framework import generics, permissions, status
from rest_framework.response import Response
from django.db import transaction
from django.utils import timezone

from django_Backend.bookings import serializers
from .models import Wallet, Transaction, WithdrawalRequest
from .serializers import (
    WalletSerializer, 
    TransactionSerializer,
    WithdrawalRequestSerializer,
    DepositSerializer
)
from bookings.models import Job
from accounts.models import User

class WalletDetailAPIView(generics.RetrieveAPIView):
    serializer_class = WalletSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
        return wallet

class TransactionListAPIView(generics.ListAPIView):
    serializer_class = TransactionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
        return Transaction.objects.filter(wallet=wallet).order_by('-created_at')

class DepositCreateAPIView(generics.CreateAPIView):
    serializer_class = DepositSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        with transaction.atomic():
            wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
            amount = serializer.validated_data['amount']
            
            # Create deposit transaction
            Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.DEPOSIT,
                status=Transaction.Status.COMPLETED,
                reference=f"DEP_{self.request.user.id}_{timezone.now().timestamp()}"
            )
            
            # Update wallet balance
            wallet.balance += amount
            wallet.save()

class WithdrawalRequestCreateAPIView(generics.CreateAPIView):
    serializer_class = WithdrawalRequestSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        with transaction.atomic():
            wallet, _ = Wallet.objects.get_or_create(user=self.request.user)
            amount = serializer.validated_data['amount']
            
            if wallet.balance < amount:
                raise serializers.ValidationError(
                    {"error": "Insufficient balance"}
                )
            
            # Create withdrawal request
            withdrawal = WithdrawalRequest.objects.create(
                wallet=wallet,
                amount=amount,
                bank_account=serializer.validated_data['bank_account'],
                bank_name=serializer.validated_data['bank_name'],
                status=WithdrawalRequest.Status.PENDING
            )
            
            # Deduct from wallet immediately
            Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.WITHDRAWAL,
                status=Transaction.Status.PENDING,
                reference=f"WDR_{withdrawal.id}"
            )
            
            wallet.balance -= amount
            wallet.save()

class ProcessPaymentAPIView(generics.CreateAPIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, job_id):
        with transaction.atomic():
            try:
                job = Job.objects.get(id=job_id)
            except Job.DoesNotExist:
                return Response(
                    {"error": "Job not found"},
                    status=status.HTTP_404_NOT_FOUND
                )

            if job.customer != request.user:
                return Response(
                    {"error": "You can only pay for your own jobs"},
                    status=status.HTTP_403_FORBIDDEN
                )

            if job.status != Job.Status.COMPLETED:
                return Response(
                    {"error": "Job must be completed before payment"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            customer_wallet, _ = Wallet.objects.get_or_create(user=job.customer)
            artisan_wallet, _ = Wallet.objects.get_or_create(user=job.artisan.user)

            if customer_wallet.balance < job.agreed_price:
                return Response(
                    {"error": "Insufficient wallet balance"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Calculate commission (10%)
            commission = job.agreed_price * 0.1
            artisan_amount = job.agreed_price - commission

            # Customer payment transaction
            Transaction.objects.create(
                wallet=customer_wallet,
                amount=job.agreed_price,
                transaction_type=Transaction.Type.PAYMENT,
                status=Transaction.Status.COMPLETED,
                job=job,
                reference=f"PAY_{job.id}"
            )

            # Artisan receipt transaction
            Transaction.objects.create(
                wallet=artisan_wallet,
                amount=artisan_amount,
                transaction_type=Transaction.Type.PAYMENT,
                status=Transaction.Status.PENDING,  # Will be completed after payout delay
                job=job,
                reference=f"REC_{job.id}"
            )

            # Commission transaction
            admin_wallet, _ = Wallet.objects.get_or_create(user=User.objects.get(role=User.Role.ADMIN))
            Transaction.objects.create(
                wallet=admin_wallet,
                amount=commission,
                transaction_type=Transaction.Type.COMMISSION,
                status=Transaction.Status.COMPLETED,
                job=job,
                reference=f"COM_{job.id}"
            )

            # Update balances
            customer_wallet.balance -= job.agreed_price
            artisan_wallet.balance += artisan_amount
            admin_wallet.balance += commission

            customer_wallet.save()
            artisan_wallet.save()
            admin_wallet.save()

            job.status = Job.Status.COMPLETED
            job.save()

            return Response(
                {"message": "Payment processed successfully"},
                status=status.HTTP_200_OK
            )