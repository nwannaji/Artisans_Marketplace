import logging

from .models import Notification

logger = logging.getLogger(__name__)


def create_notification(user, notification_type, title, message,
                        related_object_type=None, related_object_id=None):
    """Create an in-app notification for a user.

    This is the primary entry point for other apps to create notifications.
    Returns the created Notification instance.

    Args:
        user: The User instance to notify.
        notification_type: One of Notification.NotificationType values
                          ('job_status', 'escrow', 'dispute', 'chat', 'payment', 'system').
        title: Short subject line for the notification.
        message: Detailed body text.
        related_object_type: Optional string identifying the object type (e.g. 'job', 'dispute').
        related_object_id: Optional integer PK of the related object.

    Returns:
        Notification instance.
    """
    try:
        notification = Notification.objects.create(
            user=user,
            notification_type=notification_type,
            title=title,
            message=message,
            related_object_type=related_object_type,
            related_object_id=related_object_id,
        )
        logger.info(
            "Created notification %s for user %s: %s",
            notification.pk, user.pk, title,
        )
        return notification
    except Exception:
        logger.exception(
            "Failed to create notification for user %s: %s",
            user.pk, title,
        )
        raise