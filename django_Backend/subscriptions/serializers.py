from rest_framework import serializers

from .models import Subscription
from .utils import TIER_INFO


class SubscriptionSerializer(serializers.ModelSerializer):
    """Serializer for artisan-facing subscription info (read-only)."""
    artisan_username = serializers.CharField(source='artisan.user.username', read_only=True)
    tier_display = serializers.CharField(source='get_tier_display', read_only=True)
    effective_tier = serializers.CharField(read_only=True)
    is_active = serializers.BooleanField(read_only=True)

    class Meta:
        model = Subscription
        fields = [
            'id', 'artisan', 'artisan_username', 'tier', 'tier_display',
            'effective_tier', 'is_active',
            'expires_at', 'activated_by', 'notes',
            'created_at', 'updated_at',
        ]
        read_only_fields = ('created_at', 'updated_at', 'activated_by')


class SubscriptionActivateSerializer(serializers.Serializer):
    """Serializer for admin activation of a subscription tier."""
    tier = serializers.ChoiceField(
        choices=[('PRO', 'Pro'), ('PREMIUM', 'Premium')],
        help_text="The tier to activate.",
    )
    duration_days = serializers.IntegerField(
        default=30,
        min_value=1,
        max_value=365,
        help_text="Number of days until the subscription expires (typically 30 for monthly).",
    )
    notes = serializers.CharField(
        required=False,
        allow_blank=True,
        help_text="Optional notes (payment reference, etc.).",
    )


class TierInfoSerializer(serializers.Serializer):
    """Public serializer for tier/plan information."""
    tier = serializers.CharField()
    name = serializers.CharField()
    monthly_price = serializers.CharField()
    features = serializers.ListField(child=serializers.CharField())
    max_bookings_per_month = serializers.IntegerField(allow_null=True)
    priority_search = serializers.BooleanField()
    badge = serializers.CharField(allow_null=True)


class MySubscriptionSerializer(serializers.Serializer):
    """Serializer for the current artisan's subscription status.

    Returns a default FREE subscription if no record exists.
    """
    tier = serializers.CharField()
    tier_display = serializers.CharField()
    effective_tier = serializers.CharField()
    is_active = serializers.BooleanField()
    expires_at = serializers.DateTimeField(allow_null=True)
    max_bookings_per_month = serializers.IntegerField(allow_null=True)
    current_month_bookings = serializers.IntegerField()

    @classmethod
    def default_free(cls, booking_count=0):
        """Return a default FREE subscription response."""
        return {
            'tier': 'FREE',
            'tier_display': 'Free',
            'effective_tier': 'FREE',
            'is_active': False,
            'expires_at': None,
            'max_bookings_per_month': 3,
            'current_month_bookings': booking_count,
        }