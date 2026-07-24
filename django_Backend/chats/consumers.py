"""WebSocket consumer for real-time chat.

Protocol:
  Connect to: ws://host/ws/chat/?token=<access_token>

Incoming message types (client → server):
  {"type": "chat_message", "conversation_id": int, "message": str}
  {"type": "typing", "conversation_id": int}
  {"type": "read_receipt", "conversation_id": int}
  {"type": "join_conversation", "conversation_id": int}
  {"type": "leave_conversation", "conversation_id": int}
  {"type": "heartbeat"}

Outgoing message types (server → client):
  {"type": "chat_message", "data": {<serialized Chat message>}}
  {"type": "user_typing", "user_id": int, "username": str, "conversation_id": int}
  {"type": "messages_read", "conversation_id": int, "reader_id": int}
  {"type": "user_online", "user_id": int}
  {"type": "user_offline", "user_id": int}
  {"type": "heartbeat_ack"}
  {"type": "error", "message": str}
"""

import json
import logging
from datetime import timedelta

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth.models import AnonymousUser
from django.db.models import Q
from django.utils import timezone

logger = logging.getLogger(__name__)


class ChatConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real-time chat messaging."""

    async def connect(self):
        user = self.scope.get('user')
        if user is None or isinstance(user, AnonymousUser) or not user.is_authenticated:
            await self.close(code=4001)
            return

        self.user = user
        self.conversation_groups = set()
        self.user_group_name = f'user_{self.user.id}'

        # Join the user's personal group (for online status, direct updates)
        await self.channel_layer.group_add(self.user_group_name, self.channel_name)

        await self.accept()

        # Broadcast online status to all conversations the user belongs to
        await self._broadcast_online_status(is_online=True)

        # Update last_active timestamp
        await self._update_last_active()

        logger.info("WebSocket connected: user=%s (pk=%s)", self.user.username, self.user.pk)

    async def disconnect(self, close_code):
        if not hasattr(self, 'user'):
            return

        # Leave all conversation groups
        for group_name in list(self.conversation_groups):
            await self.channel_layer.group_discard(group_name, self.channel_name)

        # Leave personal group
        await self.channel_layer.group_discard(self.user_group_name, self.channel_name)

        # Broadcast offline status
        await self._broadcast_online_status(is_online=False)

        logger.info("WebSocket disconnected: user=%s (pk=%s)", self.user.username, self.user.pk)

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send(json.dumps({'type': 'error', 'message': 'Invalid JSON'}))
            return

        message_type = data.get('type')

        handlers = {
            'chat_message': self._handle_chat_message,
            'typing': self._handle_typing,
            'read_receipt': self._handle_read_receipt,
            'join_conversation': self._handle_join_conversation,
            'leave_conversation': self._handle_leave_conversation,
            'heartbeat': self._handle_heartbeat,
        }

        handler = handlers.get(message_type)
        if handler:
            await handler(data)
        else:
            await self.send(json.dumps({'type': 'error', 'message': f'Unknown type: {message_type}'}))

    # ── Message Handlers ──────────────────────────────────────

    async def _handle_chat_message(self, data):
        conversation_id = data.get('conversation_id')
        message_text = data.get('message', '').strip()

        if not conversation_id or not message_text:
            await self.send(json.dumps({'type': 'error', 'message': 'conversation_id and message required'}))
            return

        # Validate participation
        conversation = await self._get_conversation(conversation_id)
        if conversation is None:
            await self.send(json.dumps({'type': 'error', 'message': 'Conversation not found'}))
            return

        if not await self._is_participant(conversation, self.user):
            await self.send(json.dumps({'type': 'error', 'message': 'Not a participant'}))
            return

        # Validate message length
        if len(message_text) > 2000:
            await self.send(json.dumps({'type': 'error', 'message': 'Message too long (max 2000 chars)'}))
            return

        # Save message to database
        chat_msg = await self._save_message(
            conversation=conversation,
            sender=self.user,
            message=message_text,
        )

        # Serialize the message
        serialized = await self._serialize_message(chat_msg)

        # Broadcast to the conversation group
        group_name = f'conversation_{conversation_id}'
        await self.channel_layer.group_send(
            group_name,
            {
                'type': 'chat_message_event',
                'data': serialized,
            }
        )

    async def _handle_typing(self, data):
        conversation_id = data.get('conversation_id')
        if not conversation_id:
            return

        group_name = f'conversation_{conversation_id}'
        await self.channel_layer.group_send(
            group_name,
            {
                'type': 'typing_event',
                'user_id': self.user.id,
                'username': self.user.username,
                'conversation_id': conversation_id,
            }
        )

    async def _handle_read_receipt(self, data):
        conversation_id = data.get('conversation_id')
        if not conversation_id:
            return

        # Mark messages as read in DB
        await self._mark_messages_read(conversation_id)

        group_name = f'conversation_{conversation_id}'
        await self.channel_layer.group_send(
            group_name,
            {
                'type': 'messages_read_event',
                'conversation_id': conversation_id,
                'reader_id': self.user.id,
            }
        )

    async def _handle_join_conversation(self, data):
        conversation_id = data.get('conversation_id')
        if not conversation_id:
            return

        # Verify the user is a participant
        conversation = await self._get_conversation(conversation_id)
        if conversation is None or not await self._is_participant(conversation, self.user):
            await self.send(json.dumps({'type': 'error', 'message': 'Cannot join this conversation'}))
            return

        group_name = f'conversation_{conversation_id}'
        if group_name not in self.conversation_groups:
            await self.channel_layer.group_add(group_name, self.channel_name)
            self.conversation_groups.add(group_name)
            logger.info(
                "User %s joined conversation %s",
                self.user.username, conversation_id,
            )

    async def _handle_leave_conversation(self, data):
        conversation_id = data.get('conversation_id')
        if not conversation_id:
            return

        group_name = f'conversation_{conversation_id}'
        if group_name in self.conversation_groups:
            await self.channel_layer.group_discard(group_name, self.channel_name)
            self.conversation_groups.discard(group_name)

    async def _handle_heartbeat(self, data):
        await self.send(json.dumps({'type': 'heartbeat_ack'}))
        await self._update_last_active()

    # ── Group Event Handlers (called by channel layer) ────────

    async def chat_message_event(self, event):
        """Handler for chat_message events broadcast from the channel layer."""
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'data': event['data'],
        }))

    async def typing_event(self, event):
        """Handler for typing indicator events."""
        # Don't send typing indicator back to the user who is typing
        if event['user_id'] == self.user.id:
            return
        await self.send(text_data=json.dumps({
            'type': 'user_typing',
            'user_id': event['user_id'],
            'username': event['username'],
            'conversation_id': event['conversation_id'],
        }))

    async def messages_read_event(self, event):
        """Handler for read receipt events."""
        # Don't send read receipt back to the reader
        if event['reader_id'] == self.user.id:
            return
        await self.send(text_data=json.dumps({
            'type': 'messages_read',
            'conversation_id': event['conversation_id'],
            'reader_id': event['reader_id'],
        }))

    async def user_online_event(self, event):
        """Handler for online status events."""
        if event['user_id'] == self.user.id:
            return  # Don't echo own status back
        await self.send(text_data=json.dumps({
            'type': 'user_online',
            'user_id': event['user_id'],
        }))

    async def user_offline_event(self, event):
        """Handler for offline status events."""
        if event['user_id'] == self.user.id:
            return
        await self.send(text_data=json.dumps({
            'type': 'user_offline',
            'user_id': event['user_id'],
        }))

    # ── Database Helper Methods ────────────────────────────────

    @database_sync_to_async
    def _get_conversation(self, conversation_id):
        from .models import Conversation
        try:
            return Conversation.objects.get(id=conversation_id, is_active=True)
        except Conversation.DoesNotExist:
            return None

    @database_sync_to_async
    def _is_participant(self, conversation, user):
        from accounts.models import User
        return user in [conversation.client, conversation.artisan] or user.role == User.Role.ADMIN

    @database_sync_to_async
    def _save_message(self, conversation, sender, message):
        from .models import Chat
        return Chat.objects.create(
            conversation=conversation,
            sender=sender,
            message=message,
            is_admin_message=(sender.role == 'ADMIN'),
        )

    @database_sync_to_async
    def _serialize_message(self, chat_msg):
        from .serializers import ChatSerializer
        from rest_framework.test import APIRequestFactory
        factory = APIRequestFactory()
        request = factory.get('/')
        serializer = ChatSerializer(chat_msg, context={'request': request})
        return serializer.data

    @database_sync_to_async
    def _mark_messages_read(self, conversation_id):
        from .models import Chat
        return Chat.objects.filter(
            conversation_id=conversation_id,
            is_read=False,
        ).exclude(sender=self.user).update(is_read=True)

    @database_sync_to_async
    def _update_last_active(self):
        self.user.last_active = timezone.now()
        self.user.save(update_fields=['last_active'])

    async def _broadcast_online_status(self, is_online):
        """Broadcast online/offline status to all conversations the user is in."""
        conversation_ids = await self._get_user_conversation_ids()
        event_type = 'user_online_event' if is_online else 'user_offline_event'
        for conv_id in conversation_ids:
            group_name = f'conversation_{conv_id}'
            await self.channel_layer.group_send(
                group_name,
                {
                    'type': event_type,
                    'user_id': self.user.id,
                }
            )

    @database_sync_to_async
    def _get_user_conversation_ids(self):
        from .models import Conversation
        return list(Conversation.objects.filter(
            Q(client=self.user) | Q(artisan=self.user),
            is_active=True,
        ).values_list('id', flat=True))