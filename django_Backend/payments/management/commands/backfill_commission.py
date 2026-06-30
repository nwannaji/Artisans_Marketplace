"""Backfill commission transactions for completed jobs that bypassed the escrow flow.

When a job is marked as COMPLETED without going through the formal escrow
hold → release flow, no COMMISSION Transaction is created. This command
retroactively creates commission transactions for those jobs using the
agreed_price and current commission rate.

Intended to be run once to fix historical data, e.g.:
    python manage.py backfill_commission
    python manage.py backfill_commission --dry-run

Use --rate to override the commission rate (as a decimal, e.g. 0.10 for 10%).
By default, the rate stored in AppSettings is used.
"""

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction as db_transaction
from django.utils import timezone

from bookings.models import Job
from payments.models import AppSettings, Transaction, Wallet
from accounts.models import User


class Command(BaseCommand):
    help = (
        'Create missing COMMISSION transactions for completed jobs that '
        'bypassed the escrow flow. Uses agreed_price * commission_rate as '
        'the commission amount.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be created without actually creating transactions',
        )
        parser.add_argument(
            '--rate',
            type=float,
            default=None,
            help='Override commission rate as a decimal (e.g. 0.10 for 10%%). '
                 'Defaults to the rate stored in AppSettings.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        rate_override = options['rate']

        commission_rate = (
            Decimal(str(rate_override)) if rate_override is not None
            else AppSettings.get_commission_rate()
        )

        admin_user = User.objects.filter(role=User.Role.ADMIN, is_active=True).first()
        if not admin_user:
            self.stderr.write(self.style.ERROR(
                'No active admin user found. Create one first.'
            ))
            return

        # Find completed jobs that have no COMMISSION transaction
        jobs_with_commission = Transaction.objects.filter(
            transaction_type=Transaction.Type.COMMISSION,
            status=Transaction.Status.COMPLETED,
        ).values_list('job_id', flat=True)

        completed_jobs = Job.objects.filter(
            status=Job.Status.COMPLETED,
        ).exclude(id__in=jobs_with_commission)

        if not completed_jobs.exists():
            self.stdout.write(self.style.SUCCESS('No missing commission transactions found.'))
            return

        self.stdout.write(
            f'Found {completed_jobs.count()} completed job(s) missing commission transactions.'
        )
        self.stdout.write(f'Using commission rate: {commission_rate} ({float(commission_rate * 100):.1f}%)\n')

        total_commission = Decimal('0')
        created_count = 0

        for job in completed_jobs:
            # Use agreed_price as the basis for commission
            # (escrow_held_amount is 0 for jobs that bypassed the escrow flow)
            base_amount = job.agreed_price or Decimal('0')
            if base_amount <= 0:
                self.stdout.write(self.style.WARNING(
                    f'  Skipping Job #{job.id}: agreed_price is {base_amount}'
                ))
                continue

            commission_amount = base_amount * commission_rate

            if dry_run:
                self.stdout.write(
                    f'  [DRY RUN] Job #{job.id}: '
                    f'agreed_price=N{base_amount}, '
                    f'commission=N{commission_amount:.2f}'
                )
                total_commission += commission_amount
                continue

            # Create COMMISSION transaction and credit admin wallet
            with db_transaction.atomic():
                admin_wallet, _ = Wallet.objects.select_for_update().get_or_create(
                    user=admin_user
                )

                Transaction.objects.create(
                    wallet=admin_wallet,
                    amount=commission_amount,
                    transaction_type=Transaction.Type.COMMISSION,
                    status=Transaction.Status.COMPLETED,
                    reference=f"COMM-{job.id}-backfill-{timezone.now().strftime('%Y%m%d%H%M%S')}",
                    job=job,
                    description=f"Backfilled commission for Job #{job.id} (N{base_amount} @ {float(commission_rate * 100):.1f}%)"
                )

                admin_wallet.balance += commission_amount
                admin_wallet.save(update_fields=['balance', 'updated_at'])

            self.stdout.write(self.style.SUCCESS(
                f'  Job #{job.id}: created commission N{commission_amount:.2f} '
                f'(N{base_amount} @ {float(commission_rate * 100):.1f}%)'
            ))
            total_commission += commission_amount
            created_count += 1

        if dry_run:
            self.stdout.write(
                f'\n[DRY RUN] Would create {completed_jobs.count()} commission transaction(s) '
                f'totaling N{total_commission:.2f}'
            )
        else:
            self.stdout.write(
                self.style.SUCCESS(
                    f'\nDone. Created {created_count} commission transaction(s) '
                    f'totaling N{total_commission:.2f}'
                )
            )