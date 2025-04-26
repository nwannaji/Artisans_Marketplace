from django.urls import path
from .views import DisputeListCreateAPIView, DisputeRetrieveUpdateAPIView, DisputeResolveAPIView

urlpatterns = [
    path('disputes/', DisputeListCreateAPIView.as_view(), name='dispute-list-create'),
    path('disputes/<int:pk>/', DisputeRetrieveUpdateAPIView.as_view(), name='dispute-retrieve-update'),
    path('disputes/resolve/<int:pk>/', DisputeResolveAPIView.as_view(), name='dispute-resolve'),
]
