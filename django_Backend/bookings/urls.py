from django.urls import path
from .views import (
    JobListCreateAPIView,
    JobRetrieveUpdateDestroyAPIView,
    JobStatusUpdateAPIView,
    AdminApproveJobAPIView,
    AdminRejectJobAPIView,
    ArtisanAcceptJobAPIView,
    JobCreateWithArtisanAPIView,
    JobRatingAPIView,
)
app_name = 'bookings'

urlpatterns = [
    path('', JobListCreateAPIView.as_view(), name='create'),
    path('create-with-artisan/', JobCreateWithArtisanAPIView.as_view(), name='create-with-artisan'),
    path('<int:pk>/', JobRetrieveUpdateDestroyAPIView.as_view(), name='detail'),
    path('<int:pk>/status/', JobStatusUpdateAPIView.as_view(), name='status'),
    path('<int:pk>/approve/', AdminApproveJobAPIView.as_view(), name='admin-approve'),
    path('<int:pk>/reject/', AdminRejectJobAPIView.as_view(), name='admin-reject'),
    path('<int:pk>/accept/', ArtisanAcceptJobAPIView.as_view(), name='artisan-accept'),
    path('<int:pk>/rate/', JobRatingAPIView.as_view(), name='rate'),
]