from django.urls import path
from . import views

app_name = 'admin_dashboard'

urlpatterns = [
    # Auth
    path('', views.dashboard_overview, name='overview'),
    path('login/', views.dashboard_login, name='login'),
    path('logout/', views.dashboard_logout, name='logout'),

    # Users
    path('users/', views.user_list, name='user_list'),
    path('users/<int:pk>/', views.user_detail, name='user_detail'),
    path('users/<int:pk>/edit/', views.user_edit, name='user_edit'),
    path('users/<int:pk>/delete/', views.user_delete, name='user_delete'),
    path('users/<int:pk>/toggle-active/', views.user_toggle_active, name='user_toggle_active'),

    # Artisans
    path('artisans/', views.artisan_list, name='artisan_list'),
    path('artisans/<int:pk>/', views.artisan_detail, name='artisan_detail'),
    path('artisans/<int:pk>/edit/', views.artisan_edit, name='artisan_edit'),
    path('artisans/<int:pk>/delete/', views.artisan_delete, name='artisan_delete'),
    path('artisans/<int:pk>/toggle-verified/', views.artisan_toggle_verified, name='artisan_toggle_verified'),

    # Jobs
    path('jobs/', views.job_list, name='job_list'),
    path('jobs/<int:pk>/', views.job_detail, name='job_detail'),
    path('jobs/<int:pk>/approve/', views.job_approve, name='job_approve'),
    path('jobs/<int:pk>/reject/', views.job_reject, name='job_reject'),

    # Disputes
    path('disputes/', views.dispute_list, name='dispute_list'),
    path('disputes/<int:pk>/', views.dispute_detail, name='dispute_detail'),
    path('disputes/<int:pk>/resolve/', views.dispute_resolve, name='dispute_resolve'),

    # Chats
    path('chats/', views.conversation_list, name='conversation_list'),
    path('chats/<int:pk>/', views.conversation_detail, name='conversation_detail'),
    path('chats/<int:conversation_id>/send/', views.admin_send_message, name='admin_send_message'),

    # Subscriptions
    path('subscriptions/', views.subscription_list, name='subscription_list'),
    path('subscriptions/create/', views.subscription_create, name='subscription_create'),
    path('subscriptions/<int:pk>/activate/', views.subscription_activate, name='subscription_activate'),
    path('subscriptions/<int:pk>/deactivate/', views.subscription_deactivate, name='subscription_deactivate'),

]