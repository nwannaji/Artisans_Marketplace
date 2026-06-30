from django.urls import path
from .views import (
    PaystackPaymentCallbackView,
    WalletDetailAPIView, TransactionListCreateAPIView,
    TransactionUpdateAPIView, AppSettingsRetrieveUpdateAPIView,
    EscrowFundJobAPIView, EscrowReleaseJobAPIView,
    EscrowStatusAPIView, EscrowReleaseOtpAPIView,
    DepositAPIView,
    AdminEscrowListView, AdminEscrowReleaseAPIView, AdminEscrowRefundAPIView,
    PaystackWebhookView,
    PaystackTransferWebhookView,
    PandascrowWebhookView,
    BankAccountListCreateAPIView, BankAccountDetailAPIView, BankAccountVerifyAPIView,
    WithdrawalAPIView,
)

app_name = 'payments'

urlpatterns = [
    path('wallet/', WalletDetailAPIView.as_view(), name='wallet-detail'),
    path('transactions/', TransactionListCreateAPIView.as_view(), name='transaction-list-create'),
    path('transactions/<int:pk>/', TransactionUpdateAPIView.as_view(), name='transaction-update'),
    path('deposit/', DepositAPIView.as_view(), name='deposit'),
    path('withdraw/', WithdrawalAPIView.as_view(), name='withdraw'),
    path('settings/<str:key>/', AppSettingsRetrieveUpdateAPIView.as_view(), name='app-settings-update'),
    path('bank-accounts/', BankAccountListCreateAPIView.as_view(), name='bank-account-list-create'),
    path('bank-accounts/<int:pk>/', BankAccountDetailAPIView.as_view(), name='bank-account-detail'),
    path('bank-accounts/<int:pk>/verify/', BankAccountVerifyAPIView.as_view(), name='bank-account-verify'),
    path('paystack/callback/', PaystackPaymentCallbackView.as_view(), name='paystack-callback'),
    path('paystack/webhook/', PaystackWebhookView.as_view(), name='paystack-webhook'),
    path('paystack/transfer-webhook/', PaystackTransferWebhookView.as_view(), name='paystack-transfer-webhook'),
    path('pandascrow/webhook/', PandascrowWebhookView.as_view(), name='pandascrow-webhook'),
    path('escrow/<int:pk>/fund/', EscrowFundJobAPIView.as_view(), name='escrow-fund'),
    path('escrow/<int:pk>/release/', EscrowReleaseJobAPIView.as_view(), name='escrow-release'),
    path('escrow/<int:pk>/status/', EscrowStatusAPIView.as_view(), name='escrow-status'),
    path('escrow/<int:pk>/release/otp/', EscrowReleaseOtpAPIView.as_view(), name='escrow-release-otp'),
    path('admin/escrow/', AdminEscrowListView.as_view(), name='admin-escrow-list'),
    path('admin/escrow/<int:pk>/release/', AdminEscrowReleaseAPIView.as_view(), name='admin-escrow-release'),
    path('admin/escrow/<int:pk>/refund/', AdminEscrowRefundAPIView.as_view(), name='admin-escrow-refund'),
]