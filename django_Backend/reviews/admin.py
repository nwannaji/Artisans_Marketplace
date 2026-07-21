from django.contrib import admin
from .models import Review


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ('id', 'artisan', 'customer', 'rating', 'created_at')
    list_filter = ('rating', 'created_at')
    search_fields = ('customer__username', 'artisan__user__username', 'comment')
    raw_id_fields = ('artisan', 'customer', 'job')