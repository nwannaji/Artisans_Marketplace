from rest_framework import serializers
from .models import Dispute
from bookings.models import Job
from accounts.models import User

class DisputeSerializer(serializers.ModelSerializer):
    job_id = serializers.PrimaryKeyRelatedField(queryset=Job.objects.all(), source='job')
    resolved_by_id = serializers.PrimaryKeyRelatedField(queryset=User.objects.all(), source='resolved_by', required=False)

    class Meta:
        model = Dispute
        fields = ['job_id', 'reason', 'details', 'status', 'resolution', 'resolution_amount', 'resolved_by_id', 'created_at', 'resolved_at']

    def create(self, validated_data):
        # You can add any logic needed during creation if necessary.
        return Dispute.objects.create(**validated_data)

    def update(self, instance, validated_data):
        # You can customize the update logic if needed.
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        return instance
