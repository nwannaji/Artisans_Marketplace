from django.db import models
from accounts.models import User


class Conversation(models.Model):
    """Groups messages between participants. Admin can be an optional participant for mediation."""
    CONVERSATION_TYPES = (
        ('client_artisan', 'Client-Artisan'),
        ('admin_client', 'Admin-Client'),
        ('admin_artisan', 'Admin-Artisan'),
    )

    client = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='client_conversations'
    )
    artisan = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='artisan_conversations'
    )
    admin = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='admin_conversations'
    )
    related_job = models.ForeignKey(
        'bookings.Job', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='conversations'
    )
    conversation_type = models.CharField(
        max_length=20, choices=CONVERSATION_TYPES, default='client_artisan'
    )
    is_active = models.BooleanField(default=True)
    MESSAGE_TTL_CHOICES = [
        (0, 'Never expire'),
        (7, '1 week'),
        (14, '2 weeks'),
        (30, '1 month'),
    ]
    message_ttl_days = models.PositiveSmallIntegerField(
        default=14,
        choices=MESSAGE_TTL_CHOICES,
        help_text='Days to retain messages. 0 = never auto-delete.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['client', 'is_active'], name='idx_conv_client_active'),
            models.Index(fields=['artisan', 'is_active'], name='idx_conv_artisan_active'),
        ]

    def __str__(self):
        return f"Conversation {self.id}: {self.client.username} & {self.artisan.username}"


class Chat(models.Model):
    """Individual messages within a conversation."""
    MESSAGE_TYPES = (
        ('text', 'Text'),
        ('voice_note', 'Voice Note'),
        ('location', 'Location'),
    )

    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name='messages'
    )
    sender = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='sent_messages'
    )
    message = models.TextField(blank=True, default='')
    message_type = models.CharField(
        max_length=20, choices=MESSAGE_TYPES, default='text'
    )
    audio_file = models.FileField(
        upload_to='chat_audio/', blank=True, null=True
    )
    audio_duration = models.FloatField(
        blank=True, null=True, help_text='Duration in seconds'
    )
    latitude = models.FloatField(blank=True, null=True)
    longitude = models.FloatField(blank=True, null=True)
    location_label = models.CharField(max_length=255, blank=True, default='')
    is_admin_message = models.BooleanField(default=False)
    timestamp = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False, db_index=True)

    class Meta:
        ordering = ['timestamp']
        indexes = [
            models.Index(fields=['conversation', 'is_read'], name='idx_chat_conv_read'),
            models.Index(fields=['conversation', 'timestamp'], name='idx_chat_conv_timestamp'),
        ]

    def __str__(self):
        if self.message_type == 'voice_note':
            return f"Voice note from {self.sender.username} in Conversation {self.conversation.id}"
        if self.message_type == 'location':
            return f"Location from {self.sender.username} in Conversation {self.conversation.id}"
        return f"Message from {self.sender.username} in Conversation {self.conversation.id}"