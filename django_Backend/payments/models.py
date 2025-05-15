from django.utils import timezone
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
        default=0.00,
        validators=[MinValueValidator(0)]
    )
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"{self.user.username}'s Wallet - ${self.balance}"

class Transaction(models.Model):
    class Type(models.TextChoices):
        DEPOSIT = 'DEPOSIT', 'Deposit'
        WITHDRAWAL = 'WITHDRAWAL', 'Withdrawal'
        PAYMENT = 'PAYMENT', 'Payment'
        COMMISSION = 'COMMISSION', 'Commission'
        REFUND = 'REFUND', 'Refund'
    
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
    transaction_type = models.CharField(max_length=20, choices=Type.choices)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    reference = models.CharField(max_length=100, unique=True)
    job = models.ForeignKey(
        Job, 
        on_delete=models.SET_NULL, 
        blank=True, 
        null=True
    )
    description = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)
    
    def __str__(self):
        return f"{self.get_transaction_type_display()} - ${self.amount} ({self.status})"
    
class AppSettings(models.Model):
    key = models.CharField(max_length=255, unique=True)
    value = models.CharField(max_length=255)

    def __str__(self):
        return f"{self.key}: {self.value}"

    @classmethod
    def get_value(cls, key):
        setting = cls.objects.filter(key=key).first()
        return setting.value if setting else None
