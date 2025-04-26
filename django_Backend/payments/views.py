from rest_framework import generics, permissions, status
from rest_framework.response import Response

from payments.utils import send_sms
from .models import Wallet, Transaction, AppSettings
from  .serializers import WalletSerializer, TransactionSerializer, AppSettingsSerializer
from django.db import transaction as db_transaction
from accounts.models import User

class WalletDetailAPIView(generics.RetrieveAPIView):
    queryset = Wallet.objects.all()
    serializer_class = WalletSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user.wallet  # Fetch wallet for the logged-in user

class TransactionListCreateAPIView(generics.ListCreateAPIView):
    queryset = Transaction.objects.all()
    serializer_class = TransactionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Filter transactions for the logged-in user's wallet
        user = self.request.user
        return Transaction.objects.filter(wallet=user.wallet)

    def perform_create(self, serializer):
        # Logic for creating a new transaction, ensure balance is sufficient for payment/withdrawal
        wallet = self.request.user.wallet
        amount = serializer.validated_data['amount']
        transaction_type = serializer.validated_data['transaction_type']

        if transaction_type == Transaction.Type.PAYMENT and wallet.balance < amount:
            raise serializer.ValidationError("Insufficient funds for payment.")

        # Deduct balance for payments and withdrawals
        if transaction_type in [Transaction.Type.PAYMENT, Transaction.Type.WITHDRAWAL]:
            wallet.balance -= amount
            wallet.save()

        serializer.save(wallet=wallet)  # Save the transaction with the wallet

class TransactionUpdateAPIView(generics.UpdateAPIView):
    queryset = Transaction.objects.all()
    serializer_class = TransactionSerializer
    permission_classes = [permissions.IsAdminUser]  # Admin can update transaction status

    def perform_update(self, serializer):
        # For example, handling payment completion
        instance = serializer.save()

        if instance.status == Transaction.Status.COMPLETED:
            # Credit the wallet if it's a completed payment
            if instance.transaction_type == Transaction.Type.PAYMENT:
                wallet = instance.wallet
                wallet.balance += instance.amount
                wallet.save()

        return instance

class AppSettingsRetrieveUpdateAPIView(generics.RetrieveUpdateAPIView):
    queryset = AppSettings.objects.all()
    serializer_class = AppSettingsSerializer
    permission_classes = [permissions.IsAdminUser]  # Only admin can update settings

    def get_object(self):
        # Retrieve a setting by key
        key = self.kwargs.get('key')
        return AppSettings.objects.get(key=key)



import requests
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from .models import Transaction, Wallet
from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from .serializers import TransactionSerializer

class PaystackPaymentView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        # Get the amount and reference from the request data
        amount = request.data.get('amount')
        job_id = request.data.get('job_id')

        # Check if the wallet has enough funds
        wallet = request.user.wallet
        if wallet.balance < amount:
            return Response({'error': 'Insufficient funds'}, status=status.HTTP_400_BAD_REQUEST)

        # Initialize payment
        reference = f"paystack-{wallet.user.id}-{job_id}"  # Create a unique reference
        url = f"{settings.PAYSTACK_API_URL}/transaction/initialize"
        headers = {
            'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
            'Content-Type': 'application/json',
        }
        data = {
            'amount': int(amount * 100),  # Amount should be in kobo (100 kobo = 1 Naira)
            'email': wallet.user.email,
            'reference': reference,
            'callback_url': 'https://yourdomain.com/paystack/callback/',  # Change to your actual callback URL
        }
        
        response = requests.post(url, json=data, headers=headers)
        result = response.json()

        if response.status_code == 200:
            # Store the transaction
            transaction = Transaction.objects.create(
                wallet=wallet,
                amount=amount,
                transaction_type=Transaction.Type.PAYMENT,
                status=Transaction.Status.PENDING,
                reference=reference,
                job_id=job_id
            )

            return Response({'authorization_url': result['data']['authorization_url']})
        else:
            return Response({'error': result.get('message', 'Payment initialization failed.')}, status=status.HTTP_400_BAD_REQUEST)

class PaystackPaymentCallbackView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        reference = request.data.get('reference')

        # Verify the payment with Paystack API
        url = f"{settings.PAYSTACK_API_URL}/transaction/verify/{reference}"
        headers = {
            'Authorization': f"Bearer {settings.PAYSTACK_SECRET_KEY}",
        }
        response = requests.get(url, headers=headers)
        result = response.json()

        if response.status_code == 200 and result['data']['status'] == 'success':
            # Payment was successful, update transaction status
            transaction = get_object_or_404(Transaction, reference=reference)
            transaction.status = Transaction.Status.COMPLETED
            transaction.save()

            # Update wallet balance
            wallet = transaction.wallet
            wallet.balance -= transaction.amount
            wallet.save()

            # Notify user about successful payment
            self.send_payment_notification(wallet.user, transaction)

            return Response({'status': 'Payment successful'})

        else:
            return Response({'error': 'Payment verification failed'}, status=status.HTTP_400_BAD_REQUEST)

    def send_payment_notification(self, user, transaction):
        message = (
            f"Hi {user.username}, your payment of ₦{transaction.amount} was successful.\n"
            f"Reference: {transaction.reference}\n"
            "Thank you for your patronage."
        )
        send_sms(user.phone, message)


