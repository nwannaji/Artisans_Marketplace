from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, CustomerProfile, ArtisanProfile

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
    list_display = ('user', 'profession', 'is_verified', 'rating')
    list_filter = ('is_verified', 'profession')
    actions = ['verify_artisans', 'unverify_artisans']
    
    def verify_artisans(self, request, queryset):
        queryset.update(is_verified=True)
        # Activate user accounts
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