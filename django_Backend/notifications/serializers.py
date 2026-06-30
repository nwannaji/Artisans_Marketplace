from rest_framework import serializers
from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    """Full notification serializer — used for listing and retrieving."""

    class Meta:
        model = Notification
        fields = [
            'id', 'user', 'notification_type', 'title', 'message',
            'related_object_type', 'related_object_id', 'is_read', 'created_at',
        ]
        read_only_fields = ['id', 'user', 'notification_type', 'title', 'message',
                            'related_object_type', 'related_object_id', 'created_at']

    def update(self, instance, validated_data):
        # Only allow updating is_read via this serializer
        instance.is_read = validated_data.get('is_read', instance.is_read)
        instance.save(update_fields=['is_read'])
        return instance


class NotificationUpdateSerializer(serializers.ModelSerializer):
    """Minimal serializer for PATCH requests — only is_read."""

    class Meta:
        model = Notification
        fields = ['is_read']