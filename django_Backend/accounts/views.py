from django.contrib.auth import login
from rest_framework import generics, permissions, status
from rest_framework.response import Response

from .serializers import (
    UserRegistrationSerializer,
    UserLoginSerializer,
)
from .models import User

# User Registration API
class UserRegistrationAPIView(generics.CreateAPIView):
    serializer_class = UserRegistrationSerializer
    permission_classes = [permissions.AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Generate token immediately if Customer
        response_data = {
            'user_id': user.pk,
            'email': user.email,
            'role': user.role,
            'is_active': user.is_active,
        }

        if user.role == User.Role.CUSTOMER:
            login(request, user)
            token_serializer = UserLoginSerializer()
            tokens = token_serializer.get_tokens_for_user(user)
            response_data['tokens'] = tokens
            return Response(response_data, status=status.HTTP_201_CREATED)

        response_data['message'] = 'Account created successfully. Awaiting admin approval.'
        return Response(response_data, status=status.HTTP_201_CREATED)

# User Login API
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
            'user_id': user.pk,
            'email': user.email,
            'role': user.role,
            'is_active': user.is_active,
            'tokens': tokens
        }, status=status.HTTP_200_OK)
