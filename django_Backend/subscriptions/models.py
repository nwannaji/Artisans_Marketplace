from django.conf import settings
from django.db import models
from django.utils import timezone

from accounts.models import ArtisanProfile


class Subscription(models.Model):
    """Subscription tier for artisans.

    Tracks which tier (Free/Pro/Premium) an artisan is on, when it expires,
    and who activated it. No payment processing — admin manually activates
    after verifying offline payment (bank transfer).
    """

    class Tier(models.TextChoices):
        FREE = 'FREE', 'Free'
        PRO = 'PRO', 'Pro'
        PREMIUM = 'PREMIUM', 'Premium'

    artisan = models.OneToOneField(
        ArtisanProfile,
        on_delete=models.CASCADE,
        related_name='subscription',
        help_text="The artisan this subscription belongs to.",
    )
    tier = models.CharField(
        max_length=10,
        choices=Tier.choices,
        default=Tier.FREE,
        db_index=True,
        help_text="Current subscription tier.",
    )
    expires_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="When the current tier expires. Null means no expiry (Free tier).",
    )
    activated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='activated_subscriptions',
        help_text="Admin who activated this tier.",
    )
    notes = models.TextField(
        blank=True,
        help_text="Admin notes (payment reference, bank transfer details, etc.).",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['tier', 'expires_at'], name='idx_sub_tier_expires'),
        ]

    def __str__(self):
        return f"{self.artisan.user.username} — {self.get_tier_display()}"

    @property
    def effective_tier(self):
        """Return the effective tier, accounting for expiry.

        - Free tier is always Free.
        - Pro/Premium revert to Free once expires_at has passed.
        - If expires_at is None and tier is Pro/Premium, treat as active
          (admin set it without an expiry).
        """
        if self.tier == self.Tier.FREE:
            return self.Tier.FREE
        if self.expires_at and self.expires_at < timezone.now():
            return self.Tier.FREE
        return self.tier

    @property
    def is_active(self):
        """True if the subscription is currently active (Pro or Premium)."""
        return self.effective_tier != self.Tier.FREE