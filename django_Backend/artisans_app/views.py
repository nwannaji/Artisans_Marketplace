from django.shortcuts import render

# Create your views here.
from rest_framework import generics, permissions, filters
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework.response import Response
from accounts.models import User, ArtisanProfile
from  accounts.serializers import ArtisanProfileSerializer
from  django_filters import ArtisanFilter

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

class ArtisanVerificationAPIView(generics.UpdateAPIView):
    queryset = ArtisanProfile.objects.all()
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.IsAdminUser]
    
    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        instance.is_verified = request.data.get('is_verified', instance.is_verified)
        
        # Activate user account when verified
        if instance.is_verified and not instance.user.is_active:
            instance.user.is_active = True
            instance.user.save()
        
        instance.save()
        serializer = self.get_serializer(instance)
        return Response(serializer.data)