from django.urls import path

app_name = 'notifications'
from .views import (
    NotificationListAPIView,
    NotificationDetailAPIView,
    NotificationMarkAllReadView,
    UnreadCountView,
)

urlpatterns = [
    path('notifications/', NotificationListAPIView.as_view(), name='notification-list'),
    path('notifications/<int:pk>/', NotificationDetailAPIView.as_view(), name='notification-detail'),
    path('notifications/mark-all-read/', NotificationMarkAllReadView.as_view(), name='notification-mark-all-read'),
    path('notifications/unread-count/', UnreadCountView.as_view(), name='notification-unread-count'),
]