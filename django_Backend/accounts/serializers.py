from django.contrib.auth import authenticate, get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

from .models import CustomerProfile, ArtisanProfile

User = get_user_model()

# User Registration Serializer
class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    password2 = serializers.CharField(write_only=True)
    role = serializers.ChoiceField(choices=User.Role.choices)

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'password2', 'role', 'phone_number']

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError("Passwords don't match")
        return attrs

    def create(self, validated_data):
        role = validated_data.pop('role')
        validated_data.pop('password2')

        user = User.objects.create_user(
            **validated_data,
            role=role,
            is_active=True if role == User.Role.CUSTOMER else False
        )

        # Automatically create associated profile
        if role == User.Role.ARTISAN:
            ArtisanProfile.objects.create(user=user)
        elif role == User.Role.CUSTOMER:
            CustomerProfile.objects.create(user=user)

        return user

# User Login Serializer
class UserLoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')

        if username and password:
            user = authenticate(username=username, password=password)
            if user:
                if not user.is_active and user.role in [User.Role.ARTISAN, User.Role.ADMIN]:
                    raise serializers.ValidationError(
                        "Account is pending admin approval. Please contact support."
                    )
                attrs['user'] = user
            else:
                raise serializers.ValidationError("Invalid credentials")
        else:
            raise serializers.ValidationError("Both 'username' and 'password' are required.")

        return attrs

    @staticmethod
    def get_tokens_for_user(user):
        refresh = RefreshToken.for_user(user)
        return {
            'refresh': str(refresh),
            'access': str(refresh.access_token),
        }

# Artisan Profile Serializer
class ArtisanProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = ArtisanProfile
        fields = '__all__'
        read_only_fields = ('created_at', 'updated_at')
