import logging

from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Count, Q

from .models import Notification
from .serializers import NotificationSerializer, NotificationUpdateSerializer

logger = logging.getLogger(__name__)


class NotificationListAPIView(generics.ListAPIView):
    """List the authenticated user's notifications.

    Supports filtering by unread status via ?unread=true query parameter.
    """
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        queryset = Notification.objects.filter(user=self.request.user)
        unread = self.request.query_params.get('unread')
        if unread and unread.lower() == 'true':
            queryset = queryset.filter(is_read=False)
        return queryset


class NotificationDetailAPIView(generics.RetrieveUpdateAPIView):
    """Retrieve or update a single notification.

    GET returns the notification details.
    PATCH allows marking the notification as read/unread.
    Users can only access their own notifications.
    """
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)

    def get_serializer_class(self):
        if self.request.method in ('PATCH', 'PUT'):
            return NotificationUpdateSerializer
        return NotificationSerializer


class NotificationMarkAllReadView(APIView):
    """POST to mark all of the current user's notifications as read."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        updated = Notification.objects.filter(
            user=request.user,
            is_read=False,
        ).update(is_read=True)
        return Response({
            'message': 'All notifications marked as read.',
            'updated_count': updated,
        }, status=status.HTTP_200_OK)


class UnreadCountView(APIView):
    """GET returns the count of unread notifications for the current user."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        count = Notification.objects.filter(
            user=request.user,
            is_read=False,
        ).count()
        return Response({'unread_count': count})