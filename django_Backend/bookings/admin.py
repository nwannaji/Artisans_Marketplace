from django.contrib import admin
from .models import Job
from django.utils.html import format_html

class JobAdmin(admin.ModelAdmin):
    list_display = ('id', 'customer', 'artisan', 'scheduled_time', 'status_badge', 'agreed_price')
    list_filter = ('status', 'scheduled_time')
    search_fields = ('customer__username', 'artisan__user__username', 'description')
    readonly_fields = ('created_at', 'updated_at')
    date_hierarchy = 'scheduled_time'
    actions = ['mark_as_completed', 'mark_as_disputed']
    
    fieldsets = (
        ('Job Details', {
            'fields': ('customer', 'artisan', 'description', 'scheduled_time', 'agreed_price')
        }),
        ('Location', {
            'fields': ('location', 'latitude', 'longitude')
        }),
        ('Status', {
            'fields': ('status', 'rating', 'review')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )
    
    def status_badge(self, obj):
        color_map = {
            'scheduled': 'blue',
            'in_progress': 'orange',
            'completed': 'green',
            'cancelled': 'red',
            'disputed': 'purple',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.status, 'gray'),
            obj.get_status_display()
        )
    status_badge.short_description = 'Status'
    
    def mark_as_completed(self, request, queryset):
        queryset.update(status='completed')
    mark_as_completed.short_description = "Mark selected jobs as completed"
    
    def mark_as_disputed(self, request, queryset):
        queryset.update(status='disputed')
    mark_as_disputed.short_description = "Mark selected jobs as disputed"

admin.site.register(Job, JobAdmin)