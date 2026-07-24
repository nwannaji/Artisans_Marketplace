from django.urls import path

from . import views

app_name = 'subscriptions'

urlpatterns = [
    path('my/', views.MySubscriptionView.as_view(), name='my_subscription'),
    path('tiers/', views.TierListView.as_view(), name='tier_list'),
]