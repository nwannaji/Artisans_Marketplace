from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils.translation import gettext_lazy as _
from django.core.validators import MinValueValidator, MaxValueValidator

from accounts.users_manager import CustomUserManager


# User model
class User(AbstractUser):
    class Role(models.TextChoices):
        ADMIN = 'ADMIN', _('Administrator')
        ARTISAN = 'ARTISAN', _('Artisan')
        CUSTOMER = 'CUSTOMER', _('Customer')

    role = models.CharField(
        max_length=20,
        choices=Role.choices,
        default=Role.CUSTOMER
    )
    phone_number = models.CharField(max_length=20, blank=True, null=True)
    is_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(
        default=False,
        help_text="For artisans/admins, must be approved by admin"
    )
    objects = CustomUserManager()

    def __str__(self):
        return f"{self.username} ({self.get_role_display()})"


# Abstract base profile
class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    profile_picture = models.ImageField(upload_to='profile_pics/', blank=True, null=True)
    bio = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


# Customer Profile
class CustomerProfile(UserProfile):
    address = models.TextField(blank=True, null=True)

    def __str__(self):
        return f"Customer Profile - {self.user.username}"


# Artisan Profile
class ArtisanProfile(UserProfile):
    class AvailabilityStatus(models.TextChoices):
        AVAILABLE = 'AVAILABLE', _('Available')
        BUSY = 'BUSY', _('Busy')
        ENGAGED = 'ENGAGED', _('Engaged')
        OFFLINE = 'OFFLINE', _('Offline')

    profession = models.CharField(max_length=100, blank=True, null=True, db_index=True)
    skills = models.JSONField(default=list)
    hourly_rate = models.DecimalField(
        max_digits=10, decimal_places=2, blank=True, null=True
    )
    rating = models.FloatField(
        default=0.0,
        validators=[MinValueValidator(0), MaxValueValidator(5)]
    )
    jobs_completed = models.PositiveIntegerField(default=0)
    location = models.CharField(max_length=255, blank=True, null=True, db_index=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True, db_index=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True, db_index=True)
    verification_documents = models.JSONField(default=list)
    is_verified = models.BooleanField(default=False)
    is_available = models.CharField(
        max_length=10,
        choices=AvailabilityStatus.choices,
        default=AvailabilityStatus.OFFLINE,
        db_index=True,
        help_text="Artisan's current availability status"
    )

    class Meta:
        indexes = [
            models.Index(fields=['is_available', 'profession'], name='idx_artisan_avail_prof'),
        ]

    def __str__(self):
        return f"Artisan Profile - {self.user.username}"