import random

from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

from .models import CustomerProfile, ArtisanProfile, OTPVerification
from payments.models import Wallet

User = get_user_model()


# User Registration Serializer
class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    password2 = serializers.CharField(write_only=True)
    role = serializers.ChoiceField(choices=User.Role.choices)
    profession = serializers.CharField(
        required=False, allow_blank=True, max_length=100,
        help_text="Trade or profession for artisan accounts (e.g. Plumber, Electrician)"
    )

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'password2', 'role', 'phone_number', 'profession']

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError("Passwords don't match")

        # Validate profession is provided for artisan role
        if attrs.get('role') == User.Role.ARTISAN and not attrs.get('profession', '').strip():
            raise serializers.ValidationError(
                {"profession": "Please enter your trade or profession (e.g. Plumber, Electrician)"}
            )

        return attrs

    def create(self, validated_data):
        role = validated_data.pop('role')
        validated_data.pop('password2')
        profession = validated_data.pop('profession', '')

        user = User.objects.create_user(
            **validated_data,
            role=role,
            is_staff=role == User.Role.ADMIN,
            is_active=True if role == User.Role.CUSTOMER else False
        )

        # Automatically create associated profile and wallet
        if role == User.Role.ARTISAN:
            ArtisanProfile.objects.create(user=user, profession=profession.strip())
        elif role == User.Role.CUSTOMER:
            CustomerProfile.objects.create(user=user)

        Wallet.objects.get_or_create(user=user)

        return user


# User Login Serializer
class UserLoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()
    role = serializers.CharField()

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')
        role = attrs.get('role')

        # Django's authenticate() returns None for inactive users,
        # so check the user object directly to give a helpful error message.
        try:
            user_obj = User.objects.get(username=username)
        except User.DoesNotExist:
            raise serializers.ValidationError('Invalid credentials')

        if not user_obj.check_password(password):
            raise serializers.ValidationError('Invalid credentials')

        if not user_obj.is_active:
            # SECURITY: Use generic message to avoid revealing that the username exists
            raise serializers.ValidationError('Invalid credentials')

        if user_obj.role != role:
            raise serializers.ValidationError('Role mismatch')

        return {
            'user': user_obj,
        }

    def get_tokens_for_user(self, user):
        # Generate and return the tokens (JWT or similar)
        refresh = RefreshToken.for_user(user)
        access_token = refresh.access_token
        return {
            'access': str(access_token),
            'refresh': str(refresh),
        }


# Serializer for updating current user profile (with validation)
class UserUpdateSerializer(serializers.ModelSerializer):
    """Serializer for the CurrentUserAPIView.patch endpoint.

    Only allows updating email and phone_number with proper validation.
    """
    class Meta:
        model = User
        fields = ['email', 'phone_number']

    def validate_email(self, value):
        if value:
            # Check email uniqueness (excluding current user)
            user = self.instance
            if User.objects.filter(email=value).exclude(pk=user.pk).exists():
                raise serializers.ValidationError("A user with this email already exists.")
        return value


# Artisan Profile Serializer — explicit fields for security (no __all__)
class ArtisanProfileSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)
    review_count = serializers.SerializerMethodField()

    class Meta:
        model = ArtisanProfile
        fields = [
            'id', 'user', 'user_username', 'user_is_active',
            'profession', 'skills', 'hourly_rate', 'rating',
            'jobs_completed', 'location', 'latitude', 'longitude',
            'profile_picture', 'is_available', 'bio',
            'review_count', 'created_at', 'updated_at',
        ]
        read_only_fields = ('created_at', 'updated_at', 'user', 'is_verified', 'rating', 'jobs_completed')

    def get_review_count(self, obj):
        from bookings.models import Job
        return Job.objects.filter(
            artisan=obj,
            status=Job.Status.COMPLETED,
            rating__isnull=False,
        ).count()

    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list.")
        return value

    def validate_verification_documents(self, value):
        # Only admins can set verification_documents — reject from regular users
        if self.instance and value != self.instance.verification_documents:
            raise serializers.ValidationError("Verification documents can only be set by an administrator.")
        return value


