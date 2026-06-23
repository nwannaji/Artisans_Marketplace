from django.urls import path
from .views import (
    UserRegistrationAPIView,
    UserLoginAPIView,
    CurrentUserAPIView,
    ChangePasswordView,
    ArtisanAvailabilityToggleView,
    ArtisanProfileSelfUpdateView,
    UserActivateAPIView,
    CustomerListAPIView,
    ArtisanLocationUpdateView,
    ProfilePictureUploadView,
)
app_name = 'accounts'

urlpatterns = [
    path('register/', UserRegistrationAPIView.as_view(), name='user-register'),
    path('login/', UserLoginAPIView.as_view(), name='user-login'),
    path('me/', CurrentUserAPIView.as_view(), name='current-user'),
    path('me/upload-picture/', ProfilePictureUploadView.as_view(), name='upload-profile-picture'),
    path('me/artisan-profile/', ArtisanProfileSelfUpdateView.as_view(), name='artisan-self-profile'),
    path('me/availability/', ArtisanAvailabilityToggleView.as_view(), name='artisan-availability'),
    path('me/update-location/', ArtisanLocationUpdateView.as_view(), name='artisan-location-update'),
    path('change-password/', ChangePasswordView.as_view(), name='change-password'),
    path('users/<int:pk>/activate/', UserActivateAPIView.as_view(), name='user-activate'),
    path('customers/', CustomerListAPIView.as_view(), name='customer-list'),
]