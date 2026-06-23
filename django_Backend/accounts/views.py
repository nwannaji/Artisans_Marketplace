import logging

from django.contrib.auth import login
from django.contrib.auth.password_validation import validate_password
from django.core.files.uploadedfile import InMemoryUploadedFile
from django.db.models import Count, Avg
from rest_framework import generics, permissions, status, serializers as drf_serializers
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.authentication import TokenAuthentication
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters

from .permissions import IsAdminRole

from .serializers import (
    UserRegistrationSerializer,
    UserLoginSerializer,
    CustomerProfileSerializer,
    ArtisanProfileSelfUpdateSerializer,
)
from .models import User, ArtisanProfile, CustomerProfile
from bookings.models import Job

logger = logging.getLogger(__name__)


# User Registration API
class UserRegistrationAPIView(generics.CreateAPIView):
    serializer_class = UserRegistrationSerializer
    authentication_classes = []  # Skip auth — registration is anonymous
    permission_classes = [AllowAny]

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
    authentication_classes = []  # Skip auth — login is anonymous; stale tokens in header must not cause 401
    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']

        # Login the user
        login(request, user)

        # Get JWT tokens for the user
        tokens = serializer.get_tokens_for_user(user)

        # Return the user data and tokens
        return Response({
            'user_id': user.pk,
            'email': user.email,
            'role': user.role,
            'is_active': user.is_active,
            'tokens': tokens
        }, status=status.HTTP_200_OK)


