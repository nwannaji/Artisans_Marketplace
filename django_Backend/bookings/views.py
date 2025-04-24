from rest_framework import generics, permissions, status
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from django.utils import timezone
from .models import Job
from .serializers import JobSerializer, JobCreateSerializer
from apps.accounts.models import User
from apps.artisans.models import ArtisanProfile

class JobListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['status', 'artisan', 'customer']

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

    def get_serializer_class(self):
        if self.request.method == 'POST':
            return JobCreateSerializer
        return JobSerializer

    def perform_create(self, serializer):
        if self.request.user.role != User.Role.CUSTOMER:
            raise permissions.exceptions.PermissionDenied(
                "Only customers can create jobs"
            )
        serializer.save(customer=self.request.user)

class JobRetrieveUpdateDestroyAPIView(generics.RetrieveUpdateDestroyAPIView):
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_serializer_class(self):
        if self.request.method in ['PUT', 'PATCH']:
            return JobCreateSerializer
        return JobSerializer

    def perform_update(self, serializer):
        job = self.get_object()
        user = self.request.user
        
        # Only allow status updates for artisans
        if user.role == User.Role.ARTISAN and job.artisan.user != user:
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

class JobStatusUpdateAPIView(generics.UpdateAPIView):
    queryset = Job.objects.all()
    serializer_class = JobSerializer
    permission_classes = [permissions.IsAuthenticated]
    http_method_names = ['patch']

    def patch(self, request, *args, **kwargs):
        job = self.get_object()
        new_status = request.data.get('status')
        user = request.user

        # Artisan can only update their own jobs
        if user.role == User.Role.ARTISAN and job.artisan.user != user:
            return Response(
                {"error": "You can only update your own jobs"},
                status=status.HTTP_403_FORBIDDEN
            )

        # Validate status transitions
        valid_transitions = {
            Job.Status.SCHEDULED: [Job.Status.IN_PROGRESS, Job.Status.CANCELLED],
            Job.Status.IN_PROGRESS: [Job.Status.COMPLETED, Job.Status.DISPUTED],
        }

        if job.status not in valid_transitions or new_status not in valid_transitions[job.status]:
            return Response(
                {"error": "Invalid status transition"},
                status=status.HTTP_400_BAD_REQUEST
            )

        job.status = new_status
        job.save()
        return Response(self.get_serializer(job)).data