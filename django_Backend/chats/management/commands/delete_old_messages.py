"""Auto-delete chat messages older than a specified number of days.

Intended to be run via cron or task scheduler, e.g.:
    # Run daily at 3 AM, deleting messages older than 14 days:
    0 3 * * * cd /path/to/project && python manage.py delete_old_messages --days=14

Use --dry-run to preview what would be deleted without actually removing anything:
    python manage.py delete_old_messages --days=14 --dry-run
"""

import os
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import transaction as db_transaction
from django.utils import timezone

from chats.models import Chat, Conversation


class Command(BaseCommand):
    help = (
        'Delete chat messages older than the specified number of days. '
        'Also cleans up associated audio files from disk and removes '
        'inactive conversations that have no remaining messages.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--days',
            type=int,
            default=14,
            help='Delete messages older than this many days (default: 14)',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be deleted without actually deleting',
        )

    def handle(self, *args, **options):
        days = options['days']
        dry_run = options['dry_run']
        cutoff = timezone.now() - timedelta(days=days)

        self.stdout.write(
            f'Looking for messages older than {days} days (before {cutoff:%Y-%m-%d %H:%M})...'
        )

        old_messages = Chat.objects.filter(timestamp__lt=cutoff)
        total_count = old_messages.count()

        if total_count == 0:
            self.stdout.write(self.style.SUCCESS('No messages old enough to delete.'))
            return

        # Collect audio file paths before deletion (bulk .delete() doesn't
        # trigger model signals, so we must handle file cleanup manually).
        audio_messages = old_messages.filter(audio_file__isnull=False).exclude(
            audio_file=''
        )
        audio_paths = []
        for msg in audio_messages.only('audio_file'):
            try:
                audio_paths.append(msg.audio_file.path)
            except ValueError:
                # FileField.path raises ValueError if the file has no name
                pass

        if dry_run:
            self.stdout.write(
                f'[DRY RUN] Would delete {total_count} message(s) '
                f'and {len(audio_paths)} audio file(s).'
            )
            # List some sample messages
            for msg in old_messages.select_related('sender', 'conversation')[:10]:
                self.stdout.write(
                    f'  - Message #{msg.id} from {msg.sender.username} '
                    f'in Conversation #{msg.conversation.id} ({msg.timestamp:%Y-%m-%d %H:%M})'
                )
            if total_count > 10:
                self.stdout.write(f'  ... and {total_count - 10} more')

            # Estimate inactive conversations that would become empty
            inactive_conv_ids = []
            for conv in Conversation.objects.filter(is_active=False):
                remaining = conv.messages.filter(timestamp__gte=cutoff).exists()
                if not remaining and not conv.messages.filter(timestamp__lt=cutoff).count() == 0:
                    # Has old messages but no new ones → will become empty after deletion
                    inactive_conv_ids.append(conv.id)
            self.stdout.write(
                f'[DRY RUN] Would also clean up {len(inactive_conv_ids)} '
                f'inactive conversation(s) with no remaining messages.'
            )
            return

        # --- Actual deletion ---
        with db_transaction.atomic():
            # Delete the old messages in bulk
            deleted_count, _ = old_messages.delete()

        self.stdout.write(
            self.style.SUCCESS(f'Deleted {deleted_count} message(s).')
        )

        # Clean up audio files from disk
        cleaned_files = 0
        for path in audio_paths:
            if os.path.isfile(path):
                try:
                    os.remove(path)
                    cleaned_files += 1
                except OSError as e:
                    self.stderr.write(
                        self.style.WARNING(f'Could not delete audio file {path}: {e}')
                    )
        if cleaned_files:
            self.stdout.write(
                self.style.SUCCESS(f'Cleaned up {cleaned_files} audio file(s) from disk.')
            )

        # Clean up inactive conversations that now have zero messages
        inactive_empty = []
        for conv in Conversation.objects.filter(is_active=False):
            if not conv.messages.exists():
                inactive_empty.append(conv.id)

        if inactive_empty:
            deleted_conv_count, _ = Conversation.objects.filter(
                id__in=inactive_empty
            ).delete()
            self.stdout.write(
                self.style.SUCCESS(
                    f'Deleted {deleted_conv_count} inactive conversation(s) with no remaining messages.'
                )
            )

        self.stdout.write(
            self.style.SUCCESS(
                f'\nDone. Deleted: {deleted_count} message(s), '
                f'{cleaned_files} audio file(s), '
                f'{len(inactive_empty)} inactive conversation(s).'
            )
        )