class CurrentUserAPIView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        data = {
            'user_id': user.pk,
            'username': user.username,
            'email': user.email,
            'role': user.role,
            'is_active': user.is_active,
            'is_verified': user.is_verified,
            'phone_number': user.phone_number,
            'photo_url': None,
        }
        if user.role == User.Role.ARTISAN:
            try:
                profile = user.artisanprofile
                # Count reviews (completed jobs with ratings) — use aggregate to avoid N+1
                review_agg = Job.objects.filter(
                    artisan=profile,
                    status=Job.Status.COMPLETED,
                    rating__isnull=False,
                ).aggregate(
                    review_count=Count('id'),
                    avg_rating=Avg('rating'),
                )
                data['photo_url'] = profile.profile_picture.url if profile.profile_picture else None
                data['artisan_profile'] = {
                    'id': profile.pk,
                    'profession': profile.profession,
                    'skills': profile.skills,
                    'hourly_rate': str(profile.hourly_rate) if profile.hourly_rate else None,
                    'rating': profile.rating,
                    'review_count': review_agg['review_count'] or 0,
                    'jobs_completed': profile.jobs_completed,
                    'location': profile.location,
                    'latitude': str(profile.latitude) if profile.latitude else None,
                    'longitude': str(profile.longitude) if profile.longitude else None,
                    'profile_picture': profile.profile_picture.url if profile.profile_picture else None,
                    'is_verified': profile.is_verified,
                    'is_available': profile.is_available,
                    'bio': profile.bio,
                }
            except ArtisanProfile.DoesNotExist:
                pass
        elif user.role == User.Role.CUSTOMER:
            try:
                profile = user.customerprofile
                data['photo_url'] = profile.profile_picture.url if profile.profile_picture else None
                data['customer_profile'] = {
                    'id': profile.pk,
                    'address': profile.address,
                    'bio': profile.bio,
                    'profile_picture': profile.profile_picture.url if profile.profile_picture else None,
                }
            except CustomerProfile.DoesNotExist:
                pass
        return Response(data)

    def patch(self, request):
        """Update the current user's profile (email, phone_number).

        Uses the UserUpdateSerializer for proper validation instead of
        directly mutating request.data.
        """
        from .serializers import UserUpdateSerializer
        user = request.user
        serializer = UserUpdateSerializer(user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({'message': 'Profile updated successfully'})


class ArtisanProfileSelfUpdateView(APIView):
    """Allow artisans to update their own profile fields.

    PATCH /api/auth/me/artisan-profile/

    Only the artisan themselves can update, and only the fields they
    should control: profession, skills, hourly_rate, bio, location.
    System-managed fields (rating, jobs_completed, is_verified) and
    availability (use the dedicated toggle endpoint) are excluded.
    """
    permission_classes = [IsAuthenticated]

    def get_artisan_profile(self, user):
        """Get the artisan profile for the current user, or 404."""
        try:
            return ArtisanProfile.objects.get(user=user)
        except ArtisanProfile.DoesNotExist:
            return None

    def get(self, request):
        """Return the current artisan's profile data."""
        if request.user.role != User.Role.ARTISAN:
            return Response(
                {'error': 'Only artisan accounts can access this endpoint.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        profile = self.get_artisan_profile(request.user)
        if profile is None:
            return Response(
                {'error': 'Artisan profile not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        from .serializers import ArtisanProfileSerializer
        serializer = ArtisanProfileSerializer(profile)
        return Response(serializer.data)

    def patch(self, request):
        """Update the current artisan's profile."""
        if request.user.role != User.Role.ARTISAN:
            return Response(
                {'error': 'Only artisan accounts can access this endpoint.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        profile = self.get_artisan_profile(request.user)
        if profile is None:
            return Response(
                {'error': 'Artisan profile not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = ArtisanProfileSelfUpdateSerializer(
            profile, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()

        # Return full profile data so the client can update its state
        from .serializers import ArtisanProfileSerializer
        full_serializer = ArtisanProfileSerializer(profile)
        return Response(full_serializer.data)


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        current_password = request.data.get('current_password')
        new_password = request.data.get('new_password')

        if not current_password or not new_password:
            return Response(
                {'error': 'Both current_password and new_password are required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not user.check_password(current_password):
            return Response(
                {'error': 'Current password is incorrect'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            validate_password(new_password, user=user)
        except Exception:
            # SECURITY: Do not expose detailed password validation errors
            return Response(
                {'error': 'Password does not meet security requirements.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        user.set_password(new_password)
        user.save()
        return Response({'message': 'Password changed successfully'})


class ArtisanAvailabilityToggleView(APIView):
    """Allow artisans to toggle their availability status (AVAILABLE, BUSY, OFFLINE).
    Note: ENGAGED is a system-managed status set automatically when an artisan
    has an active booking — artisans cannot set it manually.

    Optionally accepts latitude and longitude to update the artisan's stored
    location when they become available (for real-time GPS positioning).
    """
    permission_classes = [IsAuthenticated]

    def patch(self, request):
        user = request.user

        if user.role != User.Role.ARTISAN:
            return Response(
                {"error": "Only artisans can toggle availability"},
                status=status.HTTP_403_FORBIDDEN
            )

        new_status = request.data.get('is_available')
        # ENGAGED is a system-managed status — artisans cannot set it manually
        valid_statuses = [
            ArtisanProfile.AvailabilityStatus.AVAILABLE,
            ArtisanProfile.AvailabilityStatus.BUSY,
            ArtisanProfile.AvailabilityStatus.OFFLINE,
        ]

        if new_status not in valid_statuses:
            return Response(
                {"error": f"Invalid status. Use one of: {', '.join(valid_statuses)}"},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            profile = ArtisanProfile.objects.get(user=user)
        except ArtisanProfile.DoesNotExist:
            return Response(
                {"error": "Artisan profile not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        # Prevent setting AVAILABLE if the artisan has active jobs
        if new_status == ArtisanProfile.AvailabilityStatus.AVAILABLE:
            has_active_jobs = Job.objects.filter(
                artisan=profile,
                status__in=[
                    Job.Status.PENDING,
                    Job.Status.ADMIN_APPROVED,
                    Job.Status.ACCEPTED,
                    Job.Status.IN_PROGRESS,
                ]
            ).exists()
            if has_active_jobs:
                return Response(
                    {"error": "Cannot set availability to Available while you have active jobs. "
                               "Complete or cancel your active jobs first."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # If artisan is ENGAGED, only allow switching to BUSY or OFFLINE
        if profile.is_available == ArtisanProfile.AvailabilityStatus.ENGAGED:
            if new_status not in (
                ArtisanProfile.AvailabilityStatus.BUSY,
                ArtisanProfile.AvailabilityStatus.OFFLINE,
            ):
                return Response(
                    {"error": "You currently have an active booking. "
                              "You can switch to Busy or Offline, but not Available until your booking is completed."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        profile.is_available = new_status

        # Update location coordinates if provided (from phone GPS)
        update_fields = ['is_available']
        latitude = request.data.get('latitude')
        longitude = request.data.get('longitude')
        if latitude is not None and longitude is not None:
            try:
                lat = float(latitude)
                lng = float(longitude)
                if -90 <= lat <= 90 and -180 <= lng <= 180:
                    profile.latitude = lat
                    profile.longitude = lng
                    update_fields += ['latitude', 'longitude']
            except (ValueError, TypeError):
                pass  # Ignore invalid coordinates silently

        # Also update the text location if provided
        location_name = request.data.get('location')
        if location_name:
            profile.location = location_name
            update_fields.append('location')

        profile.save(update_fields=update_fields)
        return Response({
            "is_available": profile.is_available,
            "latitude": str(profile.latitude) if profile.latitude else None,
            "longitude": str(profile.longitude) if profile.longitude else None,
            "message": f"Availability updated to {profile.get_is_available_display()}"
        })


class UserActivateAPIView(APIView):
    """Admin activates or deactivates a user account.

    PATCH /api/auth/users/<pk>/activate/ with {"is_active": true/false}
    """
    permission_classes = [IsAdminRole]

    def patch(self, request, pk):
        try:
            user = User.objects.get(pk=pk)
        except User.DoesNotExist:
            return Response(
                {"error": "User not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        is_active = request.data.get('is_active')
        if is_active is None:
            return Response(
                {"error": "is_active field is required"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # SECURITY: Fix boolean coercion — bool("false") == True was a bug
        if isinstance(is_active, str):
            is_active = is_active.lower() in ('true', '1', 'yes')
        else:
            is_active = bool(is_active)

        user.is_active = is_active
        user.save(update_fields=['is_active'])

        logger.info(
            "User %s (pk=%s) %s by admin %s",
            user.username, user.pk,
            'activated' if is_active else 'deactivated',
            request.user.username,
        )

        return Response({
            "user_id": user.pk,
            "username": user.username,
            "is_active": user.is_active,
            "message": f"Account {'activated' if user.is_active else 'deactivated'} successfully"
        })


class CustomerListAPIView(generics.ListAPIView):
    """Admin lists all customer accounts with their profile info."""
    serializer_class = CustomerProfileSerializer
    permission_classes = [IsAdminRole]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter]
    search_fields = ['user__username', 'user__email']
    filterset_fields = ['user__is_active']

    def get_queryset(self):
        return CustomerProfile.objects.select_related('user').all()


class ArtisanLocationUpdateView(APIView):
    """Artisan updates their GPS location without changing availability status.

    Used for periodic location updates while the artisan is available.
    """
    permission_classes = [IsAuthenticated]

    def patch(self, request):
        user = request.user

        if user.role != User.Role.ARTISAN:
            return Response(
                {"error": "Only artisans can update their location"},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            profile = ArtisanProfile.objects.get(user=user)
        except ArtisanProfile.DoesNotExist:
            return Response(
                {"error": "Artisan profile not found"},
                status=status.HTTP_404_NOT_FOUND
            )

        latitude = request.data.get('latitude')
        longitude = request.data.get('longitude')
        location_name = request.data.get('location')

        update_fields = []
        if latitude is not None and longitude is not None:
            try:
                lat = float(latitude)
                lng = float(longitude)
                # Validate coordinate ranges
                if not (-90 <= lat <= 90 and -180 <= lng <= 180):
                    return Response(
                        {"error": "Latitude must be between -90 and 90, longitude between -180 and 180"},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                profile.latitude = lat
                profile.longitude = lng
                update_fields += ['latitude', 'longitude']
            except (ValueError, TypeError):
                return Response(
                    {"error": "Invalid latitude or longitude values"},
                    status=status.HTTP_400_BAD_REQUEST
                )

        if location_name:
            profile.location = location_name
            update_fields.append('location')

        if not update_fields:
            return Response(
                {"error": "No location data provided"},
                status=status.HTTP_400_BAD_REQUEST
            )

        profile.save(update_fields=update_fields)
        return Response({
            "message": "Location updated",
            "latitude": str(profile.latitude) if profile.latitude else None,
            "longitude": str(profile.longitude) if profile.longitude else None,
            "location": profile.location,
        })


class ProfilePictureUploadView(APIView):
    """Upload or update the current user's profile picture.

    POST /api/auth/me/upload-picture/ with multipart form data:
        - profile_picture: image file (required)

    Works for all user roles (Customer, Artisan, Admin).
    For Customer/Artisan, updates their respective profile model.
    For Admin, creates a basic profile record if needed.
    """
    permission_classes = [IsAuthenticated]

    # SECURITY: Allowed file extensions
    ALLOWED_EXTENSIONS = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif']
    MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB

    # Map of content types to their canonical extension
    CONTENT_TYPE_MAP = {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
        'image/gif': 'gif',
        'image/heic': 'heic',
        'image/heif': 'heif',
    }

    def post(self, request):
        user = request.user

        if 'profile_picture' not in request.FILES:
            logger.warning(
                "Upload picture: no file in request. Content-Type: %s, FILES keys: %s, POST keys: %s",
                request.content_type,
                list(request.FILES.keys()),
                list(request.POST.keys()),
            )
            return Response(
                {'error': 'No image file provided. Use "profile_picture" field.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        image = request.FILES['profile_picture']
        logger.info(
            "Upload picture: user=%s, name=%s, content_type=%s, size=%d",
            user.username, image.name, image.content_type, image.size,
        )

        # SECURITY: Validate file extension (not just content_type which can be spoofed)
        file_ext = image.name.rsplit('.', 1)[-1].lower() if '.' in image.name else ''

        # If no extension in filename, infer from content_type
        if not file_ext and image.content_type in self.CONTENT_TYPE_MAP:
            file_ext = self.CONTENT_TYPE_MAP[image.content_type]

        if file_ext not in self.ALLOWED_EXTENSIONS:
            logger.warning(
                "Upload picture: invalid extension '%s' for file '%s' (content_type=%s)",
                file_ext, image.name, image.content_type,
            )
            return Response(
                {'error': f'Invalid file type ".{file_ext or image.name}". Allowed: JPG, JPEG, PNG, WebP, GIF.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # SECURITY: Validate content_type as additional check
        # Accept application/octet-stream as fallback — mobile clients often
        # send this when they can't determine the real MIME type.  If the
        # extension is valid we trust it over an ambiguous content-type.
        allowed_types = list(self.CONTENT_TYPE_MAP.keys()) + ['application/octet-stream']
        if image.content_type not in allowed_types:
            logger.warning(
                "Upload picture: invalid content_type '%s' for file '%s'",
                image.content_type, image.name,
            )
            return Response(
                {'error': f'Invalid content type "{image.content_type}". Allowed: JPEG, PNG, WebP, GIF, HEIC.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # If content_type is the generic fallback, infer the real type from
        # the file extension so Pillow / storage gets the correct MIME type.
        if image.content_type == 'application/octet-stream' and file_ext in self.CONTENT_TYPE_MAP.values():
            real_type = [k for k, v in self.CONTENT_TYPE_MAP.items() if v == file_ext][0]
            image.content_type = real_type
            logger.info(
                "Upload picture: inferred content_type '%s' from extension '%s' for user %s",
                real_type, file_ext, user.username,
            )

        # Validate file size
        if image.size > self.MAX_FILE_SIZE:
            return Response(
                {'error': f'Image file too large ({image.size // (1024*1024)}MB). Maximum size is 5MB.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Convert HEIC/HEIF to JPEG before saving (Pillow doesn't support HEIC natively)
        if file_ext in ('heic', 'heif'):
            try:
                from PIL import Image
                import io as io_module
                img = Image.open(image)
                img = img.convert('RGB')
                buf = io_module.BytesIO()
                img.save(buf, format='JPEG', quality=85)
                buf.seek(0)
                # Replace with JPEG version
                new_name = image.name.rsplit('.', 1)[0] + '.jpg'
                image = InMemoryUploadedFile(
                    file=buf,
                    field_name=image.field_name,
                    name=new_name,
                    content_type='image/jpeg',
                    size=buf.getbuffer().nbytes,
                    charset=None,
                )
            except Exception as e:
                logger.warning("Failed to convert HEIC image for user %s: %s", user.pk, e)
                return Response(
                    {'error': 'Could not process HEIC image. Please convert to JPG or PNG and try again.'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Save to the appropriate profile
        if user.role == User.Role.ARTISAN:
            try:
                profile = user.artisanprofile
            except ArtisanProfile.DoesNotExist:
                return Response(
                    {'error': 'Artisan profile not found.'},
                    status=status.HTTP_404_NOT_FOUND
                )
            # Delete old picture if it exists and is not the default
            if profile.profile_picture:
                try:
                    profile.profile_picture.delete(save=False)
                except Exception:
                    logger.warning("Failed to delete old profile picture for user %s", user.pk)
            profile.profile_picture = image
            profile.save(update_fields=['profile_picture'])

        elif user.role == User.Role.CUSTOMER:
            profile, created = CustomerProfile.objects.get_or_create(user=user)
            # Delete old picture if it exists
            if profile.profile_picture:
                try:
                    profile.profile_picture.delete(save=False)
                except Exception:
                    logger.warning("Failed to delete old profile picture for user %s", user.pk)
            profile.profile_picture = image
            profile.save(update_fields=['profile_picture'])

        else:
            # Admin — store on a CustomerProfile (or could be a separate model)
            # For simplicity, we use CustomerProfile for admins too
            profile, created = CustomerProfile.objects.get_or_create(user=user)
            if profile.profile_picture:
                try:
                    profile.profile_picture.delete(save=False)
                except Exception:
                    logger.warning("Failed to delete old profile picture for user %s", user.pk)
            profile.profile_picture = image
            profile.save(update_fields=['profile_picture'])

        return Response({
            'message': 'Profile picture updated successfully',
            'photo_url': profile.profile_picture.url if profile.profile_picture else None,
        })