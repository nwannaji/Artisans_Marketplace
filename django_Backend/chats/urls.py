from django.urls import path
from .views import ChatListCreateAPIView, ChatThreadAPIView

app_name='chats'

urlpatterns = [
    path('messages/', ChatListCreateAPIView.as_view(), name='chat-list-create'),
    path('messages/<int:user_id>/', ChatThreadAPIView.as_view(), name='chat-thread'),
]
