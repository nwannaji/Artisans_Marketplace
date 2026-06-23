from django.contrib import admin
from .models import Job
from django.utils.html import format_html


class JobAdmin(admin.ModelAdmin):
    list_display = ('id', 'customer', 'artisan', 'scheduled_time', 'status_badge', 'agreed_price', 'escrow_held_amount')
    list_filter = ('status', 'scheduled_time')
    search_fields = ('customer__username', 'artisan__user__username', 'description')
    readonly_fields = ('created_at', 'updated_at', 'admin_approved_at')
    date_hierarchy = 'scheduled_time'
    actions = ['mark_as_completed', 'mark_as_disputed', 'approve_jobs']

    fieldsets = (
        ('Job Details', {
            'fields': ('customer', 'artisan', 'description', 'scheduled_time', 'agreed_price')
        }),
        ('Location', {
            'fields': ('location', 'latitude', 'longitude')
        }),
        ('Status & Approval', {
            'fields': ('status', 'admin_approved_by', 'admin_approved_at', 'rating', 'review')
        }),
        ('Escrow', {
            'fields': ('escrow_held_amount',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )

    def status_badge(self, obj):
        color_map = {
            'PENDING': 'gray',
            'ADMIN_APPROVED': 'blue',
            'ACCEPTED': 'teal',
            'IN_PROGRESS': 'orange',
            'COMPLETED': 'green',
            'CANCELLED': 'red',
            'DISPUTED': 'purple',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.status, 'gray'),
            obj.get_status_display()
        )
    status_badge.short_description = 'Status'

    def mark_as_completed(self, request, queryset):
        queryset.update(status=Job.Status.COMPLETED)
    mark_as_completed.short_description = "Mark selected jobs as completed"

    def mark_as_disputed(self, request, queryset):
        queryset.update(status=Job.Status.DISPUTED)
    mark_as_disputed.short_description = "Mark selected jobs as disputed"

    def approve_jobs(self, request, queryset):
        from django.utils import timezone
        queryset.filter(status=Job.Status.PENDING).update(
            status=Job.Status.ADMIN_APPROVED,
            admin_approved_by=request.user,
            admin_approved_at=timezone.now()
        )
    approve_jobs.short_description = "Approve selected pending jobs"


admin.site.register(Job, JobAdmin)