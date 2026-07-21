from django.conf import settings
from django.core.validators import MinValueValidator, MaxValueValidator
from django.db import models

from accounts.models import ArtisanProfile


class Review(models.Model):
    """A customer's review of an artisan.

    One review per customer per artisan. Optionally linked to a Job
    when the review originated from the job-rating flow.
    """
    artisan = models.ForeignKey(
        ArtisanProfile,
        on_delete=models.CASCADE,
        related_name='reviews',
    )
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='given_reviews',
    )
    rating = models.FloatField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
    )
    comment = models.TextField(blank=True, default='')
    job = models.OneToOneField(
        'bookings.Job',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='job_review',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('customer', 'artisan')]
        indexes = [
            models.Index(fields=['artisan', '-created_at'], name='idx_review_artisan_created'),
        ]
        ordering = ['-created_at']

    def __str__(self):
        return f"Review by {self.customer.username} for {self.artisan.user.username} — {self.rating}/5"