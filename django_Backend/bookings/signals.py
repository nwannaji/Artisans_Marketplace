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

    Uses select_for_update within an atomic transaction to prevent race conditions.
    The signal re-triggers when process_escrow_refund saves the job with
    escrow_held_amount=0, but the guard condition (amount > 0) short-circuits
    on the second invocation.
    """
    if instance.status != Job.Status.CANCELLED:
        return
    if not instance.escrow_held_amount or instance.escrow_held_amount <= 0:
        return

    from decimal import Decimal
    from payments.utils import process_escrow_refund

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