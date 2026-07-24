from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import ArtisanProfile
from accounts.permissions import IsAdminRole
from .models import Subscription
from .serializers import MySubscriptionSerializer, SubscriptionActivateSerializer, TierInfoSerializer
from .utils import TIER_INFO, PAYMENT_INFO, get_current_month_booking_count, get_effective_tier, get_monthly_booking_limit


class MySubscriptionView(APIView):
    """Get the current artisan's subscription status.

    Returns a default FREE response if no subscription record exists.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role != user.Role.ARTISAN:
            return Response(
                {'detail': 'Only artisans have subscriptions.'},
                status=403,
            )

        try:
            artisan_profile = user.artisanprofile
        except ArtisanProfile.DoesNotExist:
            return Response(
                {'detail': 'Artisan profile not found.'},
                status=404,
            )

        try:
            sub = artisan_profile.subscription
            effective_tier = sub.effective_tier
            booking_count = get_current_month_booking_count(artisan_profile)

            data = {
                'tier': sub.tier,
                'tier_display': sub.get_tier_display(),
                'effective_tier': effective_tier,
                'is_active': sub.is_active,
                'expires_at': sub.expires_at,
                'max_bookings_per_month': get_monthly_booking_limit(effective_tier),
                'current_month_bookings': booking_count,
            }
        except Subscription.DoesNotExist:
            booking_count = get_current_month_booking_count(artisan_profile)
            data = MySubscriptionSerializer.default_free(booking_count)

        return Response(data)


class TierListView(APIView):
    """Public endpoint returning available subscription tiers, features, and payment info.

    All data is served from the backend so the Flutter app never hardcodes
    prices, features, or bank details — update TIER_INFO / PAYMENT_INFO in
    utils.py and every client sees the change immediately.
    """
    permission_classes = [AllowAny]

    def get(self, request, *args, **kwargs):
        serializer = TierInfoSerializer(TIER_INFO, many=True)
        return Response({
            'tiers': serializer.data,
            'payment_info': PAYMENT_INFO,
        })