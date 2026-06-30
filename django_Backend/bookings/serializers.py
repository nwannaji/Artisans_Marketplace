from rest_framework import serializers
from .models import Job


class JobSerializer(serializers.ModelSerializer):
    customer_username = serializers.CharField(source='customer.username', read_only=True)
    artisan_username = serializers.CharField(
        source='artisan.user.username', read_only=True, default=None, allow_null=True
    )

    class Meta:
        model = Job
        fields = [
            'id', 'customer', 'customer_username', 'artisan', 'artisan_username',
            'description', 'scheduled_time', 'agreed_price', 'location',
            'latitude', 'longitude', 'status', 'escrow_held_amount',
            'admin_approved_by', 'admin_approved_at',
            'rating', 'review', 'created_at', 'updated_at',
        ]
        read_only_fields = ('status', 'rating', 'review', 'created_at', 'updated_at',
                            'escrow_held_amount', 'admin_approved_by', 'admin_approved_at')


class JobCreateSerializer(serializers.ModelSerializer):
    """Serializer for clients creating a new job. Artisan is not required at creation."""
    customer_username = serializers.CharField(source='customer.username', read_only=True)

    class Meta:
        model = Job
        fields = ['description', 'scheduled_time', 'agreed_price', 'location',
                  'latitude', 'longitude', 'customer_username']
        read_only_fields = ('customer',)

    def create(self, validated_data):
        validated_data['customer'] = self.context['request'].user
        validated_data['status'] = Job.Status.PENDING
        return super().create(validated_data)


class ArtisanReviewSerializer(serializers.ModelSerializer):
    """Serializer for displaying individual reviews on an artisan's public profile."""
    customer_name = serializers.CharField(source='customer.get_full_name_or_username', read_only=True)

    class Meta:
        model = Job
        fields = ['id', 'customer_name', 'rating', 'review', 'description', 'created_at']


class JobRatingSerializer(serializers.Serializer):
    """Serializer for submitting a rating and optional review for a completed job."""
    rating = serializers.FloatField(min_value=1, max_value=5)
    review = serializers.CharField(required=False, allow_blank=True, max_length=1000)