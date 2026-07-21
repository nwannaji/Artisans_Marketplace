from django.db import models
from bookings.models import Job
from accounts.models import User


class Dispute(models.Model):
    class Status(models.TextChoices):
        OPEN = 'open', 'Open'
        IN_REVIEW = 'in_review', 'In Review'
        RESOLVED = 'resolved', 'Resolved'
        CLOSED = 'closed', 'Closed'

    class Reason(models.TextChoices):
        POOR_SERVICE = 'poor_service', 'Poor Service'
        NOT_COMPLETED = 'not_completed', 'Not Completed'
        OVER_CHARGING = 'over_charging', 'Over Charging'
        OTHER = 'other', 'Other'

    job = models.OneToOneField(Job, on_delete=models.CASCADE, related_name='dispute')
    reason = models.CharField(max_length=50, choices=Reason.choices)
    details = models.TextField()
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.OPEN, db_index=True)
    resolution = models.TextField(blank=True, null=True)
    resolved_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        blank=True,
        null=True,
        related_name='resolved_disputes'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        indexes = [
            models.Index(fields=['status'], name='idx_dispute_status'),
        ]

    def __str__(self):
        return f"Dispute for Job #{self.job.id} - {self.get_reason_display()}"


class EvidenceFile(models.Model):
    """File attachment for dispute evidence (photos, documents, etc.)."""
    dispute = models.ForeignKey(
        Dispute,
        on_delete=models.CASCADE,
        related_name='evidence_files'
    )
    uploaded_by = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='uploaded_evidence'
    )
    file = models.FileField(
        upload_to='dispute_evidence/%Y/%m/',
        help_text='Evidence file (image or document)'
    )
    caption = models.CharField(
        max_length=255,
        blank=True,
        help_text='Optional description of the evidence'
    )
    file_type = models.CharField(
        max_length=20,
        blank=True,
        help_text='MIME type of the uploaded file'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Evidence File'
        verbose_name_plural = 'Evidence Files'

    def __str__(self):
        return f"Evidence for Dispute #{self.dispute_id} - {self.caption or self.file.name}"