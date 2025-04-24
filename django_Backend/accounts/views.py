from rest_framework import generics, permissions, status
from rest_framework.response import Response
from django.contrib.auth import login
from .serializers import (
    UserRegistrationSerializer,
    UserLoginSerializer,
)
from .models import User

class UserRegistrationAPIView(generics.CreateAPIView):
    serializer_class = UserRegistrationSerializer
    permission_classes = [permissions.AllowAny]
    
    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        
        # Generate token for immediate login if customer
        if user.role == User.Role.CUSTOMER:
            login(request, user)
            token_serializer = UserLoginSerializer()
            tokens = token_serializer.get_tokens_for_user(user)
            return Response({
                'tokens': tokens,
                'user_id': user.pk,
                'email': user.email,
                'role': user.role,
                'is_active': user.is_active
            }, status=status.HTTP_201_CREATED)
        else:
            return Response({
                'message': 'Account created successfully. Awaiting admin approval.',
                'user_id': user.pk,
                'role': user.role,
                'is_active': user.is_active
            }, status=status.HTTP_201_CREATED)

class UserLoginAPIView(generics.GenericAPIView):
    serializer_class = UserLoginSerializer
    permission_classes = [permissions.AllowAny]
    
    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        
        login(request, user)
        tokens = serializer.get_tokens_for_user(user)
        
        return Response({
            'tokens': tokens,
            'user_id': user.pk,
            'email': user.email,
            'role': user.role,
            'is_active': user.is_active
        })