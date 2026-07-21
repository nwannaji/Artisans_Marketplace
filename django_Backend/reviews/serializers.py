from rest_framework import serializers

from .models import Review


class ReviewSerializer(serializers.ModelSerializer):
    """Read serializer for Review objects."""
    customer_name = serializers.CharField(
        source='customer.get_full_name_or_username', read_only=True
    )
    has_job_context = serializers.SerializerMethodField()
    job_description = serializers.SerializerMethodField()

    class Meta:
        model = Review
        fields = [
            'id', 'artisan', 'customer', 'customer_name',
            'rating', 'comment', 'job',
            'has_job_context', 'job_description',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['customer', 'created_at', 'updated_at']

    def get_has_job_context(self, obj):
        return obj.job_id is not None

    def get_job_description(self, obj):
        if obj.job:
            return obj.job.description
        return None


class ReviewCreateSerializer(serializers.Serializer):
    """Input serializer for creating a review from the artisan profile page."""
    rating = serializers.FloatField(min_value=1, max_value=5)
    comment = serializers.CharField(required=False, allow_blank=True, max_length=2000)


class ReviewUpdateSerializer(serializers.Serializer):
    """Input serializer for updating an existing review."""
    rating = serializers.FloatField(min_value=1, max_value=5, required=False)
    comment = serializers.CharField(required=False, allow_blank=True, max_length=2000)