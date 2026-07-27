from django.utils import timezone


class UpdateLastActiveMiddleware:
    """Update user.last_active on authenticated requests.

    A user is considered "online" if their last_active timestamp is
    within the last 3 minutes. This middleware updates that timestamp
    only when the existing value is stale (older than 2 minutes),
    reducing database writes from one-per-request to roughly one
    per 2 minutes per active user.
    """

    # Minimum seconds between last_active updates to avoid excessive DB writes
    UPDATE_INTERVAL_SECONDS = 120  # 2 minutes

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated:
            now = timezone.now()
            last_active = request.user.last_active

            # Only write to DB if last_active is stale or has never been set
            if (
                last_active is None
                or (now - last_active).total_seconds() >= self.UPDATE_INTERVAL_SECONDS
            ):
                request.user.last_active = now
                request.user.save(update_fields=['last_active'])

        return self.get_response(request)