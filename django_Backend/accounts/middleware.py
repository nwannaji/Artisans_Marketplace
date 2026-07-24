from django.utils import timezone


class UpdateLastActiveMiddleware:
    """Update user.last_active on every authenticated request.

    A user is considered "online" if their last_active timestamp is
    within the last 3 minutes. This middleware updates that timestamp
    on each request so the online status stays current.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated:
            request.user.last_active = timezone.now()
            request.user.save(update_fields=['last_active'])
        return self.get_response(request)