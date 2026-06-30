from django.urls import path
from .views import (
    DisputeListCreateAPIView,
    DisputeRetrieveUpdateAPIView,
    DisputeResolveAPIView,
    EvidenceFileListCreateAPIView,
    EvidenceFileDeleteAPIView,
)

app_name = 'disputes'

urlpatterns = [
    path('disputes/', DisputeListCreateAPIView.as_view(), name='dispute-list-create'),
    path('disputes/<int:pk>/', DisputeRetrieveUpdateAPIView.as_view(), name='dispute-retrieve-update'),
    path('disputes/resolve/<int:pk>/', DisputeResolveAPIView.as_view(), name='dispute-resolve'),
    path('disputes/evidence/<int:dispute_pk>/', EvidenceFileListCreateAPIView.as_view(), name='evidence-list-create'),
    path('disputes/evidence/<int:pk>/delete/', EvidenceFileDeleteAPIView.as_view(), name='evidence-delete'),
]