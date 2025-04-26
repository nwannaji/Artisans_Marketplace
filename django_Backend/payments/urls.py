from django.urls import path
from .views import PaystackPaymentCallbackView, PaystackPaymentView, WalletDetailAPIView, TransactionListCreateAPIView, TransactionUpdateAPIView, AppSettingsRetrieveUpdateAPIView

urlpatterns = [
    path('wallet/', WalletDetailAPIView.as_view(), name='wallet-detail'),
    path('transactions/', TransactionListCreateAPIView.as_view(), name='transaction-list-create'),
    path('transactions/<int:pk>/', TransactionUpdateAPIView.as_view(), name='transaction-update'),
    path('settings/<str:key>/', AppSettingsRetrieveUpdateAPIView.as_view(), name='app-settings-update'),
    path('paystack/payment/', PaystackPaymentView.as_view(), name='paystack-payment'),
    path('paystack/callback/', PaystackPaymentCallbackView.as_view(), name='paystack-callback'),
]
