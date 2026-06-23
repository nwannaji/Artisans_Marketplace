from decimal import Decimal
from django.db import models
from accounts.models import User
from bookings.models import Job
from django.core.validators import MinValueValidator


class Wallet(models.Model):
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='wallet'
    )
    balance = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(0)]
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                check=models.Q(balance__gte=0),
                name='wallet_balance_nonnegative',
            ),
        ]

    def __str__(self):
        return f"{self.user.username}'s Wallet - ₦{self.balance}"


class Transaction(models.Model):
    class Type(models.TextChoices):
        DEPOSIT = 'DEPOSIT', 'Deposit'
        WITHDRAWAL = 'WITHDRAWAL', 'Withdrawal'
        TRANSFER_OUT = 'TRANSFER_OUT', 'Bank Transfer'
        COMMISSION = 'COMMISSION', 'Commission'
        REFUND = 'REFUND', 'Refund'
        ESCROW_HOLD = 'ESCROW_HOLD', 'Escrow Hold'
        ESCROW_RELEASE = 'ESCROW_RELEASE', 'Escrow Release'

    class Status(models.TextChoices):
        PENDING = 'PENDING', 'Pending'
        COMPLETED = 'COMPLETED', 'Completed'
        FAILED = 'FAILED', 'Failed'

    wallet = models.ForeignKey(
        Wallet,
        on_delete=models.CASCADE,
        related_name='transactions'
    )
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    transaction_type = models.CharField(max_length=20, choices=Type.choices, db_index=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    reference = models.CharField(max_length=100, unique=True, db_index=True)
    job = models.ForeignKey(
        Job,
        on_delete=models.SET_NULL,
        blank=True,
        null=True,
        related_name='transactions'
    )
    description = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['wallet', 'status'], name='idx_transaction_wallet_status'),
        ]

    def __str__(self):
        return f"{self.get_transaction_type_display()} - ₦{self.amount} ({self.status})"


class AppSettings(models.Model):
    key = models.CharField(max_length=255, unique=True)
    value = models.CharField(max_length=255)

    def __str__(self):
        return f"{self.key}: {self.value}"

    @classmethod
    def get_value(cls, key):
        setting = cls.objects.filter(key=key).first()
        return setting.value if setting else None

    @classmethod
    def get_commission_rate(cls):
        """Return commission rate as a Decimal (e.g., Decimal('0.10') for 10%).

        Uses Decimal throughout to avoid floating-point precision errors
        in financial calculations. Defaults to 10%.
        """
        rate_str = cls.get_value('commission_rate')
        if rate_str is not None:
            try:
                return Decimal(rate_str)
            except Exception:
                pass
        return Decimal('0.10')  # Default 10%


class BankAccount(models.Model):
    """Artisan's bank account for Paystack transfer payouts."""
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='bank_accounts'
    )
    bank_code = models.CharField(
        max_length=10,
        help_text="Paystack bank code (e.g., '058' for GTBank)"
    )
    account_number = models.CharField(max_length=10)
    account_name = models.CharField(max_length=100)
    is_verified = models.BooleanField(
        default=False,
        help_text="Whether the account has been verified via Paystack"
    )
    paystack_recipient_code = models.CharField(
        max_length=100,
        blank=True,
        null=True,
        help_text="Paystack transfer recipient code (set after verification)"
    )
    is_default = models.BooleanField(
        default=False,
        help_text="Primary account for withdrawals"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'bank_code', 'account_number'],
                name='unique_user_bank_account'
            ),
        ]

    def __str__(self):
        return f"{self.account_name} - {self.bank_code}/{self.account_number[-4:]}"