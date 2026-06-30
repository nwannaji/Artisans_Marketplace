from django.db import models
from django.conf import settings


class Notification(models.Model):
    """In-app notification for users."""

    class NotificationType(models.TextChoices):
        JOB_STATUS = 'job_status', 'Job Status'
        ESCROW = 'escrow', 'Escrow'
        DISPUTE = 'dispute', 'Dispute'
        CHAT = 'chat', 'Chat'
        PAYMENT = 'payment', 'Payment'
        SYSTEM = 'system', 'System'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    notification_type = models.CharField(
        max_length=20,
        choices=NotificationType.choices,
        db_index=True,
    )
    title = models.CharField(max_length=255)
    message = models.TextField()
    related_object_type = models.CharField(
        max_length=50,
        blank=True,
        null=True,
        help_text="The type of the related object, e.g. 'job', 'dispute', 'conversation'",
    )
    related_object_id = models.IntegerField(
        blank=True,
        null=True,
        help_text="The primary key of the related object",
    )
    is_read = models.BooleanField(default=False, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'is_read'], name='idx_notification_user_read'),
        ]

    def __str__(self):
        return f"Notification for {self.user.username}: {self.title}"