import logging

from django.db import transaction as db_transaction
from django.db.models.signals import post_save
from django.dispatch import receiver
from bookings.models import Job
from accounts.models import ArtisanProfile

logger = logging.getLogger(__name__)


@receiver(post_save, sender=Job)
def update_artisan_availability_on_job_status(sender, instance, **kwargs):
    """
    Automatically toggle artisan availability based on job status changes.

    - When a job moves to ACCEPTED or IN_PROGRESS: set artisan to ENGAGED
    - When a job moves to COMPLETED, CANCELLED, or DISPUTED:
      check if the artisan has other active jobs; if none, revert ENGAGED to AVAILABLE
    - Never auto-change an OFFLINE or manually-BUSY artisan back to AVAILABLE
    """
    artisan = instance.artisan
    if artisan is None:
        return

    status = instance.status

    # Job started or in progress — artisan is engaged
    if status in (Job.Status.ACCEPTED, Job.Status.IN_PROGRESS):
        if artisan.is_available != ArtisanProfile.AvailabilityStatus.OFFLINE:
            ArtisanProfile.objects.filter(pk=artisan.pk).update(
                is_available=ArtisanProfile.AvailabilityStatus.ENGAGED
            )

    # Job ended — check if artisan is free to become available again
    elif status in (Job.Status.COMPLETED, Job.Status.CANCELLED, Job.Status.DISPUTED):
        # Never auto-change an OFFLINE artisan back to AVAILABLE
        if artisan.is_available == ArtisanProfile.AvailabilityStatus.OFFLINE:
            return

        # Check for other active jobs (PENDING and ADMIN_APPROVED also count,
        # since the artisan was marked ENGAGED when the booking was created)
        has_active_jobs = Job.objects.filter(
            artisan=artisan,
            status__in=[
                Job.Status.PENDING,
                Job.Status.ADMIN_APPROVED,
                Job.Status.ACCEPTED,
                Job.Status.IN_PROGRESS,
            ]
        ).exclude(pk=instance.pk).exists()

        if not has_active_jobs:
            # Only revert ENGAGED artisans to AVAILABLE.
            # BUSY is a manual setting — respect it and don't override.
            if artisan.is_available == ArtisanProfile.AvailabilityStatus.ENGAGED:
                ArtisanProfile.objects.filter(pk=artisan.pk).update(
                    is_available=ArtisanProfile.AvailabilityStatus.AVAILABLE
                )


@receiver(post_save, sender=Job)
def refund_escrow_on_cancellation(sender, instance, **kwargs):
    """
    When a job is cancelled with held escrow, automatically refund the customer.

    Routes to Pandascrow cancel if the job has a PandascrowEscrow record,
    otherwise uses the legacy internal wallet refund flow.
    """
    if instance.status != Job.Status.CANCELLED:
        return
    if not instance.escrow_held_amount or instance.escrow_held_amount <= 0:
        return

    from decimal import Decimal
    from payments.utils import process_escrow_refund, pandascrow_cancel_escrow, PandascrowAPIError
    from payments.models import PandascrowEscrow

    # Check if this is a Pandascrow escrow
    pandascrow_escrow = getattr(instance, 'pandascrow_escrow', None)
    if pandascrow_escrow and pandascrow_escrow.status in (
        PandascrowEscrow.Status.INITIALIZED,
        PandascrowEscrow.Status.FUNDED,
    ):
        try:
            pandascrow_cancel_escrow(pandascrow_escrow.escrow_id)
            pandascrow_escrow.status = PandascrowEscrow.Status.CANCELLED
            pandascrow_escrow.save(update_fields=['status', 'updated_at'])
            instance.escrow_held_amount = Decimal('0.00')
            instance.save(update_fields=['escrow_held_amount', 'updated_at'])
            logger.info("Cancelled Pandascrow escrow %s for cancelled job %s",
                       pandascrow_escrow.escrow_id, instance.pk)
        except PandascrowAPIError as e:
            logger.exception("Failed to cancel Pandascrow escrow %s for job %s: %s",
                            pandascrow_escrow.escrow_id, instance.pk, str(e))
        return

    # Legacy internal escrow refund
    try:
        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=instance.pk)
            if not job.escrow_held_amount or job.escrow_held_amount <= 0:
                return  # Already refunded by another process
            refund_amount = Decimal(str(job.escrow_held_amount))
            process_escrow_refund(job, refund_amount)
    except Exception:
        # Log but don't crash — the cancellation itself should still succeed
        logger.exception("Failed to auto-refund escrow for cancelled job %s", instance.pk)