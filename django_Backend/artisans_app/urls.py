from django.urls import path
from .views import ArtisanDetailAPIView,ArtisanListAPIView,ArtisanProfile,ArtisanVerificationAPIView


urlpatterns = [
    path("artisan-details/", ArtisanDetailAPIView.as_view()),
    path("artisans-list/", ArtisanListAPIView.as_view()),
    path("artisans-profile/", ArtisanProfile.as_view()),
    path("verify-artisan", ArtisanVerificationAPIView.as_view()),
]