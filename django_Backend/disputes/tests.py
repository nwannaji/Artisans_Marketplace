"""
Comprehensive tests for the disputes app.

Covers: dispute creation, IDOR protection, admin-only resolution,
and evidence file upload validation.

Run with: python manage.py test disputes
"""

import io
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from decimal import Decimal
from django.utils import timezone

from accounts.models import User, ArtisanProfile
from bookings.models import Job
from .models import Dispute, EvidenceFile


class DisputeCreationTests(TestCase):
    """Tests for dispute creation endpoint."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='disp_customer', email='disp_cust@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='disp_artisan', email='disp_art@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Plumber',
        )
        self.admin = User.objects.create_user(
            username='disp_admin', email='disp_admin@test.com',
            password='StrongPass123!', role='ADMIN', is_active=True, is_staff=True,
        )
        # A different customer (for IDOR tests)
        self.other_customer = User.objects.create_user(
            username='disp_other_cust', email='disp_other@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )

        self.job = Job.objects.create(
            customer=self.customer, artisan=self.artisan_profile,
            description='Dispute test job', agreed_price=Decimal('5000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Lagos', status=Job.Status.IN_PROGRESS,
        )

    def test_customer_can_create_dispute(self):
        """A customer involved in the job can create a dispute."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:dispute-list-create')
        payload = {
            'job_id': self.job.pk,
            'reason': 'poor_service',
            'details': 'The work was not done properly.',
        }
        resp = self.client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'open')

        # Job should now be DISPUTED
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, Job.Status.DISPUTED)

    def test_artisan_can_create_dispute(self):
        """An artisan involved in the job can also create a dispute."""
        self.client.force_authenticate(user=self.artisan)
        url = reverse('disputes:dispute-list-create')
        payload = {
            'job_id': self.job.pk,
            'reason': 'over_charging',
            'details': 'Customer is demanding more than agreed.',
        }
        resp = self.client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_uninvolved_customer_cannot_create_dispute(self):
        """A customer not involved in the job should not be able to dispute it."""
        self.client.force_authenticate(user=self.other_customer)
        url = reverse('disputes:dispute-list-create')
        payload = {
            'job_id': self.job.pk,
            'reason': 'poor_service',
            'details': 'Not my job but I want to dispute.',
        }
        resp = self.client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)


