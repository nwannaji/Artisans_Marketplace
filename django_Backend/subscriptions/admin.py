from django.contrib import admin

from .models import Subscription


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ('artisan', 'tier', 'expires_at', 'is_active', 'activated_by', 'updated_at')
    list_filter = ('tier', 'expires_at')
    search_fields = ('artisan__user__username', 'artisan__user__email')
    readonly_fields = ('created_at', 'updated_at')
    raw_id_fields = ('artisan', 'activated_by')