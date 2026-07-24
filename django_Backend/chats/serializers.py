from datetime import timedelta

from rest_framework import serializers
from django.utils import timezone
from .models import Conversation, Chat
from accounts.models import User


class ChatSerializer(serializers.ModelSerializer):
    sender_username = serializers.CharField(source='sender.username', read_only=True)
    audio_file_url = serializers.SerializerMethodField()

    class Meta:
        model = Chat
        fields = ['id', 'conversation', 'sender', 'sender_username',
                  'message', 'message_type', 'audio_file', 'audio_file_url',
                  'audio_duration', 'latitude', 'longitude', 'location_label',
                  'is_admin_message', 'timestamp', 'is_read']
        read_only_fields = ['id', 'conversation', 'sender', 'sender_username', 'timestamp',
                            'is_admin_message', 'message_type', 'audio_file_url']

    def validate_message(self, value):
        if value and len(value) > 2000:
            raise serializers.ValidationError("Message must be 2000 characters or fewer.")
        return value

    def get_audio_file_url(self, obj):
        if obj.audio_file:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.audio_file.url)
            return obj.audio_file.url
        return None


class ConversationSerializer(serializers.ModelSerializer):
    client_username = serializers.CharField(source='client.username', read_only=True)
    artisan_username = serializers.CharField(source='artisan.username', read_only=True)
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()
    other_user_online = serializers.SerializerMethodField()
    message_ttl_days = serializers.IntegerField(min_value=0, required=False)

    class Meta:
        model = Conversation
        fields = ['id', 'client', 'client_username', 'artisan', 'artisan_username',
                  'admin', 'related_job', 'conversation_type', 'is_active',
                  'message_ttl_days', 'created_at', 'last_message', 'unread_count',
                  'other_user_online']
        read_only_fields = ['created_at']

    def validate_message_ttl_days(self, value):
        valid = [choice[0] for choice in Conversation.MESSAGE_TTL_CHOICES]
        if value not in valid:
            raise serializers.ValidationError(
                f"message_ttl_days must be one of {valid}"
            )
        return value

    def get_last_message(self, obj):
        last_msg = obj.messages.order_by('-timestamp').first()
        if last_msg:
            result = {
                'message': last_msg.message,
                'sender': last_msg.sender.username,
                'timestamp': last_msg.timestamp,
                'is_admin_message': last_msg.is_admin_message,
                'is_read': last_msg.is_read,
                'message_type': last_msg.message_type,
            }
            if last_msg.audio_file:
                request = self.context.get('request')
                if request:
                    result['audio_file_url'] = request.build_absolute_uri(last_msg.audio_file.url)
                else:
                    result['audio_file_url'] = last_msg.audio_file.url
                result['audio_duration'] = last_msg.audio_duration
            if last_msg.message_type == 'location':
                result['latitude'] = last_msg.latitude
                result['longitude'] = last_msg.longitude
                result['location_label'] = last_msg.location_label
            return result
        return None

    def get_unread_count(self, obj):
        """Count unread messages for the requesting user (messages sent by others)."""
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return obj.messages.filter(is_read=False).exclude(sender=request.user).count()
        return 0

    def get_other_user_online(self, obj):
        """Return whether the other participant in the conversation is online.

        Online means last_active was within the last 3 minutes.
        The 'other user' is the one who is NOT the requesting user.
        """
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False

        # Determine the other user in the conversation
        if request.user.id == obj.client_id:
            other_user = obj.artisan
        else:
            other_user = obj.client

        if other_user.last_active:
            return other_user.last_active >= timezone.now() - timedelta(minutes=3)
        return False


class ConversationUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating conversation settings (TTL, active status)."""
    class Meta:
        model = Conversation
        fields = ['message_ttl_days', 'is_active']

    def validate_message_ttl_days(self, value):
        valid = [choice[0] for choice in Conversation.MESSAGE_TTL_CHOICES]
        if value not in valid:
            raise serializers.ValidationError(
                f"message_ttl_days must be one of {valid}"
            )
        return value


class ConversationCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating a conversation.

    SECURITY: The client field is always set to the requesting user
    by the view's perform_create method. It is not exposed as a writable
    field to prevent users from creating conversations on behalf of others.
    The artisan must be specified and must be an active artisan.
    Users cannot create conversations between arbitrary other users.
    """
    class Meta:
        model = Conversation
        fields = ['artisan', 'related_job']
        extra_kwargs = {
            'related_job': {'required': False},
        }

    def validate_artisan(self, value):
        """Ensure the artisan user is active and has the ARTISAN role."""
        if value.role != User.Role.ARTISAN:
            raise serializers.ValidationError("Selected user is not an artisan.")
        if not value.is_active:
            raise serializers.ValidationError("This artisan account is not active.")
        return value