# Admin-only serializer that allows setting is_verified
class ArtisanAdminProfileSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)

    class Meta:
        model = ArtisanProfile
        fields = [
            'id', 'user', 'user_username', 'user_is_active',
            'profession', 'skills', 'hourly_rate', 'rating',
            'jobs_completed', 'location', 'latitude', 'longitude',
            'profile_picture', 'is_verified', 'is_available', 'bio',
            'verification_documents', 'created_at', 'updated_at',
        ]
        read_only_fields = ('created_at', 'updated_at', 'user')


# Artisan self-service profile update serializer
# Only allows editing fields that the artisan themselves should control.
# Excludes is_available (use the availability toggle endpoint),
# latitude/longitude (use the location update endpoint),
# and system-managed fields (rating, jobs_completed, is_verified, etc.)
class ArtisanProfileSelfUpdateSerializer(serializers.ModelSerializer):
    """Serializer for artisans to update their own profile via
    PATCH /api/auth/me/artisan-profile/

    Only profession, skills, hourly_rate, bio, location, latitude, and longitude are editable.
    """
    class Meta:
        model = ArtisanProfile
        fields = ['profession', 'skills', 'hourly_rate', 'bio', 'location', 'latitude', 'longitude']

    def validate_profession(self, value):
        if not value or not value.strip():
            raise serializers.ValidationError("Profession is required.")
        return value.strip()

    def validate_skills(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Skills must be a list.")
        # Clean up empty strings
        return [s.strip() for s in value if isinstance(s, str) and s.strip()]

    def validate_hourly_rate(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError("Hourly rate cannot be negative.")
        return value


# Customer Profile Serializer (for admin customer management)
class CustomerProfileSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source='user.username', read_only=True)
    user_email = serializers.EmailField(source='user.email', read_only=True)
    user_is_active = serializers.BooleanField(source='user.is_active', read_only=True)
    job_count = serializers.SerializerMethodField()

    class Meta:
        model = CustomerProfile
        fields = ['id', 'user', 'user_username', 'user_email', 'user_is_active',
                  'address', 'bio', 'profile_picture', 'job_count']

    def get_job_count(self, obj):
        from bookings.models import Job
        return Job.objects.filter(customer=obj.user).count()


# Forgot Password Serializer
class ForgotPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField(required=False)
    username = serializers.CharField(required=False)

    def validate(self, attrs):
        email = attrs.get('email')
        username = attrs.get('username')

        if not email and not username:
            raise serializers.ValidationError(
                "Please provide either an email address or username."
            )

        # Look up user by email or username — always return the same
        # generic success message so we don't reveal whether the account exists.
        user = None
        if email:
            try:
                user = User.objects.get(email__iexact=email)
            except User.DoesNotExist:
                pass
        elif username:
            try:
                user = User.objects.get(username__iexact=username)
            except User.DoesNotExist:
                pass

        # Attach the user (or None) for the view to handle
        attrs['user'] = user
        return attrs


# Reset Password Serializer
class ResetPasswordSerializer(serializers.Serializer):
    otp = serializers.CharField(
        max_length=6,
        min_length=6,
        help_text="The 6-digit OTP sent to your email."
    )
    new_password = serializers.CharField(write_only=True)
    new_password2 = serializers.CharField(write_only=True)

    def validate(self, attrs):
        otp = attrs.get('otp')
        new_password = attrs.get('new_password')
        new_password2 = attrs.get('new_password2')

        if new_password != new_password2:
            raise serializers.ValidationError(
                {"new_password2": "Passwords do not match."}
            )

        # Look up a valid (unused, not expired) OTP record
        try:
            otp_record = OTPVerification.objects.get(
                otp=otp,
                purpose=OTPVerification.Purpose.PASSWORD_RESET,
                is_used=False,
            )
        except OTPVerification.DoesNotExist:
            raise serializers.ValidationError(
                {"otp": "Invalid or expired OTP."}
            )

        if otp_record.is_expired():
            raise serializers.ValidationError(
                {"otp": "OTP has expired. Please request a new one."}
            )

        # Validate the new password against Django's validators
        user = otp_record.user
        try:
            validate_password(new_password, user=user)
        except Exception:
            raise serializers.ValidationError(
                {"new_password": "Password does not meet security requirements."}
            )

        attrs['otp_record'] = otp_record
        attrs['user'] = user
        return attrs