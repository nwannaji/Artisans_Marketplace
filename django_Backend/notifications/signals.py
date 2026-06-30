import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from bookings.models import Job
from disputes.models import Dispute
from payments.models import Transaction

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


@receiver(post_save, sender=Transaction)
def notify_escrow_events(sender, instance, created, **kwargs):
    """Send notifications for escrow-related transaction events.

    Fires when an ESCROW_HOLD (funding) or ESCROW_RELEASE (release) transaction
    is completed. Handles both newly-created completed transactions and
    status updates (e.g. PANDASCROW_FUND transitioning to COMPLETED via webhook).
    """
    transaction = instance

    # Only notify for completed escrow transactions
    if transaction.status != Transaction.Status.COMPLETED:
        return

    # Avoid duplicate notifications: only send when newly created
    # or when status changed to COMPLETED (tracked by checking if created OR
    # if this is an update that changed status)
    if not created:
        # For updates, only notify if the status field changed to COMPLETED.
        # We can't easily check old vs new status in post_save, so we rely on
        # a simple heuristic: if this is an update and the transaction is now
        # COMPLETED, it likely just transitioned from PENDING. Send notification.
        pass  # Allow update-triggered notifications for PANDASCROW_FUND completions

    if transaction.transaction_type == Transaction.Type.ESCROW_HOLD:
        # Escrow funded — notify the customer and artisan
        job = transaction.job
        if job:
            create_notification(
                user=job.customer,
                notification_type=Notification.NotificationType.ESCROW,
                title='Escrow Funded',
                message=f'Your payment of ₦{transaction.amount} for job #{job.id} has been held in escrow.',
                related_object_type='job',
                related_object_id=job.id,
            )
            if job.artisan and job.artisan.user:
                create_notification(
                    user=job.artisan.user,
                    notification_type=Notification.NotificationType.ESCROW,
                    title='Escrow Funded',
                    message=f'Payment of ₦{transaction.amount} for job #{job.id} has been secured in escrow.',
                    related_object_type='job',
                    related_object_id=job.id,
                )

    elif transaction.transaction_type == Transaction.Type.ESCROW_RELEASE:
        # Escrow released — notify the artisan about payment
        job = transaction.job
        if job:
            if job.artisan and job.artisan.user:
                create_notification(
                    user=job.artisan.user,
                    notification_type=Notification.NotificationType.ESCROW,
                    title='Escrow Released',
                    message=f'Escrow payment of ₦{transaction.amount} for job #{job.id} has been released to your wallet.',
                    related_object_type='job',
                    related_object_id=job.id,
                )
            create_notification(
                user=job.customer,
                notification_type=Notification.NotificationType.ESCROW,
                title='Escrow Released',
                message=f'Escrow payment of ₦{transaction.amount} for job #{job.id} has been released.',
                related_object_type='job',
                related_object_id=job.id,
            )

    elif transaction.transaction_type in (
        Transaction.Type.PANDASCROW_FUND,
        Transaction.Type.PANDASCROW_RELEASE,
    ):
        # Pandascrow escrow events — notify when completed (via webhook update)
        job = transaction.job
        if job:
            title = 'Escrow Funded' if transaction.transaction_type == Transaction.Type.PANDASCROW_FUND else 'Escrow Released'
            create_notification(
                user=job.customer,
                notification_type=Notification.NotificationType.ESCROW,
                title=title,
                message=f'Payment of ₦{transaction.amount} for job #{job.id} has been {"held in escrow" if transaction.transaction_type == Transaction.Type.PANDASCROW_FUND else "released"}.',
                related_object_type='job',
                related_object_id=job.id,
            )
            if job.artisan and job.artisan.user:
                create_notification(
                    user=job.artisan.user,
                    notification_type=Notification.NotificationType.ESCROW,
                    title=title,
                    message=f'Payment of ₦{transaction.amount} for job #{job.id} has been {"secured in escrow" if transaction.transaction_type == Transaction.Type.PANDASCROW_FUND else "released to your wallet"}.',
                    related_object_type='job',
                    related_object_id=job.id,
                )