class DisputeIDORTests(TestCase):
    """Tests for IDOR protection on dispute endpoints."""

    def setUp(self):
        self.client = APIClient()

        # Customer A and their job
        self.customer_a = User.objects.create_user(
            username='idor_a', email='idor_a@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan_a = User.objects.create_user(
            username='idor_art_a', email='idor_art_a@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile_a = ArtisanProfile.objects.create(
            user=self.artisan_a, profession='Electrician',
        )
        self.job_a = Job.objects.create(
            customer=self.customer_a, artisan=self.artisan_profile_a,
            description='Customer A job', agreed_price=Decimal('5000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Lagos', status=Job.Status.IN_PROGRESS,
        )

        # Customer B and their job
        self.customer_b = User.objects.create_user(
            username='idor_b', email='idor_b@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan_b = User.objects.create_user(
            username='idor_art_b', email='idor_art_b@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile_b = ArtisanProfile.objects.create(
            user=self.artisan_b, profession='Painter',
        )
        self.job_b = Job.objects.create(
            customer=self.customer_b, artisan=self.artisan_profile_b,
            description='Customer B job', agreed_price=Decimal('8000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Abuja', status=Job.Status.IN_PROGRESS,
        )

        self.admin = User.objects.create_user(
            username='idor_admin', email='idor_admin@test.com',
            password='StrongPass123!', role='ADMIN', is_active=True, is_staff=True,
        )

        # Create disputes
        self.dispute_a = Dispute.objects.create(
            job=self.job_a, reason='poor_service',
            details='Customer A dispute',
        )
        self.dispute_b = Dispute.objects.create(
            job=self.job_b, reason='not_completed',
            details='Customer B dispute',
        )

    def test_customer_can_see_own_disputes(self):
        """Customer A should see their own disputes in the list."""
        self.client.force_authenticate(user=self.customer_a)
        url = reverse('disputes:dispute-list-create')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        dispute_ids = [d['id'] for d in resp.data['results']]
        self.assertIn(self.dispute_a.pk, dispute_ids)

    def test_customer_cannot_see_others_disputes(self):
        """Customer A should NOT see Customer B's disputes."""
        self.client.force_authenticate(user=self.customer_a)
        url = reverse('disputes:dispute-list-create')
        resp = self.client.get(url)
        dispute_ids = [d['id'] for d in resp.data['results']]
        self.assertNotIn(self.dispute_b.pk, dispute_ids)

    def test_customer_cannot_read_others_dispute_detail(self):
        """Customer A should NOT be able to read Customer B's dispute detail."""
        self.client.force_authenticate(user=self.customer_a)
        url = reverse('disputes:dispute-retrieve-update', kwargs={'pk': self.dispute_b.pk})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_admin_can_see_all_disputes(self):
        """Admin should be able to see all disputes."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('disputes:dispute-list-create')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        dispute_ids = [d['id'] for d in resp.data['results']]
        self.assertIn(self.dispute_a.pk, dispute_ids)
        self.assertIn(self.dispute_b.pk, dispute_ids)

    def test_artisan_can_see_own_disputes(self):
        """Artisan A should see disputes for jobs they are assigned to."""
        self.client.force_authenticate(user=self.artisan_a)
        url = reverse('disputes:dispute-list-create')
        resp = self.client.get(url)
        dispute_ids = [d['id'] for d in resp.data['results']]
        self.assertIn(self.dispute_a.pk, dispute_ids)
        self.assertNotIn(self.dispute_b.pk, dispute_ids)


class DisputeResolutionTests(TestCase):
    """Tests for admin-only dispute resolution."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='res_customer', email='res_cust@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='res_artisan', email='res_art@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Carpenter',
        )
        self.admin = User.objects.create_user(
            username='res_admin', email='res_admin@test.com',
            password='StrongPass123!', role='ADMIN', is_active=True, is_staff=True,
        )


        self.job = Job.objects.create(
            customer=self.customer, artisan=self.artisan_profile,
            description='Resolution test job', agreed_price=Decimal('5000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Lagos', status=Job.Status.DISPUTED,
        )

        self.dispute = Dispute.objects.create(
            job=self.job, reason='poor_service',
            details='The work quality is very poor.',
        )

    def test_admin_can_resolve_dispute(self):
        """Admin should be able to resolve a dispute."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('disputes:dispute-resolve', kwargs={'pk': self.dispute.pk})
        payload = {
            'resolution': 'Partial refund issued to customer.',
        }
        resp = self.client.patch(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'resolved')

        # Verify dispute was resolved
        self.dispute.refresh_from_db()
        self.assertEqual(self.dispute.status, 'resolved')
        self.assertEqual(self.dispute.resolved_by, self.admin)

    def test_customer_cannot_resolve_dispute(self):
        """Customer should not be able to resolve a dispute (admin only)."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:dispute-resolve', kwargs={'pk': self.dispute.pk})
        payload = {'resolution': 'I resolve this myself.'}
        resp = self.client.patch(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_artisan_cannot_resolve_dispute(self):
        """Artisan should not be able to resolve a dispute (admin only)."""
        self.client.force_authenticate(user=self.artisan)
        url = reverse('disputes:dispute-resolve', kwargs={'pk': self.dispute.pk})
        payload = {'resolution': 'I resolve this myself.'}
        resp = self.client.patch(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_resolution_requires_resolution_details(self):
        """Resolution without a resolution description should fail."""
        self.client.force_authenticate(user=self.admin)
        url = reverse('disputes:dispute-resolve', kwargs={'pk': self.dispute.pk})
        payload = {'resolution': ''}
        resp = self.client.patch(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class DisputeReadonlyFieldsTests(TestCase):
    """Tests that dispute status, resolution, and resolved_by are read-only."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='ro_customer', email='ro_cust@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='ro_artisan', email='ro_art@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Mason',
        )

        self.job = Job.objects.create(
            customer=self.customer, artisan=self.artisan_profile,
            description='Readonly test job', agreed_price=Decimal('3000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Lagos', status=Job.Status.IN_PROGRESS,
        )

    def test_dispute_status_is_readonly(self):
        """Attempting to set status on creation should be ignored (read-only)."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:dispute-list-create')
        payload = {
            'job_id': self.job.pk,
            'reason': 'poor_service',
            'details': 'Bad quality.',
            'status': 'resolved',  # Should be ignored
        }
        resp = self.client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        # Status should be 'open' (default), not 'resolved'
        self.assertEqual(resp.data['status'], 'open')

    def test_dispute_resolved_by_is_readonly(self):
        """Attempting to set resolved_by on creation should be ignored."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:dispute-list-create')
        payload = {
            'job_id': self.job.pk,
            'reason': 'poor_service',
            'details': 'Bad quality.',
            'resolved_by': self.customer.pk,  # Should be ignored
        }
        resp = self.client.post(url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        # resolved_by should be None (not set by the customer)
        self.assertIsNone(resp.data.get('resolved_by'))


class EvidenceFileTests(TestCase):
    """Tests for evidence file upload on disputes."""

    def setUp(self):
        self.client = APIClient()

        self.customer = User.objects.create_user(
            username='ev_customer', email='ev_cust@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )
        self.artisan = User.objects.create_user(
            username='ev_artisan', email='ev_art@test.com',
            password='StrongPass123!', role='ARTISAN', is_active=True,
        )
        self.artisan_profile = ArtisanProfile.objects.create(
            user=self.artisan, profession='Roofer',
        )
        self.other_user = User.objects.create_user(
            username='ev_other', email='ev_other@test.com',
            password='StrongPass123!', role='CUSTOMER', is_active=True,
        )

        self.job = Job.objects.create(
            customer=self.customer, artisan=self.artisan_profile,
            description='Evidence test job', agreed_price=Decimal('5000.00'),
            scheduled_time=timezone.now() + timezone.timedelta(days=7),
            location='Lagos', status=Job.Status.DISPUTED,
        )

        self.dispute = Dispute.objects.create(
            job=self.job, reason='not_completed',
            details='Job was never completed.',
        )

    def _make_image_file(self, name='test.jpg', content_type='image/jpeg'):
        """Create a small in-memory image file for upload."""
        from PIL import Image
        image = Image.new('RGB', (10, 10), color='red')
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        buffer.seek(0)
        return SimpleUploadedFile(name=name, content=buffer.read(), content_type=content_type)

    def test_participant_can_upload_evidence(self):
        """A user involved in the dispute can upload evidence files."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        image_file = self._make_image_file()
        resp = self.client.post(url, {'file': image_file, 'caption': 'Photo of damage'}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['caption'], 'Photo of damage')

    def test_artisan_can_upload_evidence(self):
        """The artisan involved in the dispute can also upload evidence."""
        self.client.force_authenticate(user=self.artisan)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        image_file = self._make_image_file(name='artisan_evidence.jpg')
        resp = self.client.post(url, {'file': image_file, 'caption': 'Work completed'}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_non_participant_cannot_upload_evidence(self):
        """A user not involved in the dispute should be denied upload."""
        self.client.force_authenticate(user=self.other_user)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        image_file = self._make_image_file()
        resp = self.client.post(url, {'file': image_file}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_evidence_file_size_limit(self):
        """Uploading a file exceeding 10MB should be rejected."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        # Create a file larger than 10MB
        large_file = SimpleUploadedFile(
            name='large.jpg',
            content=b'\x00' * (11 * 1024 * 1024),  # 11MB
            content_type='image/jpeg',
        )
        resp = self.client.post(url, {'file': large_file}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_evidence_list_for_dispute(self):
        """Listing evidence files should only show files for the specific dispute."""
        # Upload a file first
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        image_file = self._make_image_file()
        self.client.post(url, {'file': image_file, 'caption': 'Evidence 1'}, format='multipart')

        # List evidence (paginated response)
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)

    def test_uploader_can_delete_own_evidence(self):
        """The user who uploaded an evidence file can delete it."""
        self.client.force_authenticate(user=self.customer)
        list_url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})

        image_file = self._make_image_file()
        resp = self.client.post(list_url, {'file': image_file, 'caption': 'To delete'}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        evidence_id = resp.data['id']

        # Delete the evidence
        delete_url = reverse('disputes:evidence-delete', kwargs={'pk': evidence_id})
        resp = self.client.delete(delete_url)
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)

    def test_non_uploader_cannot_delete_evidence(self):
        """A user who didn't upload the evidence cannot delete it (unless admin)."""
        # Customer uploads
        self.client.force_authenticate(user=self.customer)
        list_url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': self.dispute.pk})
        image_file = self._make_image_file()
        resp = self.client.post(list_url, {'file': image_file}, format='multipart')
        evidence_id = resp.data['id']

        # Artisan tries to delete (not uploader, not admin)
        self.client.force_authenticate(user=self.artisan)
        delete_url = reverse('disputes:evidence-delete', kwargs={'pk': evidence_id})
        resp = self.client.delete(delete_url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_dispute_nonexistent_for_evidence(self):
        """Uploading evidence for a non-existent dispute should fail."""
        self.client.force_authenticate(user=self.customer)
        url = reverse('disputes:evidence-list-create', kwargs={'dispute_pk': 99999})
        image_file = self._make_image_file()
        resp = self.client.post(url, {'file': image_file}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)