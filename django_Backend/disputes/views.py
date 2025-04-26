from rest_framework import generics, permissions, status
from rest_framework.response import Response
from .models import Dispute
from .serializers import DisputeSerializer
from accounts.models import User

class DisputeListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = DisputeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Only show disputes related to jobs the user is involved in
        user = self.request.user
        return Dispute.objects.filter(job__customer=user) | Dispute.objects.filter(job__artisan__user=user)

    def perform_create(self, serializer):
        user = self.request.user
        job = serializer.validated_data['job']
        
        # Ensure the user is either the customer or the artisan related to the job
        if job.customer != user and job.artisan.user != user:
            raise permissions.exceptions.PermissionDenied("You are not allowed to dispute this job.")
        
        serializer.save()

class DisputeRetrieveUpdateAPIView(generics.RetrieveUpdateAPIView):
    queryset = Dispute.objects.all()
    serializer_class = DisputeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_update(self, serializer):
        user = self.request.user
        dispute = self.get_object()
        
        # Only allow the dispute status to be updated by an admin or the user who raised the dispute
        if user != dispute.job.customer and user != dispute.job.artisan.user:
            raise permissions.exceptions.PermissionDenied("You are not authorized to update this dispute.")

        # You can add logic for only allowing certain status transitions if needed
        serializer.save()

class DisputeResolveAPIView(generics.UpdateAPIView):
    queryset = Dispute.objects.all()
    serializer_class = DisputeSerializer
    permission_classes = [permissions.IsAdminUser]  # Only admin can resolve disputes
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        dispute = self.get_object()
        
        # Admins can resolve the dispute
        resolution_data = request.data.get('resolution', None)
        resolution_amount = request.data.get('resolution_amount', None)

        if resolution_data is None or resolution_amount is None:
            return Response({"detail": "Resolution details and resolution amount are required."}, status=status.HTTP_400_BAD_REQUEST)
        
        dispute.resolution = resolution_data
        dispute.resolution_amount = resolution_amount
        dispute.status = Dispute.RESOLVED
        dispute.resolved_by = request.user
        dispute.resolved_at = timezone.now()
        
        dispute.save()
        return Response(self.get_serializer(dispute).data)
