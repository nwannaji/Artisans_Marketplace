from django.forms import ValidationError
from django.shortcuts import render
from rest_framework import status

# Create your views here.
from rest_framework import generics, permissions, filters
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.response import Response
from accounts.models import User, ArtisanProfile
from  accounts.serializers import ArtisanProfileSerializer
from  artisans_app.filters import ArtisanFilter

class ArtisanProfileCreateAPIView(generics.CreateAPIView):
    queryset = ArtisanProfile.objects.all()
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        if ArtisanProfile.objects.filter(user=self.request.user).exists():
            raise ValidationError("You already have an artisan profile.")
        serializer.save(user=self.request.user)

    def create(self, request, *args, **kwargs):
        response = super().create(request, *args, **kwargs)
        return Response({
            "message": "Artisan profile created successfully.",
            "artisan_profile": response.data
        }, status=status.HTTP_201_CREATED)


class ArtisanListAPIView(generics.ListAPIView):
    queryset = ArtisanProfile.objects.filter(user__is_active=True, is_verified=True)
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.AllowAny]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_class = ArtisanFilter  # Using our custom filter
    search_fields = ['profession', 'skills', 'location']
    ordering_fields = ['rating', 'hourly_rate', 'jobs_completed']

class ArtisanDetailAPIView(generics.RetrieveAPIView):
    queryset = ArtisanProfile.objects.filter(user__is_active=True, is_verified=True)
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.AllowAny]

class ArtisanProfileUpdateAPIView(generics.UpdateAPIView):
    queryset = ArtisanProfile.objects.all()
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        # Admins can update any profile, but users can only update their own
        if self.request.user.is_staff:
            return ArtisanProfile.objects.get(pk=self.kwargs['pk'])
        return ArtisanProfile.objects.get(user=self.request.user)

    def perform_update(self, serializer):
        serializer.save()


