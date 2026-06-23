from django.urls import path
from .views import (
    ArtisanListAPIView, ArtisanDetailAPIView,
    ArtisanProfileUpdateAPIView, ArtisanProfileCreateAPIView,
    ArtisanNearbySearchAPIView, ProfessionListAPIView
)

app_name = 'artisans_app'

urlpatterns = [
    path('', ArtisanListAPIView.as_view(), name='list'),
    path('nearby/', ArtisanNearbySearchAPIView.as_view(), name='nearby-search'),
    path('professions/', ProfessionListAPIView.as_view(), name='professions'),
    path('create/', ArtisanProfileCreateAPIView.as_view(), name='create'),
    path('<int:pk>/', ArtisanDetailAPIView.as_view(), name='detail'),
    path('<int:pk>/verify/', ArtisanProfileUpdateAPIView.as_view(), name='verify'),
]