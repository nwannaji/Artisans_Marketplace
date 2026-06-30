from rest_framework import serializers
from .models import Wallet, Transaction, AppSettings, BankAccount, PandascrowEscrow
from accounts.models import User
from bookings.models import Job


class WalletSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(source='user.id', read_only=True)

    class Meta:
        model = Wallet
        fields = ['user_id', 'balance', 'created_at', 'updated_at']


class TransactionSerializer(serializers.ModelSerializer):
    wallet = WalletSerializer(read_only=True)
    job_id = serializers.PrimaryKeyRelatedField(queryset=Job.objects.all(), source='job', required=False, allow_null=True)

    class Meta:
        model = Transaction
        fields = ['wallet', 'amount', 'transaction_type', 'status', 'reference', 'job_id', 'description', 'created_at']

    def create(self, validated_data):
        return Transaction.objects.create(**validated_data)

    def update(self, instance, validated_data):
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        return instance


class AppSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = AppSettings
        fields = ['key', 'value']


class EscrowFundSerializer(serializers.Serializer):
    """Serializer for funding a job escrow. Amount defaults to job.agreed_price if not provided."""
    amount = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True
    )
    inspection_period = serializers.IntegerField(
        required=False, default=3, min_value=1, max_value=30,
        help_text="Number of days for buyer inspection (default: 3)"
    )


class EscrowReleaseOtpSerializer(serializers.Serializer):
    """Serializer for submitting OTP for Pandascrow escrow release."""
    otp = serializers.CharField(
        max_length=10, required=True,
        help_text="One-time password from Pandascrow for escrow release confirmation"
    )


class EscrowReleaseSerializer(serializers.Serializer):
    """Serializer for releasing escrow. No input fields needed — job ID from URL is sufficient."""
    pass


class BankAccountSerializer(serializers.ModelSerializer):
    """Serializer for artisan bank accounts (Paystack payout destinations)."""
    account_number_display = serializers.CharField(source='account_number', read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            'id', 'bank_code', 'account_number', 'account_number_display',
            'account_name', 'is_verified', 'is_default', 'paystack_recipient_code',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'is_verified', 'paystack_recipient_code', 'created_at', 'updated_at']
        extra_kwargs = {
            'account_number': {'write_only': False},
        }

    def validate_account_number(self, value):
        if not value.isdigit() or len(value) != 10:
            raise serializers.ValidationError("Account number must be exactly 10 digits.")
        return value

    def validate_bank_code(self, value):
        if not value.isdigit():
            raise serializers.ValidationError("Bank code must be numeric.")
        return value


class WithdrawalSerializer(serializers.Serializer):
    """Serializer for initiating a withdrawal to a bank account."""
    amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    bank_account_id = serializers.IntegerField(required=False, allow_null=True)

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError("Amount must be positive.")
        return value


class PandascrowEscrowSerializer(serializers.ModelSerializer):
    """Serializer for PandascrowEscrow model — read-only for API responses."""
    customer_username = serializers.CharField(source='job.customer.username', read_only=True)
    artisan_username = serializers.CharField(
        source='job.artisan.user.username', read_only=True, default=None
    )
    job_description = serializers.CharField(source='job.description', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = PandascrowEscrow
        fields = [
            'id', 'escrow_id', 'job', 'status', 'status_display', 'amount', 'currency',
            'pandascrow_fee', 'partner_fee', 'payment_url',
            'inspection_period', 'buyer_details', 'seller_details',
            'created_at', 'updated_at',
            'customer_username', 'artisan_username', 'job_description',
        ]
        read_only_fields = [
            'escrow_id', 'status', 'pandascrow_fee', 'partner_fee',
            'payment_url', 'created_at', 'updated_at',
        ]