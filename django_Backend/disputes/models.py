from django.utils import timezone
from django.db import models
from bookings.models import Job
from accounts.models import User

class Dispute(models.Model):
    OPEN = 'open'
    IN_REVIEW = 'in_review'
    RESOLVED = 'resolved'
    CLOSED = 'closed'
    
    STATUS_CHOICES = [
        (OPEN, 'Open'),
        (IN_REVIEW, 'In Review'),
        (RESOLVED, 'Resolved'),
        (CLOSED, 'Closed'),
    ]
    
    POOR_SERVICE = 'poor_service'
    NOT_COMPLETED = 'not_completed'
    OVER_CHARGING = 'over_charging'
    OTHER = 'other'
    
    REASON_CHOICES = [
        (POOR_SERVICE, 'Poor Service'),
        (NOT_COMPLETED, 'Not Completed'),
        (OVER_CHARGING, 'Over Charging'),
        (OTHER, 'Other'),
    ]
    
    job = models.OneToOneField(Job, on_delete=models.CASCADE, related_name='dispute')
    reason = models.CharField(max_length=50, choices=REASON_CHOICES)
    details = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=OPEN)
    resolution = models.TextField(blank=True, null=True)
    resolution_amount = models.DecimalField(
        max_digits=10, 
        decimal_places=2, 
        blank=True, 
        null=True,
        help_text="Amount to refund if applicable"
    )
    resolved_by = models.ForeignKey(
        User, 
        on_delete=models.SET_NULL, 
        blank=True, 
        null=True,
        related_name='resolved_disputes'
    )
    created_at = models.DateTimeField(default=timezone.now)
    resolved_at = models.DateTimeField(blank=True, null=True)
    
    def __str__(self):
        return f"Dispute for Job #{self.job.id} - {self.get_reason_display()}"