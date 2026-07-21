from rest_framework import serializers
from .models import Dispute, EvidenceFile
from bookings.models import Job
from accounts.models import User

class DisputeSerializer(serializers.ModelSerializer):
    job_id = serializers.PrimaryKeyRelatedField(queryset=Job.objects.all(), source='job')

    class Meta:
        model = Dispute
        fields = ['id', 'job_id', 'reason', 'details', 'status', 'resolution', 'resolved_by', 'created_at', 'resolved_at']
        read_only_fields = ['status', 'resolution', 'resolved_by', 'resolved_at']

    def create(self, validated_data):
        # Only job_id, reason, and details should be set during creation.
        # Status, resolution, etc. are managed by the admin resolve endpoint.
        return Dispute.objects.create(**validated_data)


class EvidenceFileSerializer(serializers.ModelSerializer):
    """Serializer for dispute evidence file uploads."""
    uploaded_by_username = serializers.CharField(source='uploaded_by.username', read_only=True)
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = EvidenceFile
        fields = ['id', 'dispute', 'file', 'file_url', 'caption', 'file_type', 'uploaded_by', 'uploaded_by_username', 'created_at']
        read_only_fields = ['dispute', 'uploaded_by', 'file_type', 'created_at']

    def get_file_url(self, obj):
        request = self.context.get('request')
        if obj.file:
            url = obj.file.url
            if request:
                return request.build_absolute_uri(url)
            return url
        return None

    def validate_file(self, value):
        # Validate file size (max 10MB)
        max_size = 10 * 1024 * 1024  # 10MB
        if value.size > max_size:
            raise serializers.ValidationError(
                f"File too large ({value.size // (1024*1024)}MB). Maximum size is 10MB."
            )

        # Validate file extension
        allowed_extensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf', 'doc', 'docx']
        file_ext = value.name.rsplit('.', 1)[-1].lower() if '.' in value.name else ''
        if file_ext not in allowed_extensions:
            raise serializers.ValidationError(
                f"Invalid file type '.{file_ext}'. Allowed: JPG, PNG, WebP, GIF, PDF, DOC, DOCX."
            )

        # Validate content type
        allowed_content_types = [
            'image/jpeg', 'image/png', 'image/webp', 'image/gif',
            'application/pdf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/octet-stream',  # Mobile clients often send this
        ]
        if value.content_type and value.content_type not in allowed_content_types:
            raise serializers.ValidationError(
                f"Invalid content type '{value.content_type}'."
            )

        return value