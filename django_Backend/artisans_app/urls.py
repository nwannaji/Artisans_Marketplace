from django.urls import path
from .views import (
    ArtisanListAPIView, ArtisanDetailAPIView,
    ArtisanProfileUpdateAPIView, ArtisanProfileCreateAPIView,
    ArtisanNearbySearchAPIView, ProfessionListAPIView,
    PortfolioImageListCreateAPIView, PortfolioImageDetailAPIView
)
from reviews.views import ArtisanReviewListCreateView, MyArtisanReviewView

app_name = 'artisans_app'

urlpatterns = [
    path('', ArtisanListAPIView.as_view(), name='list'),
    path('nearby/', ArtisanNearbySearchAPIView.as_view(), name='nearby-search'),
    path('professions/', ProfessionListAPIView.as_view(), name='professions'),
    path('create/', ArtisanProfileCreateAPIView.as_view(), name='create'),
    path('<int:artisan_pk>/reviews/', ArtisanReviewListCreateView.as_view(), name='reviews'),
    path('<int:artisan_pk>/reviews/mine/', MyArtisanReviewView.as_view(), name='my-review'),
    path('<int:pk>/', ArtisanDetailAPIView.as_view(), name='detail'),
    path('<int:pk>/verify/', ArtisanProfileUpdateAPIView.as_view(), name='verify'),
    path('portfolio/', PortfolioImageListCreateAPIView.as_view(), name='portfolio-list-create'),
    path('portfolio/<int:pk>/', PortfolioImageDetailAPIView.as_view(), name='portfolio-detail'),
]