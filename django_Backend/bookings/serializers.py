from rest_framework import serializers
from .models import Job

class JobSerializer(serializers.ModelSerializer):
    customer_username = serializers.CharField(source='customer.username', read_only=True)
    artisan_username = serializers.CharField(source='artisan.user.username', read_only=True)

    class Meta:
        model = Job
        fields = '__all__'
        read_only_fields = ('status', 'rating', 'review', 'created_at', 'updated_at')
