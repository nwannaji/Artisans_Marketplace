from rest_framework import generics, permissions, exceptions, status
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Q
from .models import Conversation, Chat
from accounts.models import User
from accounts.permissions import IsAdminRole
from .serializers import (
    ChatSerializer, ConversationSerializer, ConversationCreateSerializer
)


class ConversationListCreateAPIView(generics.ListCreateAPIView):
    permission_classes = [permissions.IsAuthenticated]

    def get_serializer_class(self):
        if self.request.method == 'POST':
            return ConversationCreateSerializer
        return ConversationSerializer

    def get_queryset(self):
        user = self.request.user
        if user.role == User.Role.ADMIN:
            return Conversation.objects.all()
        return Conversation.objects.filter(Q(client=user) | Q(artisan=user))

    def perform_create(self, serializer):
        # SECURITY: Always set client to the requesting user — never trust client input
        serializer.save(conversation_type='client_artisan', client=self.request.user)

    def create(self, request, *args, **kwargs):
        """Override to return the full ConversationSerializer after creation."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        # Return full conversation data instead of just the create fields
        output_serializer = ConversationSerializer(serializer.instance)
        headers = self.get_success_headers(output_serializer.data)
        return Response(output_serializer.data, status=status.HTTP_201_CREATED, headers=headers)


class ConversationDetailAPIView(generics.RetrieveAPIView):
    queryset = Conversation.objects.all()
    serializer_class = ConversationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        conversation = super().get_object()
        user = self.request.user
        # Allow participants and admins to view
        if user.role != User.Role.ADMIN and user not in [conversation.client, conversation.artisan]:
            raise exceptions.PermissionDenied("You are not a participant in this conversation.")
        return conversation


class ChatListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = ChatSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    # SECURITY: Allowed audio MIME types and maximum file size for voice notes
    ALLOWED_AUDIO_TYPES = [
        'audio/mpeg', 'audio/mp4', 'audio/mp3', 'audio/ogg',
        'audio/webm', 'audio/aac', 'audio/amr', 'audio/wav',
        'audio/x-m4a', 'audio/m4a', 'audio/3gpp',
    ]
    MAX_AUDIO_SIZE = 10 * 1024 * 1024  # 10MB

    def get_queryset(self):
        conversation_id = self.kwargs.get('conversation_id')
        user = self.request.user
        conversation = Conversation.objects.get(pk=conversation_id)

        # Admin can see all messages in any conversation
        if user.role == User.Role.ADMIN:
            return Chat.objects.filter(conversation=conversation)

        # Non-admin can only see messages in their conversations
        if user not in [conversation.client, conversation.artisan]:
            raise exceptions.PermissionDenied("You are not a participant in this conversation.")
        return Chat.objects.filter(conversation=conversation)

    def list(self, request, *args, **kwargs):
        """Override list to also mark messages as read for the requesting user."""
        response = super().list(request, *args, **kwargs)
        # Mark all unread messages sent by the OTHER user as read
        conversation_id = self.kwargs.get('conversation_id')
        if conversation_id and request.user.is_authenticated:
            Chat.objects.filter(
                conversation_id=conversation_id,
                is_read=False,
            ).exclude(sender=request.user).update(is_read=True)
        return response

    def perform_create(self, serializer):
        user = self.request.user
        conversation_id = self.kwargs.get('conversation_id')
        conversation = Conversation.objects.get(pk=conversation_id)

        # Verify user is a participant or admin
        if user.role != User.Role.ADMIN and user not in [conversation.client, conversation.artisan]:
            raise exceptions.PermissionDenied("You are not a participant in this conversation.")

        is_admin = user.role == User.Role.ADMIN

        # Determine message type based on content
        audio_file = self.request.data.get('audio_file')
        latitude = self.request.data.get('latitude')

        if audio_file:
            message_type = 'voice_note'
        elif latitude is not None:
            message_type = 'location'
        else:
            message_type = 'text'

        # SECURITY: Validate audio file type and size
        if audio_file:
            if hasattr(audio_file, 'content_type') and audio_file.content_type not in self.ALLOWED_AUDIO_TYPES:
                raise exceptions.ValidationError(
                    f"Invalid audio file type '{audio_file.content_type}'. "
                    f"Allowed types: MP3, M4A, OGG, WebM, AAC, AMR, WAV."
                )
            if hasattr(audio_file, 'size') and audio_file.size > self.MAX_AUDIO_SIZE:
                raise exceptions.ValidationError(
                    f"Audio file too large ({audio_file.size // (1024*1024)}MB). Maximum size is 10MB."
                )

        # Parse audio_duration from request data
        audio_duration = None
        duration_str = self.request.data.get('audio_duration')
        if duration_str:
            try:
                audio_duration = float(duration_str)
                # SECURITY: Cap audio duration to reasonable limit (60 minutes)
                if audio_duration < 0 or audio_duration > 3600:
                    audio_duration = None
            except (ValueError, TypeError):
                pass

        # Parse location data
        lat = None
        lng = None
        location_label = ''
        if message_type == 'location':
            lat_str = self.request.data.get('latitude')
            lng_str = self.request.data.get('longitude')
            location_label = self.request.data.get('location_label', '')[:200]  # Limit label length
            if lat_str:
                try:
                    lat = float(lat_str)
                    if not (-90 <= lat <= 90):
                        raise exceptions.ValidationError("Latitude must be between -90 and 90.")
                except (ValueError, TypeError):
                    pass
            if lng_str:
                try:
                    lng = float(lng_str)
                    if not (-180 <= lng <= 180):
                        raise exceptions.ValidationError("Longitude must be between -180 and 180.")
                except (ValueError, TypeError):
                    pass

        serializer.save(
            sender=user,
            conversation=conversation,
            is_admin_message=is_admin,
            message_type=message_type,
            audio_duration=audio_duration,
            latitude=lat,
            longitude=lng,
            location_label=location_label,
        )


class AdminConversationListAPIView(generics.ListAPIView):
    """Admin can view all conversations."""
    serializer_class = ConversationSerializer
    permission_classes = [IsAdminRole]

    def get_queryset(self):
        return Conversation.objects.all()


class AdminChatAPIView(generics.CreateAPIView):
    """Admin can send messages in any conversation."""
    serializer_class = ChatSerializer
    permission_classes = [IsAdminRole]

    def perform_create(self, serializer):
        conversation_id = self.kwargs.get('conversation_id')
        conversation = Conversation.objects.get(pk=conversation_id)

        # If admin isn't already linked to this conversation, add them
        if conversation.admin is None:
            conversation.admin = self.request.user
            conversation.save()

        serializer.save(
            sender=self.request.user,
            conversation=conversation,
            is_admin_message=True
        )