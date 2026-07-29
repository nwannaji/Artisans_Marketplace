# serializers.py
import os
import time

from rest_framework import serializers
from accounts.models import ArtisanProfile
from .models_portfolio import PortfolioImage


def _cache_busted_url(field):
    """Return the URL for an ImageField with a cache-busting timestamp."""
    if not field:
        return None
    base_url = field.url
    try:
        mtime = os.path.getmtime(field.path)
        ts = int(mtime)
    except (OSError, ValueError):
        ts = int(time.time())
    sep = '&' if '?' in base_url else '?'
    return f'{base_url}{sep}t={ts}'


class PortfolioImageSerializer(serializers.ModelSerializer):
    class Meta:
        model = PortfolioImage
        fields = ['id', 'artisan', 'image', 'caption', 'order', 'uploaded_at']
        read_only_fields = ['artisan', 'uploaded_at']

    def validate_image(self, value):
        # Validate file type
        allowed_types = ['image/jpeg', 'image/png', 'image/webp']
        if value.content_type not in allowed_types:
            raise serializers.ValidationError(
                "Unsupported image type. Allowed types: JPG, JPEG, PNG, WEBP."
            )
        # Validate file size (max 5MB)
        max_size = 5 * 1024 * 1024  # 5MB
        if value.size > max_size:
            raise serializers.ValidationError(
                "Image file size must be under 5MB."
            )
        return value


class ArtisanProfileSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)
    review_count = serializers.SerializerMethodField()
    profile_picture = serializers.SerializerMethodField()

    class Meta:
        model = ArtisanProfile
        fields = [
            'id', 'user', 'user_username', 'user_is_active',
            'profession', 'skills', 'hourly_rate', 'rating', 'review_count',
            'jobs_completed', 'location', 'latitude', 'longitude',
            'profile_picture', 'bio', 'is_verified', 'is_available',
            'verification_documents', 'created_at', 'updated_at',
        ]
        read_only_fields = ('created_at', 'updated_at', 'user', 'is_verified')

    def get_review_count(self, obj):
        from reviews.models import Review
        return Review.objects.filter(artisan=obj).count()

    def get_profile_picture(self, obj):
        return _cache_busted_url(obj.profile_picture)

    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list.")
        return value

    def validate_verification_documents(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Verification documents must be a list.")
        return value
