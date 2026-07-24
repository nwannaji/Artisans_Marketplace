from django.urls import path
from .views import (
    ConversationListCreateAPIView,
    ConversationDetailAPIView,
    ChatListCreateAPIView,
    MessageDeleteAPIView,
    AdminConversationListAPIView,
    AdminChatAPIView
)
app_name = 'chats'

urlpatterns = [
    path('conversations/', ConversationListCreateAPIView.as_view(), name='conversation-list-create'),
    path('conversations/<int:pk>/', ConversationDetailAPIView.as_view(), name='conversation-detail'),
    path('conversations/<int:conversation_id>/messages/', ChatListCreateAPIView.as_view(), name='chat-list-create'),
    path('conversations/<int:conversation_id>/messages/<int:pk>/', MessageDeleteAPIView.as_view(), name='message-delete'),
    path('admin/conversations/', AdminConversationListAPIView.as_view(), name='admin-conversation-list'),
    path('admin/conversations/<int:conversation_id>/messages/', AdminChatAPIView.as_view(), name='admin-chat-send'),
]