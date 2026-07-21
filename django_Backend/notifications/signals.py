import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from bookings.models import Job
from disputes.models import Dispute

from .models import Notification
from .utils import create_notification

logger = logging.getLogger(__name__)

# Map of Job.Status values to human-readable labels for notification messages
JOB_STATUS_LABELS = {
    Job.Status.PENDING: 'Pending',
    Job.Status.ADMIN_APPROVED: 'Admin Approved',
    Job.Status.ACCEPTED: 'Accepted',
    Job.Status.IN_PROGRESS: 'In Progress',
    Job.Status.AWAITING_REVIEW: 'Awaiting Review',
    Job.Status.COMPLETED: 'Completed',
    Job.Status.CANCELLED: 'Cancelled',
    Job.Status.DISPUTED: 'Disputed',
    Job.Status.REJECTED: 'Rejected',
}


@receiver(post_save, sender=Job)
def notify_job_status_change(sender, instance, created, **kwargs):
    """Send a notification when a Job is created or its status changes.

    On creation: notify the customer that their job was created.
    On update: notify relevant parties about the status transition.
    """
    job = instance

    if created:
        # Notify the customer that their job was created
        create_notification(
            user=job.customer,
            notification_type=Notification.NotificationType.JOB_STATUS,
            title='Job Created',
            message=f'Your job #{job.id} has been created and is pending approval.',
            related_object_type='job',
            related_object_id=job.id,
        )
        return

    # On update: notify relevant parties about the status change
    status_label = JOB_STATUS_LABELS.get(job.status, job.status)

    # Notify the customer about the status change
    create_notification(
        user=job.customer,
        notification_type=Notification.NotificationType.JOB_STATUS,
        title='Job Status Updated',
        message=f'Your job #{job.id} status has been updated to {status_label}.',
        related_object_type='job',
        related_object_id=job.id,
    )

    # Notify the artisan if assigned
    if job.artisan and job.artisan.user:
        # Avoid double-notification: if the artisan is the customer, don't send twice
        if job.artisan.user != job.customer:
            create_notification(
                user=job.artisan.user,
                notification_type=Notification.NotificationType.JOB_STATUS,
                title='Job Status Updated',
                message=f'Job #{job.id} has been updated to {status_label}.',
                related_object_type='job',
                related_object_id=job.id,
            )


@receiver(post_save, sender=Dispute)
def notify_dispute_created(sender, instance, created, **kwargs):
    """Send a notification when a Dispute is created or resolved."""
    dispute = instance

    if created:
        # Notify the customer that a dispute was filed
        create_notification(
            user=dispute.job.customer,
            notification_type=Notification.NotificationType.DISPUTE,
            title='Dispute Filed',
            message=f'A dispute has been filed for job #{dispute.job.id}: {dispute.get_reason_display()}.',
            related_object_type='dispute',
            related_object_id=dispute.id,
        )

        # Notify the artisan
        if dispute.job.artisan and dispute.job.artisan.user:
            create_notification(
                user=dispute.job.artisan.user,
                notification_type=Notification.NotificationType.DISPUTE,
                title='Dispute Filed',
                message=f'A dispute has been filed for job #{dispute.job.id}: {dispute.get_reason_display()}.',
                related_object_type='dispute',
                related_object_id=dispute.id,
            )
    else:
        # If the dispute status changed to resolved/closed, notify relevant parties
        if dispute.status in (Dispute.Status.RESOLVED, Dispute.Status.CLOSED):
            status_label = dispute.get_status_display()

            create_notification(
                user=dispute.job.customer,
                notification_type=Notification.NotificationType.DISPUTE,
                title='Dispute Updated',
                message=f'The dispute for job #{dispute.job.id} has been {status_label.lower()}.',
                related_object_type='dispute',
                related_object_id=dispute.id,
            )

            if dispute.job.artisan and dispute.job.artisan.user:
                create_notification(
                    user=dispute.job.artisan.user,
                    notification_type=Notification.NotificationType.DISPUTE,
                    title='Dispute Updated',
                    message=f'The dispute for job #{dispute.job.id} has been {status_label.lower()}.',
                    related_object_type='dispute',
                    related_object_id=dispute.id,
                )

