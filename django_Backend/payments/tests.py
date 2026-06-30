"""
Comprehensive tests for the payments app.

Covers: wallet creation, transaction restrictions, escrow funding,
escrow release, escrow refund, and wallet balance constraints.

Run with: python manage.py test payments
"""

import json
import hmac
import hashlib
from decimal import Decimal
from unittest.mock import patch, MagicMock

from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status

from accounts.models import User, ArtisanProfile
from bookings.models import Job
from .models import Wallet, Transaction, AppSettings, PandascrowEscrow
from .utils import PandascrowAPIError


class WalletCreationTests(TestCase):
    """Tests that a wallet is created when a user registers."""

    def setUp(self):
        self.client = APIClient()
        self.register_url = reverse('accounts:user-register')

    def test_wallet_created_on_customer_registration(self):
        """Registering a customer should automatically create a wallet."""
        payload = {
            'username': 'wallet_customer',
            'email': 'wallet_customer@test.com',
            'password': 'StrongPass123!',
            'password2': 'StrongPass123!',
            'role': 'CUSTOMER',
        }
        resp = self.client.post(self.register_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(username='wallet_customer')
        self.assertTrue(
            Wallet.objects.filter(user=user).exists(),
            "Wallet should be created on customer registration"
        )
        wallet = Wallet.objects.get(user=user)
        self.assertEqual(wallet.balance, Decimal('0.00'))

    def test_wallet_created_on_artisan_registration(self):
        """Registering an artisan should automatically create a wallet."""
        payload = {
            'username': 'wallet_artisan',
            'email': 'wallet_artisan@test.com',
            'password': 'StrongPass123!',
            'password2': 'StrongPass123!',
            'role': 'ARTISAN',
            'profession': 'Plumber',
        }
        resp = self.client.post(self.register_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(username='wallet_artisan')
        self.assertTrue(
            Wallet.objects.filter(user=user).exists(),
            "Wallet should be created on artisan registration"
        )


class TransactionCreationTests(TestCase):
    """Tests that only WITHDRAWAL transactions can be created directly."""

    def setUp(self):
        self.client = APIClient()
        self.transaction_url = reverse('payments:transaction-list-create')

        self.customer = User.objects.create_user(
            username='tx_customer',
            email='tx_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.wallet = Wallet.objects.create(user=self.customer, balance=Decimal('10000.00'))

    def test_withdrawal_creation_allowed(self):
        """Users should be able to create WITHDRAWAL transactions."""
        self.client.force_authenticate(user=self.customer)
        payload = {
            'amount': '1000.00',
            'transaction_type': 'WITHDRAWAL',
            'reference': 'WDR-TEST-001',
        }
        resp = self.client.post(self.transaction_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.wallet.refresh_from_db()
        self.assertEqual(self.wallet.balance, Decimal('9000.00'))

    def test_deposit_creation_rejected(self):
        """Direct DEPOSIT creation should be rejected — must go through Paystack."""
        self.client.force_authenticate(user=self.customer)
        payload = {
            'amount': '5000.00',
            'transaction_type': 'DEPOSIT',
            'reference': 'DEP-TEST-001',
        }
        resp = self.client.post(self.transaction_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Cannot create', str(resp.data))

    def test_escrow_hold_creation_rejected(self):
        """Direct ESCROW_HOLD creation should be rejected — must go through escrow endpoint."""
        self.client.force_authenticate(user=self.customer)
        payload = {
            'amount': '5000.00',
            'transaction_type': 'ESCROW_HOLD',
            'reference': 'ESC-TEST-001',
        }
        resp = self.client.post(self.transaction_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Cannot create', str(resp.data))

    def test_commission_creation_rejected(self):
        """Direct COMMISSION creation should be rejected."""
        self.client.force_authenticate(user=self.customer)
        payload = {
            'amount': '500.00',
            'transaction_type': 'COMMISSION',
            'reference': 'COM-TEST-001',
        }
        resp = self.client.post(self.transaction_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_withdrawal_insufficient_funds(self):
        """Attempting to withdraw more than the wallet balance should be rejected."""
        self.client.force_authenticate(user=self.customer)
        payload = {
            'amount': '50000.00',
            'transaction_type': 'WITHDRAWAL',
            'reference': 'WDR-TEST-002',
        }
        resp = self.client.post(self.transaction_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Insufficient funds', str(resp.data))


class EscrowFundTests(TestCase):
    """Tests for the escrow funding endpoint."""

    def setUp(self):
        self.client = APIClient()

        # Create customer with funded wallet
        self.customer = User.objects.create_user(
            username='escrow_customer',
            email='escrow_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('50000.00')
        )

        # Create another customer (for non-owner tests)
        self.other_customer = User.objects.create_user(
            username='other_customer',
            email='other_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        Wallet.objects.create(user=self.other_customer, balance=Decimal('50000.00'))

        # Create artisan
        self.artisan = User.objects.create_user(
            username='escrow_artisan',
            email='escrow_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Plumber'
        )

        # Create admin (needed for escrow release)
        self.admin = User.objects.create_user(
            username='escrow_admin',
            email='escrow_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )

        # Create a job in ACCEPTED status (ready for escrow)
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Fix leaky faucet',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.ACCEPTED,
        )

    def test_escrow_fund_success(self):
        """Customer can fund escrow for their own job with sufficient wallet balance."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('escrow_amount', resp.data)
        self.assertEqual(resp.data['escrow_amount'], '5000.00')

        # Verify wallet was debited
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('45000.00'))

        # Verify escrow_held_amount was set on job
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('5000.00'))

    def test_escrow_fund_with_explicit_amount(self):
        """Customer can specify an explicit amount for escrow (within 1% tolerance)."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {'amount': '5000.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_escrow_fund_amount_must_match_agreed_price(self):
        """Funding escrow with an amount that deviates more than 1% from the
        agreed price should be rejected."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})

        # Amount is too low (>1% deviation)
        resp = self.client.post(url, {'amount': '4000.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('less than the agreed price', str(resp.data))

        # Amount is too high (>1% deviation)
        resp = self.client.post(url, {'amount': '6000.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('exceeds the agreed price', str(resp.data))

    def test_escrow_fund_prevents_double_funding(self):
        """Funding escrow for a job that is already funded should be rejected."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})

        # First funding should succeed
        resp1 = self.client.post(url, {}, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_200_OK)

        # Second funding should be rejected
        resp2 = self.client.post(url, {}, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already funded', str(resp2.data).lower())

    def test_escrow_fund_prevents_funding_by_non_owner(self):
        """A different customer should not be able to fund another customer's job."""
        self.client.force_authenticate(user=self.other_customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('only fund your own', str(resp.data).lower())

    def test_escrow_fund_artisan_cannot_fund(self):
        """An artisan should not be able to fund escrow (only customers can)."""
        self.client.force_authenticate(user=self.artisan)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_escrow_fund_insufficient_balance(self):
        """Attempting to fund escrow with insufficient wallet balance should fail."""
        # Set wallet balance below the agreed price
        self.customer_wallet.balance = Decimal('1000.00')
        self.customer_wallet.save()

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Insufficient funds', str(resp.data))

    def test_escrow_fund_wrong_job_status(self):
        """Funding escrow on a PENDING job (not yet ACCEPTED) should fail."""
        pending_job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Pending job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('3000.00'),
            location='Lagos',
            status=Job.Status.PENDING,
        )
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': pending_job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('ACCEPTED or IN_PROGRESS', str(resp.data))

    def test_escrow_fund_nonexistent_job(self):
        """Funding a nonexistent job should return 404."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': 99999})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)


class EscrowReleaseTests(TestCase):
    """Tests for the escrow release endpoint."""

    def setUp(self):
        self.client = APIClient()

        # Create customer with funded wallet
        self.customer = User.objects.create_user(
            username='release_customer',
            email='release_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('50000.00')
        )

        # Create artisan
        self.artisan = User.objects.create_user(
            username='release_artisan',
            email='release_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Electrician'
        )
        self.artisan_wallet = Wallet.objects.create(
            user=self.artisan, balance=Decimal('0.00')
        )

        # Create admin
        self.admin = User.objects.create_user(
            username='release_admin',
            email='release_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )
        self.admin_wallet = Wallet.objects.create(
            user=self.admin, balance=Decimal('0.00')
        )

        # Set commission rate to 10%
        AppSettings.objects.get_or_create(
            key='commission_rate',
            defaults={'value': '0.10'},
        )

        # Create a funded job in IN_PROGRESS status
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Wire installation',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('10000.00'),
            location='Abuja',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('10000.00'),
        )

        # Debit customer wallet for the escrow
        self.customer_wallet.balance -= Decimal('10000.00')
        self.customer_wallet.save()

    def test_escrow_release_by_customer(self):
        """Customer can release escrow, crediting the artisan minus commission."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Artisan should receive 90% (10,000 - 10% commission = 9,000)
        self.assertEqual(Decimal(resp.data['artisan_payout']), Decimal('9000.00'))
        self.assertEqual(Decimal(resp.data['commission_amount']), Decimal('1000.00'))

        # Verify wallet balances
        self.artisan_wallet.refresh_from_db()
        self.assertEqual(self.artisan_wallet.balance, Decimal('9000.00'))

        self.admin_wallet.refresh_from_db()
        self.assertEqual(self.admin_wallet.balance, Decimal('1000.00'))

        # Job should be completed
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, Job.Status.COMPLETED)
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

    def test_escrow_release_artisan_cannot_release(self):
        """An artisan should not be able to release escrow (only customers can)."""
        self.client.force_authenticate(user=self.artisan)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_escrow_release_no_escrow_held(self):
        """Releasing escrow on a job with no held amount should fail."""
        no_escrow_job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='No escrow job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('0.00'),
        )
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': no_escrow_job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('No escrow held', str(resp.data))

    def test_escrow_release_wrong_job_status(self):
        """Releasing escrow on a PENDING job should fail."""
        pending_job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Pending job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.PENDING,
            escrow_held_amount=Decimal('5000.00'),
        )
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': pending_job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_escrow_release_other_customer_denied(self):
        """A different customer should not be able to release another's escrow."""
        other_customer = User.objects.create_user(
            username='other_release_cust',
            email='other_release_cust@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.client.force_authenticate(user=other_customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)


class EscrowRefundTests(TestCase):
    """Tests for the admin escrow refund endpoint."""

    def setUp(self):
        self.client = APIClient()

        # Create customer
        self.customer = User.objects.create_user(
            username='refund_customer',
            email='refund_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('0.00')
        )

        # Create artisan
        self.artisan = User.objects.create_user(
            username='refund_artisan',
            email='refund_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Plumber'
        )
        self.artisan_wallet = Wallet.objects.create(
            user=self.artisan, balance=Decimal('0.00')
        )

        # Create admin
        self.admin = User.objects.create_user(
            username='refund_admin',
            email='refund_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )
        self.admin_wallet = Wallet.objects.create(
            user=self.admin, balance=Decimal('0.00')
        )

        # Set commission rate
        AppSettings.objects.get_or_create(
            key='commission_rate',
            defaults={'value': '0.10'},
        )

        # Create a job with held escrow
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Bad plumbing job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('10000.00'),
            location='Lagos',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('10000.00'),
        )

    def test_full_refund_by_admin(self):
        """Admin can issue a full refund, crediting the customer's wallet."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')  # No amount = full refund
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Customer wallet should be credited
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('10000.00'))

        # Job escrow should be zeroed out
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

    def test_partial_refund_by_admin(self):
        """Admin can issue a partial refund; remaining goes to artisan minus commission."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        # Refund 4000 out of 10000; remaining 6000 goes to artisan minus 10% commission
        resp = self.client.post(url, {'refund_amount': '4000.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Customer gets 4000 refund
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('4000.00'))

        # Artisan gets 6000 - 600 (10% commission) = 5400
        self.artisan_wallet.refresh_from_db()
        self.assertEqual(self.artisan_wallet.balance, Decimal('5400.00'))

        # Admin gets 600 commission
        self.admin_wallet.refresh_from_db()
        self.assertEqual(self.admin_wallet.balance, Decimal('600.00'))

        # Job escrow should be zeroed
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

    def test_refund_credits_customer_wallet(self):
        """After refund, a REFUND transaction should exist for the customer."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        refund_tx = Transaction.objects.filter(
            wallet=self.customer_wallet,
            transaction_type=Transaction.Type.REFUND,
        )
        self.assertTrue(refund_tx.exists())
        self.assertEqual(refund_tx.first().amount, Decimal('10000.00'))

    def test_refund_amount_exceeds_escrow(self):
        """Refund amount cannot exceed the held escrow amount."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {'refund_amount': '50000.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('cannot exceed', str(resp.data))

    def test_refund_zero_amount_rejected(self):
        """Refund amount of zero or negative should be rejected."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {'refund_amount': '0.00'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_refund_non_admin_denied(self):
        """Non-admin users should be forbidden from the refund endpoint."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_refund_no_escrow_held(self):
        """Attempting to refund a job with no escrow should fail."""
        no_escrow_job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='No escrow',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('0.00'),
        )
        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': no_escrow_job.pk})
        resp = self.client.post(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('No escrow held', str(resp.data))


class WalletBalanceTests(TestCase):
    """Tests for wallet balance constraints."""

    def setUp(self):
        self.customer = User.objects.create_user(
            username='bal_customer',
            email='bal_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('5000.00')
        )

    def test_wallet_balance_starts_at_zero(self):
        """Newly created wallets should have a zero balance."""
        user = User.objects.create_user(
            username='zero_wallet_user',
            email='zero_wallet@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        wallet = Wallet.objects.create(user=user)
        self.assertEqual(wallet.balance, Decimal('0.00'))

    def test_withdrawal_cannot_exceed_balance(self):
        """Attempting to withdraw more than the wallet balance via API should fail."""
        client = APIClient()
        client.force_authenticate(user=self.customer)
        url = reverse('payments:transaction-list-create')
        payload = {
            'amount': '99999.00',
            'transaction_type': 'WITHDRAWAL',
            'reference': 'WDR-OVER-BAL',
        }
        resp = client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Insufficient funds', str(resp.data))

        # Balance should be unchanged
        self.wallet.refresh_from_db()
        self.assertEqual(self.wallet.balance, Decimal('5000.00'))

    def test_wallet_balance_non_negative_constraint(self):
        """The wallet model has a CheckConstraint ensuring balance >= 0.
        Verify the application-level enforcement prevents negative balance."""
        # Attempt to create a wallet with negative balance directly
        # (This tests the model-level constraint if the DB enforces it)
        user = User.objects.create_user(
            username='neg_bal_user',
            email='neg_bal@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        wallet = Wallet(user=user, balance=Decimal('-100.00'))
        # The MinValueValidator on the field should prevent this via full_clean()
        from django.core.exceptions import ValidationError
        with self.assertRaises(ValidationError):
            wallet.full_clean()


# ========================================================================
# Pandascrow Escrow Integration Tests
# ========================================================================

PANDASCROW_TEST_SETTINGS = {
    'PANDASCROW_CLIENT_ID': 'test_client',
    'PANDASCROW_CLIENT_SECRET': 'test_secret',
    'PANDASCROW_WEBHOOK_SECRET': 'test_webhook_secret',
    'PANDASCROW_API_URL': 'https://sandbox.pandascrow.io',
    'PANDASCROW_CALLBACK_URL': 'https://example.com/callback',
}


@override_settings(**PANDASCROW_TEST_SETTINGS)
class PandascrowEscrowFundTests(TestCase):
    """Tests for escrow funding via Pandascrow."""

    def setUp(self):
        self.client = APIClient()

        # Create customer with funded wallet
        self.customer = User.objects.create_user(
            username='pc_fund_customer',
            email='pc_fund_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('50000.00')
        )

        # Create another customer (for non-owner tests)
        self.other_customer = User.objects.create_user(
            username='pc_fund_other',
            email='pc_fund_other@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        Wallet.objects.create(user=self.other_customer, balance=Decimal('50000.00'))

        # Create artisan
        self.artisan = User.objects.create_user(
            username='pc_fund_artisan',
            email='pc_fund_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Plumber'
        )

        # Create a job in ACCEPTED status (ready for escrow)
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Fix sink',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.ACCEPTED,
        )

    @patch('payments.views.pandascrow_initialize_escrow')
    def test_pandascrow_escrow_fund_success(self, mock_init_escrow):
        """Successful escrow funding via Pandascrow creates PandascrowEscrow record,
        PANDASCROW_FUND transaction, sets escrow_held_amount, and returns payment_url."""
        mock_init_escrow.return_value = ('ESC-123', 'https://pay.pandascrow.io/abc')

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('payment_url', resp.data)
        self.assertEqual(resp.data['payment_url'], 'https://pay.pandascrow.io/abc')
        self.assertTrue(resp.data.get('requires_pandascrow_payment'))
        self.assertEqual(resp.data['escrow_amount'], '5000.00')

        # Verify PandascrowEscrow record created with INITIALIZED status
        pandascrow_escrow = PandascrowEscrow.objects.get(job=self.job)
        self.assertEqual(pandascrow_escrow.escrow_id, 'ESC-123')
        self.assertEqual(pandascrow_escrow.status, PandascrowEscrow.Status.INITIALIZED)
        self.assertEqual(pandascrow_escrow.payment_url, 'https://pay.pandascrow.io/abc')

        # Verify PANDASCROW_FUND transaction created
        tx = Transaction.objects.get(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_FUND,
        )
        self.assertEqual(tx.amount, Decimal('5000.00'))
        self.assertEqual(tx.status, Transaction.Status.PENDING)
        self.assertEqual(tx.wallet, self.customer_wallet)

        # Verify job escrow_held_amount is set
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('5000.00'))

    @patch('payments.views.pandascrow_initialize_escrow')
    def test_pandascrow_escrow_fund_api_failure(self, mock_init_escrow):
        """When Pandascrow API fails, response is 503 and no PandascrowEscrow record is created."""
        mock_init_escrow.side_effect = PandascrowAPIError(
            "Service unavailable", status_code=503
        )

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertFalse(PandascrowEscrow.objects.filter(job=self.job).exists())

        # Verify escrow_held_amount was NOT set on the job
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

    @patch('payments.views.pandascrow_initialize_escrow')
    def test_pandascrow_escrow_fund_already_initialized(self, mock_init_escrow):
        """If a PandascrowEscrow already exists for the job in INITIALIZED or FUNDED status,
        and the job already has escrow_held_amount set, the endpoint returns 400
        'Job already funded' to prevent double-funding."""
        PandascrowEscrow.objects.create(
            job=self.job,
            escrow_id='ESC-EXISTING',
            status=PandascrowEscrow.Status.INITIALIZED,
            amount=Decimal('5000.00'),
            payment_url='https://pay.pandascrow.io/existing',
        )
        # When Pandascrow escrow is initialized, escrow_held_amount is set on the job
        self.job.escrow_held_amount = Decimal('5000.00')
        self.job.save()

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        # Double-funding is prevented — returns 400
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already funded', str(resp.data).lower())
        # The Pandascrow API should NOT have been called
        mock_init_escrow.assert_not_called()

    @patch('payments.views.pandascrow_initialize_escrow')
    def test_pandascrow_escrow_fund_returns_existing_payment_url(self, mock_init_escrow):
        """If a PandascrowEscrow exists but escrow_held_amount is not yet set on the job
        (edge case: PandascrowEscrow record created before job update), the endpoint
        returns the existing payment_url without creating a new escrow."""
        PandascrowEscrow.objects.create(
            job=self.job,
            escrow_id='ESC-EXISTING',
            status=PandascrowEscrow.Status.INITIALIZED,
            amount=Decimal('5000.00'),
            payment_url='https://pay.pandascrow.io/existing',
        )
        # Do NOT set escrow_held_amount — this simulates the edge case where
        # the PandascrowEscrow was created but job.escrow_held_amount is still 0

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        # The endpoint should return the existing payment_url
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['payment_url'], 'https://pay.pandascrow.io/existing')
        self.assertTrue(resp.data.get('requires_pandascrow_payment'))
        # The Pandascrow API should NOT have been called
        mock_init_escrow.assert_not_called()

    @patch('payments.views.pandascrow_initialize_escrow')
    def test_pandascrow_escrow_fund_non_owner(self, mock_init_escrow):
        """Attempting to fund another customer's job should return 403."""
        self.client.force_authenticate(user=self.other_customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        mock_init_escrow.assert_not_called()

    @patch('payments.views.is_pandascrow_configured')
    def test_pandascrow_fallback_to_internal_when_not_configured(self, mock_is_configured):
        """When Pandascrow is not configured, the internal wallet escrow flow should work."""
        mock_is_configured.return_value = False

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertNotIn('payment_url', resp.data)
        self.assertNotIn('requires_pandascrow_payment', resp.data)

        # Verify wallet was debited
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('45000.00'))

        # Verify ESCROW_HOLD transaction created (internal wallet flow)
        tx = Transaction.objects.get(
            job=self.job,
            transaction_type=Transaction.Type.ESCROW_HOLD,
        )
        self.assertEqual(tx.amount, Decimal('5000.00'))
        self.assertEqual(tx.status, Transaction.Status.COMPLETED)

        # Verify escrow_held_amount is set
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('5000.00'))

        # No PandascrowEscrow record should exist
        self.assertFalse(PandascrowEscrow.objects.filter(job=self.job).exists())


@override_settings(**PANDASCROW_TEST_SETTINGS)
class PandascrowEscrowReleaseTests(TestCase):
    """Tests for escrow release via Pandascrow."""

    def setUp(self):
        self.client = APIClient()

        # Create customer
        self.customer = User.objects.create_user(
            username='pc_rel_customer',
            email='pc_rel_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('0.00')
        )

        # Create artisan
        self.artisan = User.objects.create_user(
            username='pc_rel_artisan',
            email='pc_rel_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Electrician'
        )

        # Create admin
        self.admin = User.objects.create_user(
            username='pc_rel_admin',
            email='pc_rel_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )
        self.admin_wallet = Wallet.objects.create(
            user=self.admin, balance=Decimal('0.00')
        )

        # Set commission rate
        AppSettings.objects.get_or_create(
            key='commission_rate',
            defaults={'value': '0.10'},
        )

        # Create a funded job in IN_PROGRESS status
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Wire installation',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('10000.00'),
            location='Abuja',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('10000.00'),
        )

        # Create a PandascrowEscrow in FUNDED status
        self.pandascrow_escrow = PandascrowEscrow.objects.create(
            job=self.job,
            escrow_id='ESC-REL-001',
            status=PandascrowEscrow.Status.FUNDED,
            amount=Decimal('10000.00'),
            payment_url='https://pay.pandascrow.io/esc-rel-001',
        )

    @patch('payments.views.pandascrow_complete_escrow')
    def test_pandascrow_escrow_release_success(self, mock_complete_escrow):
        """Successful Pandascrow escrow release updates status to COMPLETED,
        zeros escrow_held_amount, and creates PANDASCROW_RELEASE transaction."""
        mock_complete_escrow.return_value = {'status': 'success', 'data': {'escrow_id': 'ESC-REL-001'}}

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('pandascrow_escrow_id', resp.data)

        # Verify PandascrowEscrow status updated to COMPLETED
        self.pandascrow_escrow.refresh_from_db()
        self.assertEqual(self.pandascrow_escrow.status, PandascrowEscrow.Status.COMPLETED)

        # Verify job escrow_held_amount set to 0
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

        # Verify PANDASCROW_RELEASE transaction created
        tx = Transaction.objects.get(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_RELEASE,
        )
        self.assertEqual(tx.amount, Decimal('10000.00'))
        self.assertEqual(tx.status, Transaction.Status.COMPLETED)

    @patch('payments.views.pandascrow_complete_escrow')
    def test_pandascrow_escrow_release_with_otp(self, mock_complete_escrow):
        """Submitting OTP with the release request passes it to pandascrow_complete_escrow."""
        mock_complete_escrow.return_value = {'status': 'success', 'data': {'escrow_id': 'ESC-REL-001'}}

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {'otp': '123456'}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Verify OTP was passed to pandascrow_complete_escrow
        mock_complete_escrow.assert_called_once_with(
            escrow_id='ESC-REL-001',
            otp='123456',
        )

    @patch('payments.views.pandascrow_complete_escrow')
    def test_pandascrow_release_requires_otp(self, mock_complete_escrow):
        """When Pandascrow returns an OTP-related error, response should contain otp_required=True."""
        mock_complete_escrow.side_effect = PandascrowAPIError(
            "OTP required to complete escrow",
            status_code=400,
        )

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(resp.data.get('otp_required'))

    @patch('payments.views.pandascrow_complete_escrow')
    def test_pandascrow_release_api_failure(self, mock_complete_escrow):
        """When Pandascrow API fails during release, response is 502 and no local state changes."""
        mock_complete_escrow.side_effect = PandascrowAPIError(
            "Gateway timeout", status_code=504
        )

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_502_BAD_GATEWAY)

        # Verify no local state changes occurred
        self.pandascrow_escrow.refresh_from_db()
        self.assertEqual(self.pandascrow_escrow.status, PandascrowEscrow.Status.FUNDED)

        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('10000.00'))

        # No PANDASCROW_RELEASE transaction should have been created
        self.assertFalse(
            Transaction.objects.filter(
                job=self.job,
                transaction_type=Transaction.Type.PANDASCROW_RELEASE,
            ).exists()
        )


@override_settings(**PANDASCROW_TEST_SETTINGS)
class PandascrowWebhookTests(TestCase):
    """Tests for Pandascrow webhook handling."""

    def setUp(self):
        self.client = APIClient()
        self.webhook_url = reverse('payments:pandascrow-webhook')
        self.webhook_secret = PANDASCROW_TEST_SETTINGS['PANDASCROW_WEBHOOK_SECRET']

        # Create customer and artisan
        self.customer = User.objects.create_user(
            username='pc_wh_customer',
            email='pc_wh_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('50000.00')
        )

        self.artisan = User.objects.create_user(
            username='pc_wh_artisan',
            email='pc_wh_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Carpenter'
        )

        # Set commission rate
        AppSettings.objects.get_or_create(
            key='commission_rate',
            defaults={'value': '0.10'},
        )

        # Create a job with escrow
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Woodwork job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('8000.00'),
            location='Lagos',
            status=Job.Status.IN_PROGRESS,
            escrow_held_amount=Decimal('8000.00'),
        )

        # Create a PandascrowEscrow in INITIALIZED status
        self.pandascrow_escrow = PandascrowEscrow.objects.create(
            job=self.job,
            escrow_id='ESC-WH-001',
            status=PandascrowEscrow.Status.INITIALIZED,
            amount=Decimal('8000.00'),
            payment_url='https://pay.pandascrow.io/esc-wh-001',
        )

        # Create a PANDASCROW_FUND transaction (PENDING — created when escrow is initialized)
        self.fund_tx = Transaction.objects.create(
            wallet=self.customer_wallet,
            amount=Decimal('8000.00'),
            transaction_type=Transaction.Type.PANDASCROW_FUND,
            status=Transaction.Status.PENDING,
            reference='PESCROW-1-abc12345',
            job=self.job,
            description='Pandascrow escrow funding for Job #1',
        )

    def _compute_signature(self, payload_bytes):
        """Compute the HMAC-SHA256 signature for a webhook payload."""
        return hmac.new(
            self.webhook_secret.encode('utf-8'),
            payload_bytes,
            hashlib.sha256,
        ).hexdigest()

    def _send_webhook(self, event, data, timestamp=1234567890):
        """Helper to send a Pandascrow webhook request with a valid signature."""
        payload = {
            'event': event,
            'data': data,
            'timestamp': timestamp,
        }
        payload_bytes = json.dumps(payload).encode('utf-8')
        signature = self._compute_signature(payload_bytes)
        return self.client.post(
            self.webhook_url,
            data=payload_bytes,
            content_type='application/json',
            HTTP_X_PANDASCROW_SIGNATURE=signature,
        )

    @patch('payments.views.send_sms')
    def test_escrow_paid_webhook(self, mock_sms):
        """escrow.paid webhook updates PandascrowEscrow status to FUNDED
        and updates the PANDASCROW_FUND transaction to COMPLETED."""
        data = {
            'escrow_id': 'ESC-WH-001',
            'amount': '8000.00',
            'currency': 'NGN',
        }
        resp = self._send_webhook('escrow.paid', data)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Verify PandascrowEscrow status updated to FUNDED
        self.pandascrow_escrow.refresh_from_db()
        self.assertEqual(self.pandascrow_escrow.status, PandascrowEscrow.Status.FUNDED)

        # Verify PANDASCROW_FUND transaction updated to COMPLETED
        self.fund_tx.refresh_from_db()
        self.assertEqual(self.fund_tx.status, Transaction.Status.COMPLETED)

    def test_escrow_completed_webhook(self):
        """escrow.completed webhook updates status to COMPLETED, zeros escrow_held_amount,
        and marks job as COMPLETED."""
        # First, move escrow to FUNDED status
        self.pandascrow_escrow.status = PandascrowEscrow.Status.FUNDED
        self.pandascrow_escrow.save()

        data = {
            'escrow_id': 'ESC-WH-001',
            'amount': '8000.00',
            'currency': 'NGN',
        }
        resp = self._send_webhook('escrow.completed', data)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Verify PandascrowEscrow status updated to COMPLETED
        self.pandascrow_escrow.refresh_from_db()
        self.assertEqual(self.pandascrow_escrow.status, PandascrowEscrow.Status.COMPLETED)

        # Verify job escrow_held_amount set to 0
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))
        self.assertEqual(self.job.status, Job.Status.COMPLETED)

        # Verify PANDASCROW_RELEASE transaction created
        tx = Transaction.objects.filter(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_RELEASE,
        ).first()
        self.assertIsNotNone(tx)
        self.assertEqual(tx.status, Transaction.Status.COMPLETED)

    def test_escrow_cancelled_webhook(self):
        """escrow.cancelled webhook updates status to REFUNDED and creates
        a PANDASCROW_REFUND transaction."""
        data = {
            'escrow_id': 'ESC-WH-001',
            'amount': '8000.00',
            'currency': 'NGN',
        }
        resp = self._send_webhook('escrow.cancelled', data)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Verify PandascrowEscrow status updated to REFUNDED
        self.pandascrow_escrow.refresh_from_db()
        self.assertEqual(self.pandascrow_escrow.status, PandascrowEscrow.Status.REFUNDED)

        # Verify PANDASCROW_REFUND transaction created
        tx = Transaction.objects.filter(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_REFUND,
        ).first()
        self.assertIsNotNone(tx)
        self.assertEqual(tx.amount, Decimal('8000.00'))
        self.assertEqual(tx.status, Transaction.Status.COMPLETED)

        # Verify job escrow_held_amount set to 0
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

    def test_webhook_invalid_signature(self):
        """Webhook with invalid signature should return 401."""
        payload = {
            'event': 'escrow.paid',
            'data': {'escrow_id': 'ESC-WH-001'},
            'timestamp': 1234567890,
        }
        payload_bytes = json.dumps(payload).encode('utf-8')
        resp = self.client.post(
            self.webhook_url,
            data=payload_bytes,
            content_type='application/json',
            HTTP_X_PANDASCROW_SIGNATURE='invalid_signature',
        )
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    @patch('payments.views.send_sms')
    def test_webhook_idempotency(self, mock_sms):
        """Sending escrow.paid webhook twice with same data should not double-process."""
        # First call
        data = {
            'escrow_id': 'ESC-WH-001',
            'amount': '8000.00',
            'currency': 'NGN',
        }
        resp1 = self._send_webhook('escrow.paid', data)
        self.assertEqual(resp1.status_code, status.HTTP_200_OK)

        # Count transactions after first call
        fund_tx_count_after_first = Transaction.objects.filter(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_FUND,
            status=Transaction.Status.COMPLETED,
        ).count()

        # Second call (should be idempotent)
        resp2 = self._send_webhook('escrow.paid', data)
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)

        # Verify no additional PANDASCROW_FUND transactions were marked COMPLETED
        fund_tx_count_after_second = Transaction.objects.filter(
            job=self.job,
            transaction_type=Transaction.Type.PANDASCROW_FUND,
            status=Transaction.Status.COMPLETED,
        ).count()
        self.assertEqual(fund_tx_count_after_first, fund_tx_count_after_second)


class BackwardCompatibilityTests(TestCase):
    """Ensure the legacy internal wallet escrow flow still works
    when Pandascrow is not configured."""

    def setUp(self):
        self.client = APIClient()

        # Override settings to disable Pandascrow
        # PANDASCROW_CLIENT_ID='' means is_pandascrow_configured() returns False
        self.client_factory = APIClient()

        # Create customer with funded wallet
        self.customer = User.objects.create_user(
            username='bc_customer',
            email='bc_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.customer_wallet = Wallet.objects.create(
            user=self.customer, balance=Decimal('50000.00')
        )

        # Create artisan
        self.artisan = User.objects.create_user(
            username='bc_artisan',
            email='bc_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Painter'
        )
        self.artisan_wallet = Wallet.objects.create(
            user=self.artisan, balance=Decimal('0.00')
        )

        # Create admin
        self.admin = User.objects.create_user(
            username='bc_admin',
            email='bc_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )
        self.admin_wallet = Wallet.objects.create(
            user=self.admin, balance=Decimal('0.00')
        )

        # Set commission rate
        AppSettings.objects.get_or_create(
            key='commission_rate',
            defaults={'value': '0.10'},
        )

        # Create a job in ACCEPTED status
        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Paint living room',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('10000.00'),
            location='Abuja',
            status=Job.Status.ACCEPTED,
        )

    @override_settings(PANDASCROW_CLIENT_ID='', PANDASCROW_CLIENT_SECRET='')
    def test_internal_escrow_fund_still_works(self):
        """Internal escrow funding still works when Pandascrow is not configured."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-fund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('escrow_amount', resp.data)
        self.assertEqual(resp.data['escrow_amount'], '10000.00')

        # Verify wallet was debited
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('40000.00'))

        # Verify ESCROW_HOLD transaction created
        tx = Transaction.objects.get(
            job=self.job,
            transaction_type=Transaction.Type.ESCROW_HOLD,
        )
        self.assertEqual(tx.amount, Decimal('10000.00'))
        self.assertEqual(tx.status, Transaction.Status.COMPLETED)

        # Verify escrow_held_amount on job
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('10000.00'))

        # No PandascrowEscrow should exist
        self.assertFalse(PandascrowEscrow.objects.filter(job=self.job).exists())

    @override_settings(PANDASCROW_CLIENT_ID='', PANDASCROW_CLIENT_SECRET='')
    def test_internal_escrow_release_still_works(self):
        """Internal escrow release still works when Pandascrow is not configured."""
        # First fund the escrow
        self.job.escrow_held_amount = Decimal('10000.00')
        self.job.status = Job.Status.IN_PROGRESS
        self.job.save()
        self.customer_wallet.balance -= Decimal('10000.00')
        self.customer_wallet.save()

        self.client.force_authenticate(user=self.customer)
        url = reverse('payments:escrow-release', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('artisan_payout', resp.data)

        # Verify artisan was credited (minus 10% commission)
        self.artisan_wallet.refresh_from_db()
        self.assertEqual(self.artisan_wallet.balance, Decimal('9000.00'))

        # Verify admin got commission
        self.admin_wallet.refresh_from_db()
        self.assertEqual(self.admin_wallet.balance, Decimal('1000.00'))

        # Verify job completed
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))
        self.assertEqual(self.job.status, Job.Status.COMPLETED)

    @override_settings(PANDASCROW_CLIENT_ID='', PANDASCROW_CLIENT_SECRET='')
    def test_internal_escrow_refund_still_works(self):
        """Internal escrow refund still works when Pandascrow is not configured."""
        # Set up a funded job
        self.job.escrow_held_amount = Decimal('10000.00')
        self.job.status = Job.Status.IN_PROGRESS
        self.job.save()

        self.client.force_authenticate(user=self.admin)
        url = reverse('payments:admin-escrow-refund', kwargs={'pk': self.job.pk})
        resp = self.client.post(url, {}, format='json')  # Full refund

        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        # Verify customer wallet was credited
        self.customer_wallet.refresh_from_db()
        self.assertEqual(self.customer_wallet.balance, Decimal('60000.00'))

        # Verify job escrow_held_amount set to 0
        self.job.refresh_from_db()
        self.assertEqual(self.job.escrow_held_amount, Decimal('0.00'))

        # Verify REFUND transaction created
        refund_tx = Transaction.objects.filter(
            wallet=self.customer_wallet,
            transaction_type=Transaction.Type.REFUND,
        ).first()
        self.assertIsNotNone(refund_tx)
        self.assertEqual(refund_tx.amount, Decimal('10000.00'))