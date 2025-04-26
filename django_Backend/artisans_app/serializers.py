# serializers.py
from rest_framework import serializers
from .models import ArtisanProfile

class ArtisanProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = ArtisanProfile
        fields = '__all__'  # Or you can list fields manually
        read_only_fields = ('created_at', 'updated_at')  # VERY IMPORTANT

    # Optional: If you want, you can customize validation, like making sure 'skills' is always a list
    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list.")
        return value

    def validate_certificates(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Certificates must be a list.")
        return value

    def validate_verification_documents(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Verification documents must be a list.")
        return value
