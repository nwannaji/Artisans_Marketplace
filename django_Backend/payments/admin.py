from datetime import timezone
from django.contrib import admin
from .models import AppSettings, Wallet, Transaction
from django.utils.html import format_html

class TransactionInline(admin.TabularInline):
    model = Transaction
    extra = 0
    readonly_fields = ('created_at',)
    fields = ('transaction_type', 'amount', 'status', 'reference', 'created_at')
    can_delete = False

class WalletAdmin(admin.ModelAdmin):
    list_display = ('user', 'balance_display', 'transaction_count')
    search_fields = ('user__username', 'user__email')
    readonly_fields = ('created_at', 'updated_at')
    inlines = [TransactionInline]
    
    def balance_display(self, obj):
        return f"${obj.balance}"
    balance_display.short_description = 'Balance'
    
    def transaction_count(self, obj):
        return obj.transactions.count()
    transaction_count.short_description = 'Transactions'

class TransactionAdmin(admin.ModelAdmin):
    list_display = ('id', 'wallet', 'type_badge', 'amount_display', 'status_badge', 'created_at')
    list_filter = ('transaction_type', 'status', 'created_at')
    search_fields = ('wallet__user__username', 'reference', 'description')
    readonly_fields = ('created_at',)
    date_hierarchy = 'created_at'
    
    def amount_display(self, obj):
        return f"${obj.amount}"
    amount_display.short_description = 'Amount'
    
    def type_badge(self, obj):
        color_map = {
            'deposit': 'green',
            'withdrawal': 'blue',
            'payment': 'purple',
            'commission': 'orange',
            'refund': 'red',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.transaction_type, 'gray'),
            obj.get_transaction_type_display()
        )
    type_badge.short_description = 'Type'
    
    def status_badge(self, obj):
        color_map = {
            'pending': 'orange',
            'completed': 'green',
            'failed': 'red',
        }
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
            color_map.get(obj.status, 'gray'),
            obj.get_status_display()
        )
    status_badge.short_description = 'Status'

# class WithdrawalRequestAdmin(admin.ModelAdmin):
#     list_display = ('id', 'wallet', 'amount_display', 'status_badge', 'created_at')
#     list_filter = ('status', 'created_at')
#     search_fields = ('wallet__user__username', 'bank_account', 'bank_name')
#     readonly_fields = ('created_at',)
#     actions = ['approve_requests', 'reject_requests', 'mark_as_processed']
#     date_hierarchy = 'created_at'
    
#     def amount_display(self, obj):
#         return f"${obj.amount}"
#     amount_display.short_description = 'Amount'
    
#     def status_badge(self, obj):
#         color_map = {
#             'pending': 'orange',
#             'approved': 'blue',
#             'rejected': 'red',
#             'processed': 'green',
#         }
#         return format_html(
#             '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 10px;">{}</span>',
#             color_map.get(obj.status, 'gray'),
#             obj.get_status_display()
#         )
#     status_badge.short_description = 'Status'
    
#     def approve_requests(self, request, queryset):
#         queryset.update(status='approved')
#     approve_requests.short_description = "Approve selected requests"
    
#     def reject_requests(self, request, queryset):
#         queryset.update(status='rejected')
#     reject_requests.short_description = "Reject selected requests"
    
#     def mark_as_processed(self, request, queryset):
#         queryset.update(status='processed', processed_at=timezone.now())
#     mark_as_processed.short_description = "Mark as processed"

class AppSettingsAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        # Only allow one settings instance
        return not AppSettings.objects.exists()

admin.site.register(Wallet, WalletAdmin)
admin.site.register(Transaction, TransactionAdmin)
# admin.site.register(Transaction, WithdrawalRequestAdmin)
admin.site.register(AppSettings, AppSettingsAdmin)