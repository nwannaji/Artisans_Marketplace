from django.db.models import Case, IntegerField, Q, Value, When
from django.utils import timezone

from bookings.models import Job
from .models import Subscription


def get_effective_tier(artisan_profile):
    """Return the effective subscription tier for an artisan.

    If the artisan has no Subscription record, they default to FREE.
    If their subscription has expired, they revert to FREE.
    """
    try:
        sub = artisan_profile.subscription
    except Subscription.DoesNotExist:
        return Subscription.Tier.FREE
    return sub.effective_tier


def get_monthly_booking_limit(tier):
    """Return the max bookings per calendar month for a tier.

    Returns None for unlimited (Pro/Premium).
    """
    limits = {
        Subscription.Tier.FREE: 3,
        Subscription.Tier.PRO: None,
        Subscription.Tier.PREMIUM: None,
    }
    return limits.get(tier, 3)


def get_current_month_booking_count(artisan_profile):
    """Count bookings created this calendar month for the given artisan."""
    now = timezone.now()
    return Job.objects.filter(
        artisan=artisan_profile,
        created_at__year=now.year,
        created_at__month=now.month,
    ).count()


def annotate_tier_priority(queryset):
    """Annotate an ArtisanProfile queryset with tier_priority for ordering.

    Premium artisans get priority 0, Pro get 1, Free/default get 2.
    Only boosts artisans whose subscription is currently active (not expired).
    Uses a LEFT OUTER JOIN via the OneToOneField — artisans without a
    subscription record default to priority 2 (Free).
    """
    now = timezone.now()
    return queryset.annotate(
        tier_priority=Case(
            When(
                subscription__tier='PREMIUM',
                condition=Q(subscription__expires_at__isnull=True) | Q(subscription__expires_at__gt=now),
                then=Value(0),
            ),
            When(
                subscription__tier='PRO',
                condition=Q(subscription__expires_at__isnull=True) | Q(subscription__expires_at__gt=now),
                then=Value(1),
            ),
            default=Value(2),
            output_field=IntegerField(),
        )
    )


# Tier info for the public API endpoint.
# Centralised here so you update prices, features, and payment details
# in ONE place — no app release needed for changes.
TIER_INFO = [
    {
        'tier': 'FREE',
        'name': 'Free',
        'monthly_price': '₦0',
        'features': [
            'Basic artisan profile',
            'Up to 3 bookings per month',
            'Standard search visibility',
            'Customer messaging',
        ],
        'max_bookings_per_month': 3,
        'priority_search': False,
        'badge': None,
    },
    {
        'tier': 'PRO',
        'name': 'Pro',
        'monthly_price': '₦2,500',
        'features': [
            'Unlimited bookings',
            'Priority search results',
            'Pro badge on profile',
            'Customer messaging',
        ],
        'max_bookings_per_month': None,
        'priority_search': True,
        'badge': 'Pro',
    },
    {
        'tier': 'PREMIUM',
        'name': 'Premium',
        'monthly_price': '₦5,000',
        'features': [
            'Unlimited bookings',
            'Top search placement',
            'Premium badge on profile',
            'Featured placement',
            'Analytics dashboard',
            'Customer messaging',
        ],
        'max_bookings_per_month': None,
        'priority_search': True,
        'badge': 'Premium',
    },
]

# Payment/contact info returned by the /tiers/ endpoint.
# Update these values when your real bank details and contact info are ready.
PAYMENT_INFO = {
    'bank_name': 'Wema Bank',
    'account_number': '0123456789',
    'account_name': 'Kaycollin Services',
    'whatsapp_number': '2348000000000',
    'phone_number': '+2348000000000',
    'whatsapp_message': 'Hi, I want to upgrade my FixIt plan',
}