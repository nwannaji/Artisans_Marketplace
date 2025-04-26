from rest_framework import generics, permissions,exceptions
from .models import Chat
from accounts.models import User
from .serializers import ChatSerializer
from django.db.models import Q

class ChatListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = ChatSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return Chat.objects.filter(sender=user) | Chat.objects.filter(receiver=user)

    def perform_create(self, serializer):
        user = self.request.user
        receiver = serializer.validated_data['receiver']
        
        # Check if the receiver exists
        if not User.objects.filter(id=receiver.id).exists():
            raise exceptions.ValidationError("Receiver does not exist.")

        # Validate that customers can only send messages to artisans
        if user.role == User.Role.CUSTOMER:
            if receiver.role != User.Role.ARTISAN:
                raise exceptions.ValidationError("Customers can only send messages to artisans.")
        
        # Validate that artisans can only send messages to customers
        if user.role == User.Role.ARTISAN:
            if receiver.role != User.Role.CUSTOMER:
                raise exceptions.ValidationError("Artisans can only send messages to customers.")
        
        # If the validations pass, set sender and save the message
        serializer.save(sender=user)


class ChatThreadAPIView(generics.ListAPIView):
    serializer_class = ChatSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        other_user_id = self.kwargs.get('user_id')  # id of the person you're chatting with

        return Chat.objects.filter(
            Q(sender=user, receiver__id=other_user_id) |
            Q(sender__id=other_user_id, receiver=user)
        ).order_by('timestamp')

