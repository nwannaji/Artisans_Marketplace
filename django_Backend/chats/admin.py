from django.contrib import admin
from .models import Conversation, Chat


class ChatInline(admin.TabularInline):
    model = Chat
    extra = 0
    readonly_fields = ('sender', 'message', 'is_admin_message', 'timestamp', 'is_read')
    fields = ('sender', 'message', 'is_admin_message', 'timestamp', 'is_read')
    can_delete = False


class ConversationAdmin(admin.ModelAdmin):
    list_display = ('id', 'client', 'artisan', 'admin', 'conversation_type', 'message_ttl_days', 'is_active', 'created_at')
    list_filter = ('conversation_type', 'is_active', 'message_ttl_days', 'created_at')
    search_fields = ('client__username', 'artisan__username')
    readonly_fields = ('created_at',)
    inlines = [ChatInline]


class ChatAdmin(admin.ModelAdmin):
    list_display = ('id', 'conversation', 'sender', 'message_preview', 'is_admin_message', 'timestamp', 'is_read')
    list_filter = ('is_admin_message', 'is_read', 'timestamp')
    search_fields = ('sender__username', 'message')
    readonly_fields = ('timestamp',)

    def message_preview(self, obj):
        return obj.message[:50] + '...' if len(obj.message) > 50 else obj.message
    message_preview.short_description = 'Message'


admin.site.register(Conversation, ConversationAdmin)
admin.site.register(Chat, ChatAdmin)