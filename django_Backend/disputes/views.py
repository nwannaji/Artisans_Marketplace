import logging
from decimal import Decimal, InvalidOperation

from rest_framework import generics, permissions, status
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Q
from django.utils import timezone
from .models import Dispute, EvidenceFile
from .serializers import DisputeSerializer, EvidenceFileSerializer
from accounts.models import User
from accounts.permissions import IsAdminRole
from bookings.models import Job

logger = logging.getLogger(__name__)


class DisputeListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = DisputeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Only show disputes related to jobs the user is involved in
        user = self.request.user
        if user.role == User.Role.ADMIN:
            return Dispute.objects.select_related('job__customer', 'job__artisan__user').all()
        return (Dispute.objects.filter(job__customer=user)
                | Dispute.objects.filter(job__artisan__user=user))

    def perform_create(self, serializer):
        user = self.request.user
        job = serializer.validated_data['job']

        # Ensure the user is either the customer or the artisan related to the job
        if job.customer != user and (not job.artisan or job.artisan.user != user):
            raise permissions.exceptions.PermissionDenied("You are not allowed to dispute this job.")

        dispute = serializer.save()

        # Set the related job status to DISPUTED
        if job.status != Job.Status.DISPUTED:
            job.status = Job.Status.DISPUTED
            job.save(update_fields=['status', 'updated_at'])


class DisputeRetrieveUpdateAPIView(generics.RetrieveUpdateAPIView):
    serializer_class = DisputeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        """SECURITY: Only allow users to see disputes for jobs they're involved in.
        Admins can see all disputes."""
        user = self.request.user
        if user.role == User.Role.ADMIN:
            return Dispute.objects.select_related('job__customer', 'job__artisan__user')
        return Dispute.objects.filter(
            Q(job__customer=user) | Q(job__artisan__user=user)
        )

    def perform_update(self, serializer):
        user = self.request.user
        dispute = self.get_object()

        # Only allow the dispute to be updated by an admin or the user who raised the dispute
        if user.role != User.Role.ADMIN:
            if user != dispute.job.customer and (not dispute.job.artisan or dispute.job.artisan.user != user):
                raise permissions.exceptions.PermissionDenied("You are not authorized to update this dispute.")

        serializer.save()


class DisputeResolveAPIView(generics.UpdateAPIView):
    queryset = Dispute.objects.all()
    serializer_class = DisputeSerializer
    permission_classes = [IsAdminRole]  # Only admin can resolve disputes
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        from django.db import transaction as db_transaction

        with db_transaction.atomic():
            dispute = Dispute.objects.select_for_update().get(pk=kwargs['pk'])

            # Admins can resolve the dispute
            resolution_data = request.data.get('resolution', None)
            resolution_amount = request.data.get('resolution_amount', None)

            if resolution_data is None:
                return Response(
                    {"error": "Resolution details are required."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            dispute.resolution = resolution_data
            dispute.resolved_by = request.user
            dispute.resolved_at = timezone.now()

            # If resolution_amount is provided, handle escrow refund
            if resolution_amount is not None:
                try:
                    resolution_amount = Decimal(str(resolution_amount))
                    if resolution_amount < 0:
                        raise InvalidOperation("Negative amount")
                except (InvalidOperation, ValueError):
                    return Response(
                        {"error": "resolution_amount must be a positive number."},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                dispute.resolution_amount = resolution_amount

                # If the job has escrow held, process refund
                job = dispute.job
                if job.escrow_held_amount and job.escrow_held_amount > 0:
                    refund_amount = min(resolution_amount, job.escrow_held_amount)
                    from payments.utils import process_escrow_refund
                    process_escrow_refund(job, refund_amount)

            dispute.status = Dispute.Status.RESOLVED
            dispute.save()

            # Update job status to DISPUTED
            dispute.job.status = Job.Status.DISPUTED
            dispute.job.save(update_fields=['status', 'updated_at'])

            logger.info(
                "Dispute %s resolved by admin %s",
                dispute.pk, request.user.username,
            )

        return Response(DisputeSerializer(dispute).data)


class EvidenceFileListCreateAPIView(generics.ListCreateAPIView):
    """List or upload evidence files for a dispute.

    GET  /api/disputes/evidence/<dispute_pk>/  — list evidence files
    POST /api/disputes/evidence/<dispute_pk>/  — upload an evidence file (multipart)
    """
    serializer_class = EvidenceFileSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        dispute_pk = self.kwargs.get('dispute_pk')
        return EvidenceFile.objects.filter(dispute_id=dispute_pk).select_related('uploaded_by')

    def perform_create(self, serializer):
        dispute_pk = self.kwargs.get('dispute_pk')
        # Verify the user is a participant in the dispute
        try:
            dispute = Dispute.objects.get(pk=dispute_pk)
        except Dispute.DoesNotExist:
            from rest_framework.exceptions import ValidationError
            raise ValidationError("Dispute not found.")

        user = self.request.user
        if user.role != User.Role.ADMIN and user != dispute.job.customer and (not dispute.job.artisan or dispute.job.artisan.user != user):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("You are not a participant in this dispute.")

        # Store the file's content type
        file_obj = serializer.validated_data.get('file')
        file_type = ''
        if file_obj:
            file_type = getattr(file_obj, 'content_type', '') or ''

        serializer.save(
            uploaded_by=self.request.user,
            dispute_id=dispute_pk,
            file_type=file_type,
        )


class EvidenceFileDeleteAPIView(generics.DestroyAPIView):
    """Delete an evidence file. Only the uploader or an admin can delete."""
    serializer_class = EvidenceFileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return EvidenceFile.objects.all()

    def perform_destroy(self, instance):
        # Only the uploader or admin can delete
        if self.request.user.role != User.Role.ADMIN and instance.uploaded_by != self.request.user:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("You can only delete your own evidence files.")
        # Delete the actual file from storage
        if instance.file:
            try:
                instance.file.delete(save=False)
            except Exception:
                logger.warning("Failed to delete evidence file %s", instance.file.name)
        instance.delete()