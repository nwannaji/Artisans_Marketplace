"""WebSocket authentication middleware for Django Channels.

Provides JWT-based authentication for WebSocket connections (since the app
uses SimpleJWT, not session-based auth) and an origin validator that allows
mobile clients which don't send an Origin header.
"""

from channels.db import database_sync_to_async
from channels.security.websocket import WebsocketDenier
from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.tokens import AccessToken
from urllib.parse import urlparse

User = get_user_model()


class JWTAuthMiddleware:
    """Authenticate WebSocket connections via JWT access token.

    The token is passed as a query parameter: ws://host/ws/chat/?token=<access_token>

    This middleware populates scope['user'] with the authenticated user,
    or with AnonymousUser if authentication fails.
    """

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        scope = dict(scope)

        # Extract token from query string
        token = None
        query_string = scope.get('query_string', b'').decode('utf-8')
        for param in query_string.split('&'):
            if param.startswith('token='):
                token = param.split('=', 1)[1]
                break

        if token:
            user = await self._get_user(token)
            scope['user'] = user
        else:
            from django.contrib.auth.models import AnonymousUser
            scope['user'] = AnonymousUser()

        return await self.inner(scope, receive, send)

    @database_sync_to_async
    def _get_user(self, token_string):
        """Validate JWT token and return the user, or AnonymousUser on failure."""
        try:
            access_token = AccessToken(token_string)
            user_id = access_token['user_id']
            user = User.objects.get(id=user_id, is_active=True)
            return user
        except (TokenError, InvalidToken, User.DoesNotExist, KeyError):
            from django.contrib.auth.models import AnonymousUser
            return AnonymousUser()


class NullOriginAllowedValidator:
    """Like AllowedHostsOriginValidator but also allows connections with no
    Origin header (mobile apps don't send one).

    When an Origin header IS present, it must match ALLOWED_HOSTS.
    When Origin is absent, the connection is allowed (mobile client).
    """

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        # Extract Origin header from scope
        headers = dict(scope.get('headers', []))
        origin_value = None
        for name, value in headers.items():
            if name.decode('utf-8').lower() == 'origin':
                origin_value = value.decode('utf-8')
                break

        if origin_value is None:
            # No origin header — mobile app, allow through
            return await self.inner(scope, receive, send)

        # Validate origin against ALLOWED_HOSTS
        hostname = urlparse(origin_value).hostname
        allowed = settings.ALLOWED_HOSTS
        if '*' in allowed or hostname in allowed:
            return await self.inner(scope, receive, send)

        # Origin not allowed — reject
        denier = WebsocketDenier()
        return await denier(scope, receive, send)