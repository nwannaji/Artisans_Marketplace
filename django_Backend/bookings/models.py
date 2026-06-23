from django.db import models
from accounts.models import User, ArtisanProfile
from django.core.validators import MinValueValidator, MaxValueValidator


class Job(models.Model):
    class Status(models.TextChoices):
        PENDING = 'PENDING', 'Pending'
        ADMIN_APPROVED = 'ADMIN_APPROVED', 'Admin Approved'
        ACCEPTED = 'ACCEPTED', 'Accepted'
        IN_PROGRESS = 'IN_PROGRESS', 'In Progress'
        AWAITING_REVIEW = 'AWAITING_REVIEW', 'Awaiting Review'
        COMPLETED = 'COMPLETED', 'Completed'
        CANCELLED = 'CANCELLED', 'Cancelled'
        DISPUTED = 'DISPUTED', 'Disputed'
        REJECTED = 'REJECTED', 'Rejected'

    customer = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='customer_jobs',
        limit_choices_to={'role': User.Role.CUSTOMER}
    )
    artisan = models.ForeignKey(
        ArtisanProfile,
        on_delete=models.SET_NULL,
        related_name='artisan_jobs',
        null=True,
        blank=True,
    )
    description = models.TextField()
    scheduled_time = models.DateTimeField()
    agreed_price = models.DecimalField(max_digits=10, decimal_places=2)
    location = models.CharField(max_length=255)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
        db_index=True,
    )
    escrow_held_amount = models.DecimalField(
        max_digits=10, decimal_places=2, default=0.00, blank=True, null=True
    )
    admin_approved_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='approved_jobs'
    )
    admin_approved_at = models.DateTimeField(null=True, blank=True)
    rating = models.FloatField(
        blank=True,
        null=True,
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    review = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['customer', 'status'], name='idx_job_customer_status'),
            models.Index(fields=['artisan', 'status'], name='idx_job_artisan_status'),
            models.Index(fields=['status'], name='idx_job_status'),
        ]

    def __str__(self):
        return f"Job #{self.id} - {self.artisan.user.username if self.artisan else 'Unassigned'} for {self.customer.username}"