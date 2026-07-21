from django.urls import path
from .views import ArtisanReviewListCreateView, MyArtisanReviewView, ReviewDetailView

app_name = 'reviews'

urlpatterns = [
    path('<int:review_pk>/', ReviewDetailView.as_view(), name='review-detail'),
]