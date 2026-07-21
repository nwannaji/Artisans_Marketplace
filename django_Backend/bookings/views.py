import logging

from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError as DRFValidationError
from django_filters.rest_framework import DjangoFilterBackend
from django.utils import timezone
from django.db import transaction as db_transaction
from django.db.models import Avg, Count, Q
from accounts.permissions import IsAdminRole
from .models import Job
from .serializers import JobSerializer, JobCreateSerializer, JobRatingSerializer
from accounts.models import User
from accounts.models import ArtisanProfile

logger = logging.getLogger(__name__)


class JobListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['status', 'artisan', 'customer']

    def get_serializer_class(self):
        if self.request.method == 'POST':
            return JobCreateSerializer
        return JobSerializer

    def get_queryset(self):
        user = self.request.user

        # Artisans see jobs assigned to them
        if user.role == User.Role.ARTISAN:
            return Job.objects.filter(artisan__user=user)

        # Customers see their own jobs
        elif user.role == User.Role.CUSTOMER:
            return Job.objects.filter(customer=user)

        # Admins see all jobs
        elif user.role == User.Role.ADMIN:
            return Job.objects.all()

        return Job.objects.none()

    def perform_create(self, serializer):
        if self.request.user.role != User.Role.CUSTOMER:
            raise permissions.exceptions.PermissionDenied(
                "Only customers can create jobs"
            )
        serializer.save(customer=self.request.user)


class JobRetrieveUpdateDestroyAPIView(generics.RetrieveUpdateAPIView):
    """Retrieve or update a job. Deletion is NOT allowed — use cancellation instead."""
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    http_method_names = ['get', 'patch', 'put']  # SECURITY: No DELETE method

    def get_queryset(self):
        """Users can only see jobs they are involved in (unless admin)."""
        user = self.request.user
        if user.role == User.Role.ADMIN:
            return Job.objects.all()
        if user.role == User.Role.ARTISAN:
            return Job.objects.filter(artisan__user=user) | Job.objects.filter(customer=user)
        return Job.objects.filter(customer=user)

    def get_serializer_class(self):
        if self.request.method in ['PUT', 'PATCH']:
            return JobCreateSerializer
        return JobSerializer

    def perform_update(self, serializer):
        job = self.get_object()
        user = self.request.user

        # SECURITY: Prevent field changes on jobs that are past the PENDING stage
        # Only status transitions should be allowed via the dedicated status endpoints
        protected_fields = {'agreed_price', 'description', 'scheduled_time', 'location', 'latitude', 'longitude'}
        if job.status not in [Job.Status.PENDING, Job.Status.ADMIN_APPROVED]:
            changed_protected = protected_fields & set(serializer.validated_data.keys())
            if changed_protected:
                raise permissions.exceptions.PermissionDenied(
                    f"Cannot modify {', '.join(changed_protected)} on a job that is {job.get_status_display()}. "
                    "Use the status endpoint to update job progress."
                )

        # Only allow status updates for artisans
        if user.role == User.Role.ARTISAN and job.artisan and job.artisan.user != user:
            raise permissions.exceptions.PermissionDenied(
                "You can only update your own jobs"
            )

        # Customers can only cancel jobs
        if user.role == User.Role.CUSTOMER:
            if job.customer != user:
                raise permissions.exceptions.PermissionDenied(
                    "You can only update your own jobs"
                )
            if serializer.validated_data.get('status') != Job.Status.CANCELLED:
                raise permissions.exceptions.PermissionDenied(
                    "Customers can only cancel jobs"
                )

        serializer.save()


