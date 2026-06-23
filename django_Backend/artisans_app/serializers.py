# serializers.py
from rest_framework import serializers
from accounts.models import ArtisanProfile
from bookings.models import Job


class ArtisanProfileSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)
    review_count = serializers.SerializerMethodField()

    class Meta:
        model = ArtisanProfile
        fields = '__all__'
        read_only_fields = ('created_at', 'updated_at', 'user', 'is_verified')

    def get_review_count(self, obj):
        return Job.objects.filter(
            artisan=obj,
            status=Job.Status.COMPLETED,
            rating__isnull=False,
        ).count()

    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list.")
        return value

    def validate_verification_documents(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Verification documents must be a list.")
        return value
