from django.contrib import admin
from .models import Dispute
from django.utils.html import format_html
from django.utils import timezone

class DisputeAdmin(admin.ModelAdmin):
    list_display = ('id', 'job_link', 'reason_badge', 'status_badge', 'created_at')
    list_filter = ('status', 'reason', 'created_at')
    search_fields = ('job__customer__username', 'job__artisan__user__username', 'details')
    readonly_fields = ('created_at', 'resolved_at')
    actions = ['mark_as_resolved', 'mark_as_closed']
    date_hierarchy = 'created_at'
    
    fieldsets = (
        ('Dispute Details', {
            'fields': ('job', 'reason', 'details')
        }),
        ('Resolution', {
            'fields': ('status', 'resolution', 'resolved_by')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'resolved_at')
        }),
    )
    
    def job_link(self, obj):
        return format_html(
            '<a href="/admin/bookings/job/{}/change/">Job #{}</a>',
            obj.job.id,
            obj.job.id
        )
    job_link.short_description = 'Job'
    
    def reason_badge(self, obj):
        color_map = {
            'poor_service': 'orange',
            'not_completed': 'red',
            'over_charging': 'purple',
            'other': 'gray',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.reason, 'gray'),
            obj.get_reason_display()
        )
    reason_badge.short_description = 'Reason'
    
    def status_badge(self, obj):
        color_map = {
            'open': 'red',
            'in_review': 'orange',
            'resolved': 'blue',
            'closed': 'green',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.status, 'gray'),
            obj.get_status_display()
        )
    status_badge.short_description = 'Status'
    
    def mark_as_resolved(self, request, queryset):
        queryset.update(status='resolved', resolved_by=request.user, resolved_at=timezone.now())
    mark_as_resolved.short_description = "Mark as resolved"
    
    def mark_as_closed(self, request, queryset):
        queryset.update(status='closed')
    mark_as_closed.short_description = "Mark as closed"
    
    def save_model(self, request, obj, form, change):
        if 'status' in form.changed_data and obj.status == 'resolved' and not obj.resolved_at:
            obj.resolved_by = request.user
            obj.resolved_at = timezone.now()
        super().save_model(request, obj, form, change)

admin.site.register(Dispute, DisputeAdmin)