class AdminApproveJobAPIView(generics.UpdateAPIView):
    """Admin approves a PENDING job, changing status to ADMIN_APPROVED."""
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [IsAdminRole]
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=kwargs['pk'])
            if job.status != Job.Status.PENDING:
                return Response(
                    {"error": "Only PENDING jobs can be approved"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            job.status = Job.Status.ADMIN_APPROVED
            job.admin_approved_by = request.user
            job.admin_approved_at = timezone.now()
            job.save()
        return Response(JobSerializer(job).data)


class AdminRejectJobAPIView(generics.UpdateAPIView):
    """Admin rejects a PENDING job, changing status to REJECTED."""
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [IsAdminRole]
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=kwargs['pk'])
            if job.status != Job.Status.PENDING:
                return Response(
                    {"error": "Only PENDING jobs can be rejected"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            job.status = Job.Status.REJECTED
            job.save(update_fields=['status', 'updated_at'])
        return Response(JobSerializer(job).data)


class ArtisanAcceptJobAPIView(generics.UpdateAPIView):
    """Artisan accepts an ADMIN_APPROVED job, assigning themselves."""
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=kwargs['pk'])
            if job.status != Job.Status.ADMIN_APPROVED:
                return Response(
                    {"error": "Only ADMIN_APPROVED jobs can be accepted"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if request.user.role != User.Role.ARTISAN:
                return Response(
                    {"error": "Only artisans can accept jobs"},
                    status=status.HTTP_403_FORBIDDEN
                )
            try:
                artisan_profile = ArtisanProfile.objects.get(user=request.user)
            except ArtisanProfile.DoesNotExist:
                return Response(
                    {"error": "Artisan profile not found"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            job.artisan = artisan_profile
            job.status = Job.Status.ACCEPTED
            job.save()
        return Response(JobSerializer(job).data)


class JobStatusUpdateAPIView(generics.UpdateAPIView):
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        with db_transaction.atomic():
            job = Job.objects.select_for_update().get(pk=kwargs['pk'])
            new_status = request.data.get('status')
            user = request.user

            # Any role can cancel from PENDING, ADMIN_APPROVED, ACCEPTED, or IN_PROGRESS
            if new_status == Job.Status.CANCELLED:
                if job.status in [Job.Status.PENDING, Job.Status.ADMIN_APPROVED,
                                  Job.Status.ACCEPTED, Job.Status.IN_PROGRESS,
                                  Job.Status.AWAITING_REVIEW]:
                    # Customer or the assigned artisan can cancel
                    if user.role == User.Role.CUSTOMER and job.customer != user:
                        return Response(
                            {"error": "You can only cancel your own jobs"},
                            status=status.HTTP_403_FORBIDDEN
                        )
                    job.status = new_status
                    job.save()
                    return Response(JobSerializer(job).data)

            # Validate status transitions
            valid_transitions = {
                Job.Status.ACCEPTED: [Job.Status.IN_PROGRESS, Job.Status.CANCELLED],
                Job.Status.IN_PROGRESS: [Job.Status.AWAITING_REVIEW, Job.Status.DISPUTED, Job.Status.CANCELLED],
                Job.Status.AWAITING_REVIEW: [Job.Status.COMPLETED, Job.Status.DISPUTED, Job.Status.CANCELLED],
            }

            if job.status not in valid_transitions:
                return Response(
                    {"error": f"Cannot transition from {job.get_status_display()}"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if new_status not in valid_transitions[job.status]:
                return Response(
                    {"error": f"Cannot transition from {job.get_status_display()} to {new_status}"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Role-based checks for specific transitions
            if new_status == Job.Status.IN_PROGRESS:
                if user.role != User.Role.ARTISAN or (job.artisan and job.artisan.user != user):
                    return Response(
                        {"error": "Only the assigned artisan can start the job"},
                        status=status.HTTP_403_FORBIDDEN
                    )

            if new_status == Job.Status.AWAITING_REVIEW:
                if user.role != User.Role.ARTISAN or (job.artisan and job.artisan.user != user):
                    return Response(
                        {"error": "Only the assigned artisan can mark the job as done"},
                        status=status.HTTP_403_FORBIDDEN
                    )

            if new_status == Job.Status.COMPLETED:
                if user.role != User.Role.CUSTOMER or job.customer != user:
                    return Response(
                        {"error": "Only the customer can approve the job completion"},
                        status=status.HTTP_403_FORBIDDEN
                    )

            job.status = new_status
            job.save()

        return Response(JobSerializer(job).data)


class JobCreateWithArtisanAPIView(generics.CreateAPIView):
    """Customer creates a job pre-assigned to a specific available artisan.

    The job still goes through the PENDING → ADMIN_APPROVED → ACCEPTED flow,
    but the artisan is linked from creation time, reserving their slot.
    """
    serializer_class = JobCreateSerializer
    permission_classes = [permissions.IsAuthenticated]

    def create(self, request, *args, **kwargs):
        if request.user.role != User.Role.CUSTOMER:
            return Response(
                {"error": "Only customers can create jobs"},
                status=status.HTTP_403_FORBIDDEN
            )

        artisan_id = request.data.get('artisan_id')
        if not artisan_id:
            raise DRFValidationError({"artisan_id": "This field is required."})

        try:
            artisan = ArtisanProfile.objects.get(pk=artisan_id, user__is_active=True)
        except ArtisanProfile.DoesNotExist:
            raise DRFValidationError({"artisan_id": "Artisan not found or inactive."})

        if artisan.is_available == ArtisanProfile.AvailabilityStatus.ENGAGED:
            raise DRFValidationError(
                {"artisan_id": "This artisan is currently engaged with another booking. "
                               "Please try again later or choose a different artisan."}
            )
        elif artisan.is_available != ArtisanProfile.AvailabilityStatus.AVAILABLE:
            raise DRFValidationError(
                {"artisan_id": "This artisan is currently not available. "
                               f"Status: {artisan.get_is_available_display()}"}
            )

        # Inject the artisan into the request data so the serializer can use it
        data = request.data.copy()
        # Remove artisan_id so it doesn't cause serializer issues
        data.pop('artisan_id', None)

        serializer = self.get_serializer(data=data)
        serializer.is_valid(raise_exception=True)
        job = serializer.save(
            customer=request.user,
            artisan=artisan,
            status=Job.Status.PENDING,
        )

        # Set artisan to ENGAGED now that a booking has been created for them
        ArtisanProfile.objects.filter(pk=artisan.pk).update(
            is_available=ArtisanProfile.AvailabilityStatus.ENGAGED
        )

        return Response({
            "message": "Job created and assigned to artisan. Awaiting admin approval.",
            "job": JobSerializer(job).data,
        }, status=status.HTTP_201_CREATED)


class JobRatingAPIView(generics.GenericAPIView):
    """Allow a customer to rate and review a completed job.

    POST /api/bookings/<pk>/rate/
    Body: { "rating": 1-5, "review": "optional text" }

    This also recalculates the artisan's aggregate rating and jobs_completed count.
    """
    serializer_class = JobRatingSerializer
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, *args, **kwargs):
        job = self.get_object()

        # Only the customer who created the job can rate it
        if job.customer != request.user:
            return Response(
                {"error": "Only the customer who created this job can rate it."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Job must be completed
        if job.status != Job.Status.COMPLETED:
            return Response(
                {"error": "Only completed jobs can be rated."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Job must not already be rated
        if job.rating is not None:
            return Response(
                {"error": "This job has already been rated."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Job must have an assigned artisan
        if job.artisan is None:
            return Response(
                {"error": "This job has no assigned artisan to rate."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Save rating and review to the job
        job.rating = serializer.validated_data['rating']
        job.review = serializer.validated_data.get('review', '')
        job.save(update_fields=['rating', 'review'])

        # Also create/update a Review record for this customer-artisan pair
        from reviews.models import Review
        Review.objects.update_or_create(
            customer=job.customer,
            artisan=job.artisan,
            defaults={
                'rating': job.rating,
                'comment': job.review or '',
                'job': job,
            },
        )

        # Recalculate jobs_completed from completed jobs (reviews handle rating via signal)
        artisan = job.artisan
        agg = Job.objects.filter(
            artisan=artisan,
            status=Job.Status.COMPLETED,
        ).aggregate(
            completed_count=Count('id'),
        )
        artisan.jobs_completed = agg['completed_count'] or 0
        artisan.save(update_fields=['jobs_completed'])

        return Response({
            "message": "Rating submitted successfully.",
            "job": JobSerializer(job).data,
        }, status=status.HTTP_200_OK)

    def get_object(self):
        from django.shortcuts import get_object_or_404
        return get_object_or_404(Job, pk=self.kwargs['pk'])