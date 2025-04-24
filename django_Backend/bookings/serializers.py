from rest_framework import serializers
from .models import Job
from artisans_app.models import ArtisanProfile

class JobSerializer(serializers.ModelSerializer):
    artisan_name = serializers.CharField(source='artisan.user.get_full_name', read_only=True)
    
    class Meta:
        model = Job
        fields = '__all__'
        read_only_fields = ['customer', 'created_at', 'updated_at']

class JobCreateSerializer(serializers.ModelSerializer):
    artisan_id = serializers.PrimaryKeyRelatedField(
        queryset=ArtisanProfile.objects.filter(user__is_active=True, is_verified=True),
        source='artisan'
    )
    
    class Meta:
        model = Job
        exclude = ['customer', 'status', 'rating', 'review']