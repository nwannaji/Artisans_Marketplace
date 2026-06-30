"""
Comprehensive tests for the bookings app.

Covers: job creation, status transitions, invalid transitions,
cancellation, and the 405 response for DELETE requests.

Run with: python manage.py test bookings
"""

from decimal import Decimal
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from django.utils import timezone

from accounts.models import User, ArtisanProfile
from .models import Job


class JobCreationTests(TestCase):
    """Tests for job creation endpoint."""

    def setUp(self):
        self.client = APIClient()
        self.job_list_url = reverse('bookings:create')

        self.customer = User.objects.create_user(
            username='job_customer',
            email='job_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='job_artisan',
            email='job_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Plumber'
        )
        self.admin = User.objects.create_user(
            username='job_admin',
            email='job_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )

    def _job_payload(self):
        return {
            'description': 'Fix the kitchen sink',
            'scheduled_time': '2026-07-01T10:00:00Z',
            'agreed_price': '5000.00',
            'location': 'Lagos',
        }

    def test_customer_can_create_job(self):
        """Customers should be able to create jobs."""
        self.client.force_authenticate(user=self.customer)
        resp = self.client.post(self.job_list_url, self._job_payload(), format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        # JobCreateSerializer does not include 'status' in its response;
        # verify status in the database instead.
        self.assertEqual(Job.objects.count(), 1)
        job = Job.objects.first()
        self.assertEqual(job.customer, self.customer)
        self.assertEqual(job.status, Job.Status.PENDING)

    def test_artisan_cannot_create_job(self):
        """Artisans should be forbidden from creating jobs."""
        self.client.force_authenticate(user=self.artisan)
        resp = self.client.post(self.job_list_url, self._job_payload(), format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_cannot_create_job(self):
        """Admins (non-customers) should be forbidden from creating jobs."""
        self.client.force_authenticate(user=self.admin)
        resp = self.client.post(self.job_list_url, self._job_payload(), format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_unauthenticated_cannot_create_job(self):
        """Unauthenticated users should be denied."""
        resp = self.client.post(self.job_list_url, self._job_payload(), format='json')
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_customer_can_list_own_jobs(self):
        """Customers should only see their own jobs."""
        Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Customer job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('3000.00'),
            location='Lagos',
            status=Job.Status.PENDING,
        )
        other_customer = User.objects.create_user(
            username='other_list_cust',
            email='other_list_cust@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        Job.objects.create(
            customer=other_customer,
            artisan=self.artisan_profile,
            description='Other job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('2000.00'),
            location='Abuja',
            status=Job.Status.PENDING,
        )

        self.client.force_authenticate(user=self.customer)
        resp = self.client.get(self.job_list_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Customer should only see their own job
        job_ids = [j['id'] for j in resp.data['results']]
        self.assertEqual(len(job_ids), 1)


class JobStatusTransitionTests(TestCase):
    """Tests for valid and invalid job status transitions."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='trans_customer',
            email='trans_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='trans_artisan',
            email='trans_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Electrician'
        )
        self.admin = User.objects.create_user(
            username='trans_admin',
            email='trans_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )

    def _create_job(self, status_val=Job.Status.PENDING):
        return Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Test job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=status_val,
        )

    # ------------------------------------------------------------------
    # Full valid lifecycle
    # ------------------------------------------------------------------
    def test_full_lifecycle_pending_to_completed(self):
        """PENDING -> ADMIN_APPROVED -> ACCEPTED -> IN_PROGRESS ->
        AWAITING_REVIEW -> COMPLETED should all succeed."""
        job = self._create_job(Job.Status.PENDING)

        # Admin approves
        self.client.force_authenticate(user=self.admin)
        approve_url = reverse('bookings:admin-approve', kwargs={'pk': job.pk})
        resp = self.client.patch(approve_url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ADMIN_APPROVED')

        # Artisan accepts
        self.client.force_authenticate(user=self.artisan)
        accept_url = reverse('bookings:artisan-accept', kwargs={'pk': job.pk})
        resp = self.client.patch(accept_url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ACCEPTED')

        # Artisan starts work
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'IN_PROGRESS'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'IN_PROGRESS')

        # Artisan marks as awaiting review
        resp = self.client.patch(status_url, {'status': 'AWAITING_REVIEW'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'AWAITING_REVIEW')

        # Customer approves completion
        self.client.force_authenticate(user=self.customer)
        resp = self.client.patch(status_url, {'status': 'COMPLETED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'COMPLETED')

    # ------------------------------------------------------------------
    # Invalid transitions
    # ------------------------------------------------------------------
    def test_invalid_transition_pending_to_in_progress(self):
        """Cannot skip from PENDING directly to IN_PROGRESS."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.artisan)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'IN_PROGRESS'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_transition_pending_to_completed(self):
        """Cannot transition from PENDING to COMPLETED."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'COMPLETED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_transition_accepted_to_completed(self):
        """Cannot skip from ACCEPTED directly to COMPLETED."""
        job = self._create_job(Job.Status.ACCEPTED)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'COMPLETED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_transition_from_completed(self):
        """Cannot transition from COMPLETED to any other status."""
        job = self._create_job(Job.Status.COMPLETED)

        self.client.force_authenticate(user=self.artisan)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        for next_status in ['IN_PROGRESS', 'ACCEPTED', 'PENDING']:
            resp = self.client.patch(status_url, {'status': next_status}, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST,
                             f"Transition from COMPLETED to {next_status} should fail")

    def test_invalid_transition_from_cancelled(self):
        """Cannot transition from CANCELLED to any other status."""
        job = self._create_job(Job.Status.CANCELLED)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        for next_status in ['IN_PROGRESS', 'ACCEPTED', 'PENDING']:
            resp = self.client.patch(status_url, {'status': next_status}, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST,
                             f"Transition from CANCELLED to {next_status} should fail")

    # ------------------------------------------------------------------
    # Role-based transition checks
    # ------------------------------------------------------------------
    def test_only_assigned_artisan_can_start_job(self):
        """Only the assigned artisan can transition ACCEPTED -> IN_PROGRESS."""
        job = self._create_job(Job.Status.ACCEPTED)

        # A different artisan should not be able to start the job
        other_artisan = User.objects.create_user(
            username='other_trans_artisan',
            email='other_trans_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.client.force_authenticate(user=other_artisan)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'IN_PROGRESS'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_customer_can_approve_completion(self):
        """Only the customer who owns the job can transition to COMPLETED."""
        job = self._create_job(Job.Status.AWAITING_REVIEW)

        # Artisan should not be able to approve completion
        self.client.force_authenticate(user=self.artisan)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'COMPLETED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_artisan_can_mark_awaiting_review(self):
        """Only the assigned artisan can transition IN_PROGRESS -> AWAITING_REVIEW."""
        job = self._create_job(Job.Status.IN_PROGRESS)

        # Customer should not be able to mark as awaiting review
        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'AWAITING_REVIEW'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    # ------------------------------------------------------------------
    # Admin approve / reject
    # ------------------------------------------------------------------
    def test_admin_approve_pending_job(self):
        """Admin can approve a PENDING job."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.admin)
        url = reverse('bookings:admin-approve', kwargs={'pk': job.pk})
        resp = self.client.patch(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ADMIN_APPROVED')

    def test_admin_reject_pending_job(self):
        """Admin can reject a PENDING job."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.admin)
        url = reverse('bookings:admin-reject', kwargs={'pk': job.pk})
        resp = self.client.patch(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'REJECTED')

    def test_admin_cannot_approve_non_pending_job(self):
        """Admin cannot approve a job that is not PENDING."""
        job = self._create_job(Job.Status.ACCEPTED)

        self.client.force_authenticate(user=self.admin)
        url = reverse('bookings:admin-approve', kwargs={'pk': job.pk})
        resp = self.client.patch(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_artisan_accept_admin_approved_job(self):
        """Artisan can accept an ADMIN_APPROVED job."""
        job = self._create_job(Job.Status.ADMIN_APPROVED)

        self.client.force_authenticate(user=self.artisan)
        url = reverse('bookings:artisan-accept', kwargs={'pk': job.pk})
        resp = self.client.patch(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ACCEPTED')

    def test_artisan_cannot_accept_pending_job(self):
        """Artisan cannot accept a PENDING job (needs admin approval first)."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.artisan)
        url = reverse('bookings:artisan-accept', kwargs={'pk': job.pk})
        resp = self.client.patch(url, {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class JobCancellationTests(TestCase):
    """Tests for job cancellation by the customer."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='cancel_customer',
            email='cancel_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='cancel_artisan',
            email='cancel_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Painter'
        )

    def _create_job(self, status_val=Job.Status.PENDING):
        return Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Cancellable job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('3000.00'),
            location='Lagos',
            status=status_val,
        )

    def test_customer_can_cancel_pending_job(self):
        """Customer can cancel a PENDING job."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'CANCELLED')

    def test_customer_can_cancel_accepted_job(self):
        """Customer can cancel an ACCEPTED job."""
        job = self._create_job(Job.Status.ACCEPTED)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'CANCELLED')

    def test_customer_can_cancel_in_progress_job(self):
        """Customer can cancel an IN_PROGRESS job."""
        job = self._create_job(Job.Status.IN_PROGRESS)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'CANCELLED')

    def test_customer_can_cancel_awaiting_review_job(self):
        """Customer can cancel an AWAITING_REVIEW job."""
        job = self._create_job(Job.Status.AWAITING_REVIEW)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'CANCELLED')

    def test_customer_cannot_cancel_completed_job(self):
        """Customer cannot cancel a COMPLETED job."""
        job = self._create_job(Job.Status.COMPLETED)

        self.client.force_authenticate(user=self.customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_other_customer_cannot_cancel(self):
        """A different customer cannot cancel someone else's job."""
        job = self._create_job(Job.Status.PENDING)

        other_customer = User.objects.create_user(
            username='other_cancel_cust',
            email='other_cancel_cust@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.client.force_authenticate(user=other_customer)
        status_url = reverse('bookings:status', kwargs={'pk': job.pk})
        resp = self.client.patch(status_url, {'status': 'CANCELLED'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_cancel_via_update_endpoint_rejected(self):
        """Customers cannot cancel via the detail update endpoint because
        JobCreateSerializer does not include 'status'; they must use the
        dedicated status endpoint instead."""
        job = self._create_job(Job.Status.PENDING)

        self.client.force_authenticate(user=self.customer)
        detail_url = reverse('bookings:detail', kwargs={'pk': job.pk})
        resp = self.client.patch(detail_url, {'status': 'CANCELLED'}, format='json')
        # JobCreateSerializer ignores the status field, so
        # validated_data.get('status') is None, which triggers
        # the "Customers can only cancel jobs" permission check.
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        # Verify the job status has NOT changed
        job.refresh_from_db()
        self.assertEqual(job.status, Job.Status.PENDING)


class JobDeleteNotAllowedTests(TestCase):
    """Tests that the DELETE method is not allowed on jobs."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='del_customer',
            email='del_customer@test.com',
            password='StrongPass123!',
            role='CUSTOMER',
            is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='del_artisan',
            email='del_artisan@test.com',
            password='StrongPass123!',
            role='ARTISAN',
            is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Carpenter'
        )

        self.job = Job.objects.create(
            customer=self.customer,
            artisan=self.artisan_profile,
            description='Undeletable job',
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            agreed_price=Decimal('5000.00'),
            location='Lagos',
            status=Job.Status.PENDING,
        )

    def test_job_delete_returns_405(self):
        """DELETE method should not be allowed on the job detail endpoint."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('bookings:detail', kwargs={'pk': self.job.pk})
        resp = self.client.delete(url)
        self.assertEqual(resp.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_job_delete_not_allowed_even_for_admin(self):
        """Even admin should not be able to DELETE a job."""
        admin = User.objects.create_user(
            username='del_admin',
            email='del_admin@test.com',
            password='StrongPass123!',
            role='ADMIN',
            is_active=True,
            is_staff=True,
        )
        self.client.force_authenticate(user=admin)
        url = reverse('bookings:detail', kwargs={'pk': self.job.pk})
        resp = self.client.delete(url)
        self.assertEqual(resp.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)