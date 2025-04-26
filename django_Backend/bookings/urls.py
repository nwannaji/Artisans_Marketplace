from django.urls import path
from .views import (
    JobListCreateAPIView,
    JobRetrieveUpdateDestroyAPIView,
    JobStatusUpdateAPIView
)
app_name='bookings'

urlpatterns = [
    path('', JobListCreateAPIView.as_view(), name='create'),
    path('<int:pk>/', JobRetrieveUpdateDestroyAPIView.as_view(), name='detail'),
    path('<int:pk>/status/', JobStatusUpdateAPIView.as_view(), name='status'),
]
