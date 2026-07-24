"""WebSocket URL routing for the chats app.

A single endpoint /ws/chat/ handles all chat WebSocket connections.
The client sends join_conversation / leave_conversation messages to
subscribe to specific conversation rooms.
"""

from django.urls import path
from . import consumers

websocket_urlpatterns = [
    path('ws/chat/', consumers.ChatConsumer.as_asgi()),
]