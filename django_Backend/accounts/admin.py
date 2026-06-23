from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, CustomerProfile, ArtisanProfile
from django.utils.html import format_html


class CustomUserAdmin(UserAdmin):
    list_display = ('username', 'email', 'role', 'is_active', 'is_staff')
    list_filter = ('role', 'is_active', 'is_staff', 'is_superuser')
    actions = ['activate_users', 'deactivate_users']

    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        ('Personal Info', {'fields': ('first_name', 'last_name', 'email', 'phone_number')}),
        ('Permissions', {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'role', 'groups', 'user_permissions'),
        }),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )

    def activate_users(self, request, queryset):
        queryset.update(is_active=True)
    activate_users.short_description = "Activate selected users"

    def deactivate_users(self, request, queryset):
        queryset.update(is_active=False)
    deactivate_users.short_description = "Deactivate selected users"


admin.site.register(User, CustomUserAdmin)


@admin.register(ArtisanProfile)
class ArtisanProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'profession', 'location', 'hourly_rate', 'rating', 'is_verified', 'verification_status')
    list_filter = ('is_verified', 'profession')
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
        # Also activate the user accounts
        User.objects.filter(
            id__in=queryset.values_list('user_id', flat=True)
        ).update(is_active=True)
    verify_artisans.short_description = "Verify selected artisans"

    def unverify_artisans(self, request, queryset):
        queryset.update(is_verified=False)
    unverify_artisans.short_description = "Unverify selected artisans"


@admin.register(CustomerProfile)
class CustomerProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'created_at')