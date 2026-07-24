"""
ASGI config for artisans_backend project.

Handles both HTTP (via Django) and WebSocket (via Channels) protocols.
"""

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'artisans_backend.settings')

# Initialize Django ASGI application first so the ORM is ready
django_asgi_app = get_asgi_application()

from chats.middleware import JWTAuthMiddleware, NullOriginAllowedValidator
from chats.routing import websocket_urlpatterns

application = ProtocolTypeRouter({
    'http': django_asgi_app,
    'websocket': NullOriginAllowedValidator(
        JWTAuthMiddleware(
            URLRouter(websocket_urlpatterns)
        )
    ),
})