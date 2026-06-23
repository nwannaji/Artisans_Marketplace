"""Auto-release escrow for jobs awaiting customer review beyond 3 days.

Intended to be run via cron or task scheduler, e.g.:
    python manage.py auto_release_escrow

Jobs that have been in AWAITING_REVIEW status for more than 3 days
will have their escrow released to the artisan (minus commission)
and their status set to COMPLETED.
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from bookings.models import Job
from payments.utils import process_escrow_release


class Command(BaseCommand):
    help = (
        'Auto-release escrow for jobs that have been in AWAITING_REVIEW '
        'status for more than 3 days without customer action.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--days',
            type=int,
            default=3,
            help='Number of days to wait before auto-releasing (default: 3)',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be released without actually releasing',
        )

    def handle(self, *args, **options):
        days = options['days']
        dry_run = options['dry_run']
        cutoff = timezone.now() - timedelta(days=days)

        jobs = Job.objects.filter(
            status=Job.Status.AWAITING_REVIEW,
            updated_at__lte=cutoff,
            escrow_held_amount__gt=0,
        )

        if not jobs.exists():
            self.stdout.write('No jobs eligible for auto-release.')
            return

        released = 0
        skipped = 0

        for job in jobs:
            if dry_run:
                self.stdout.write(
                    f'[DRY RUN] Would release escrow for Job #{job.id} '
                    f'(₦{job.escrow_held_amount}, updated {job.updated_at})'
                )
                skipped += 1
                continue

            try:
                from django.db import transaction as db_transaction
                with db_transaction.atomic():
                    job = Job.objects.select_for_update().get(pk=job.pk)
                    # Re-check in case another process already handled it
                    if job.status != Job.Status.AWAITING_REVIEW or job.escrow_held_amount <= 0:
                        continue

                    artisan_payout, commission_amount = process_escrow_release(job)
                    job.status = Job.Status.COMPLETED
                    job.save(update_fields=['status', 'updated_at'])

                self.stdout.write(
                    self.style.SUCCESS(
                        f'Released escrow for Job #{job.id}: '
                        f'₦{artisan_payout} to artisan, ₦{commission_amount} commission'
                    )
                )
                released += 1
            except Exception as e:
                self.stderr.write(
                    self.style.ERROR(
                        f'Failed to release escrow for Job #{job.id}: {e}'
                    )
                )

        self.stdout.write(
            f'\nDone. Released: {released}, Skipped: {skipped}'
        )