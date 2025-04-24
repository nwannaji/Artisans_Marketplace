from django.contrib import admin
from .models import ArtisanProfile
from django.utils.html import format_html

class ArtisanProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'profession', 'location', 'hourly_rate', 'rating', 'is_verified', 'verification_status')
    list_filter = ('profession', 'is_verified')
    search_fields = ('user__username', 'user__email', 'profession', 'location')
    readonly_fields = ('rating', 'jobs_completed')
    actions = ['verify_artisans', 'unverify_artisans']
    
    fieldsets = (
        ('User Information', {
            'fields': ('user', 'profession', 'bio')
        }),
        ('Professional Details', {
            'fields': ('rating', 'jobs_completed', 'hourly_rate', 'skills')
        }),
        ('Location', {
            'fields': ('location', 'latitude', 'longitude')
        }),
        ('Bank Information', {
            'fields': ('bank_account', 'bank_name')
        }),
        ('Verification', {
            'fields': ('is_verified', 'verification_documents')
        }),
    )
    
    def verification_status(self, obj):
        if obj.is_verified:
            return format_html('<span style="color: green;">✓ Verified</span>')
        else:
            return format_html('<span style="color: red;">✗ Not Verified</span>')
    verification_status.short_description = 'Verification Status'
    
    def verify_artisans(self, request, queryset):
        queryset.update(is_verified=True)
    verify_artisans.short_description = "Verify selected artisans"
    
    def unverify_artisans(self, request, queryset):
        queryset.update(is_verified=False)
    unverify_artisans.short_description = "Unverify selected artisans"

admin.site.register(ArtisanProfile, ArtisanProfileAdmin)