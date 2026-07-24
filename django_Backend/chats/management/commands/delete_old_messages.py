"""Auto-delete chat messages based on each conversation's message_ttl_days setting.

Intended to be run via cron or task scheduler, e.g.:
    # Run daily at 3 AM:
    0 3 * * * cd /path/to/project && python manage.py delete_old_messages

Use --dry-run to preview what would be deleted without actually removing anything:
    python manage.py delete_old_messages --dry-run
"""

import os
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import transaction as db_transaction
from django.utils import timezone

from chats.models import Chat, Conversation


class Command(BaseCommand):
    help = (
        'Delete chat messages older than each conversation\'s message_ttl_days setting. '
        'Conversations with message_ttl_days=0 are never auto-deleted. '
        'Also cleans up associated audio files from disk and removes '
        'inactive conversations that have no remaining messages.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be deleted without actually deleting',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        total_deleted = 0
        total_audio_cleaned = 0

        # Only process conversations with a TTL > 0 (0 means "never expire")
        conversations = Conversation.objects.filter(message_ttl_days__gt=0)

        if not conversations.exists():
            self.stdout.write('No conversations with auto-delete enabled.')
            return

        for conv in conversations:
            cutoff = timezone.now() - timedelta(days=conv.message_ttl_days)
            old_messages = Chat.objects.filter(
                conversation=conv, timestamp__lt=cutoff
            )
            count = old_messages.count()
            if count == 0:
                continue

            # Collect audio file paths before bulk deletion
            audio_messages = old_messages.filter(audio_file__isnull=False).exclude(
                audio_file=''
            )
            audio_paths = []
            for msg in audio_messages.only('audio_file'):
                try:
                    audio_paths.append(msg.audio_file.path)
                except ValueError:
                    pass

            if dry_run:
                self.stdout.write(
                    f'[DRY RUN] Conv #{conv.id} (TTL={conv.message_ttl_days}d): '
                    f'would delete {count} message(s) older than {cutoff:%Y-%m-%d %H:%M}'
                )
                for msg in old_messages.select_related('sender')[:5]:
                    self.stdout.write(f'  - Message #{msg.id} from {msg.sender.username}')
                if count > 5:
                    self.stdout.write(f'  ... and {count - 5} more')
                continue

            with db_transaction.atomic():
                deleted_count, _ = old_messages.delete()
            total_deleted += deleted_count

            for path in audio_paths:
                if os.path.isfile(path):
                    try:
                        os.remove(path)
                        total_audio_cleaned += 1
                    except OSError as e:
                        self.stderr.write(self.style.WARNING(f'Could not delete {path}: {e}'))

        # Clean up inactive conversations with zero remaining messages
        if not dry_run:
            inactive_empty = []
            for conv in Conversation.objects.filter(is_active=False):
                if not conv.messages.exists():
                    inactive_empty.append(conv.id)
            if inactive_empty:
                deleted_conv, _ = Conversation.objects.filter(id__in=inactive_empty).delete()
                self.stdout.write(self.style.SUCCESS(
                    f'Deleted {deleted_conv} inactive conversation(s) with no remaining messages.'
                ))

        self.stdout.write(self.style.SUCCESS(
            f'\nDone. Deleted: {total_deleted} message(s), '
            f'{total_audio_cleaned} audio file(s).'
        ))