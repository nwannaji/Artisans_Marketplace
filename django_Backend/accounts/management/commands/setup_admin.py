"""
Management command to create the initial admin user and activate existing users.

Usage:
    python manage.py setup_admin                        # Create admin (requires --password)
    python manage.py setup_admin --username myadmin --password <secure-password>
    python manage.py setup_admin --activate user1 user2 # Activate existing users by username
    python manage.py setup_admin --activate-pending      # Activate ALL pending users

SECURITY NOTE: Do not use default passwords in production. Always specify --password.
"""

from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth import get_user_model

User = get_user_model()


class Command(BaseCommand):
    help = 'Create the initial admin user or activate pending users'

    def add_arguments(self, parser):
        parser.add_argument(
            '--username',
            default='admin',
            help='Username for the admin account (default: admin)',
        )
        parser.add_argument(
            '--email',
            default='admin@artisans.com',
            help='Email for the admin account (default: admin@artisans.com)',
        )
        parser.add_argument(
            '--password',
            default=None,
            help='Password for the admin account (REQUIRED for new admin creation)',
        )
        parser.add_argument(
            '--activate',
            nargs='+',
            help='Activate specific users by username',
        )
        parser.add_argument(
            '--activate-pending',
            action='store_true',
            help='Activate ALL pending (inactive) users',
        )

    def handle(self, *args, **options):
        # Activate specific users
        if options['activate']:
            self._activate_users(options['activate'])
            return

        # Activate all pending users
        if options['activate_pending']:
            self._activate_pending()
            return

        # Create admin user
        username = options['username']
        email = options['email']
        password = options['password']

        # SECURITY: Require explicit password — no default credentials
        if not password:
            raise CommandError(
                '--password is required when creating a new admin user. '
                'Do not use default passwords in production.'
            )

        if User.objects.filter(username=username).exists():
            user = User.objects.get(username=username)
            if not user.is_active:
                user.is_active = True
                user.save()
                self.stdout.write(
                    self.style.SUCCESS(f'Activated existing admin user: {username}')
                )
            else:
                self.stdout.write(
                    self.style.WARNING(f'Admin user "{username}" already exists and is active.')
                )
            return

        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            role=User.Role.ADMIN,
            is_active=True,
            is_staff=True,
            is_superuser=True,
        )

        self.stdout.write(
            self.style.SUCCESS(
                f'Admin user created successfully!\n'
                f'  Username: {username}\n'
                f'  Password: {password}\n'
                f'  Role: ADMIN\n'
                f'  Active: Yes\n'
                f'\nYou can now log in with these credentials in the app.'
            )
        )

    def _activate_users(self, usernames):
        activated = 0
        for username in usernames:
            try:
                user = User.objects.get(username=username)
                if not user.is_active:
                    user.is_active = True
                    user.save()
                    self.stdout.write(
                        self.style.SUCCESS(f'Activated: {username} ({user.role})')
                    )
                    activated += 1
                else:
                    self.stdout.write(
                        self.style.WARNING(f'Already active: {username}')
                    )
            except User.DoesNotExist:
                self.stdout.write(
                    self.style.ERROR(f'User not found: {username}')
                )

        self.stdout.write(f'\nActivated {activated} user(s).')

    def _activate_pending(self):
        pending = User.objects.filter(is_active=False)
        count = pending.count()
        if count == 0:
            self.stdout.write(self.style.WARNING('No pending users to activate.'))
            return

        for user in pending:
            user.is_active = True
            user.save()
            self.stdout.write(
                self.style.SUCCESS(f'Activated: {user.username} ({user.role})')
            )

        self.stdout.write(
            self.style.SUCCESS(f'\nActivated {count} pending user(s).')
        )