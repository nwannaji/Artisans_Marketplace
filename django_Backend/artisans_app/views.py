import math
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import MultiPartParser, FormParser
from django.db.models import Q
from rest_framework import generics, permissions, status, filters
from rest_framework.response import Response
from rest_framework.views import APIView
from django_filters.rest_framework import DjangoFilterBackend
from accounts.models import User, ArtisanProfile
from accounts.serializers import ArtisanProfileSerializer, ArtisanAdminProfileSerializer
from .filters import ArtisanFilter
from .models_portfolio import PortfolioImage
from .serializers import PortfolioImageSerializer
from subscriptions.utils import annotate_tier_priority


class ArtisanProfileCreateAPIView(generics.CreateAPIView):
    queryset = ArtisanProfile.objects.all()
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        # SECURITY: Only artisan-role users can create artisan profiles
        if self.request.user.role != User.Role.ARTISAN:
            raise ValidationError("Only artisan accounts can create artisan profiles.")
        if ArtisanProfile.objects.filter(user=self.request.user).exists():
            raise ValidationError("You already have an artisan profile.")
        serializer.save(user=self.request.user)

    def create(self, request, *args, **kwargs):
        response = super().create(request, *args, **kwargs)
        return Response({
            "message": "Artisan profile created successfully.",
            "artisan_profile": response.data
        }, status=status.HTTP_201_CREATED)


class ArtisanListAPIView(generics.ListAPIView):
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.AllowAny]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_class = ArtisanFilter
    search_fields = ['profession', 'skills', 'location']
    ordering_fields = ['rating', 'hourly_rate', 'jobs_completed']

    def get_queryset(self):
        """
        By default, only return artisans whose user account is active
        (i.e. approved by admin). Admin users can pass ?is_active=false
        (or ?is_active=all) to also see pending/inactive artisans.

        Results are ordered by subscription tier priority (Premium first,
        then Pro, then Free) and then by rating, so subscribed artisans
        appear higher in search results.
        """
        qs = ArtisanProfile.objects.select_related('user', 'subscription').all()

        is_active_param = self.request.query_params.get('is_active', 'true')

        if is_active_param.lower() == 'all':
            pass  # No filter — return all artisans regardless of active status
        elif is_active_param.lower() == 'false':
            qs = qs.filter(user__is_active=False)
        else:
            qs = qs.filter(user__is_active=True)

        # Exclude artisans with unset/default (0,0) coordinates so distance
        # computation is meaningful when lat/lng params are provided.
        if self.request.query_params.get('lat') and self.request.query_params.get('lng'):
            qs = qs.exclude(latitude=0, longitude=0)

        # Boost subscribed artisans in search results:
        # Premium (priority 0) > Pro (priority 1) > Free (priority 2)
        qs = annotate_tier_priority(qs)
        qs = qs.order_by('tier_priority', '-rating', '-jobs_completed')

        return qs

    def list(self, request, *args, **kwargs):
        """Override list to inject distance_km when lat/lng query params are provided."""
        response = super().list(request, *args, **kwargs)

        # If the client sends lat & lng, compute and attach distance_km to each result
        try:
            user_lat = float(request.query_params.get('lat'))
            user_lng = float(request.query_params.get('lng'))
        except (TypeError, ValueError):
            return response  # no valid coords → return results as-is

        # DRF paginated responses use {'results': [...]}, unpaginated are a plain list
        items = response.data.get('results', response.data) if isinstance(response.data, dict) else response.data
        for item in items:
            artisan_lat = item.get('latitude')
            artisan_lng = item.get('longitude')
            if artisan_lat is not None and artisan_lng is not None:
                try:
                    distance = self._haversine_km(
                        user_lat, user_lng,
                        float(artisan_lat), float(artisan_lng),
                    )
                    item['distance_km'] = round(distance, 2)
                except (TypeError, ValueError):
                    pass

        return response

    @staticmethod
    def _haversine_km(lat1, lng1, lat2, lng2):
        """Haversine formula returning distance in kilometres."""
        R = 6371.0
        d_lat = math.radians(lat2 - lat1)
        d_lng = math.radians(lng2 - lng1)
        a = (math.sin(d_lat / 2) ** 2
             + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
             * math.sin(d_lng / 2) ** 2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return R * c


class ArtisanDetailAPIView(generics.RetrieveAPIView):
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        """
        By default, only active artisans are visible.
        But authenticated customers who have a job with an inactive artisan
        should still be able to see that artisan's details.
        """
        qs = ArtisanProfile.objects.select_related('user').all()
        user = self.request.user
        if user.is_authenticated and user.role == User.Role.CUSTOMER:
            # Show active artisans OR artisans the customer has a job with
            active_or_assigned = qs.filter(
                Q(user__is_active=True)
                | Q(artisan_jobs__customer=user)
            ).distinct()
            return active_or_assigned
        return qs.filter(user__is_active=True)


class ArtisanProfileUpdateAPIView(generics.UpdateAPIView):
    queryset = ArtisanProfile.objects.all()
    serializer_class = ArtisanProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_serializer_class(self):
        # Admin users can set is_verified; regular users cannot
        if self.request.user.role == User.Role.ADMIN:
            return ArtisanAdminProfileSerializer
        return ArtisanProfileSerializer

    def get_object(self):
        from django.shortcuts import get_object_or_404
        # Admins can update any profile, but users can only update their own
        if self.request.user.role == User.Role.ADMIN:
            return get_object_or_404(ArtisanProfile, pk=self.kwargs['pk'])
        return get_object_or_404(ArtisanProfile, user=self.request.user)

    def perform_update(self, serializer):
        serializer.save()


class ArtisanNearbySearchAPIView(APIView):
    """Search for nearby available artisans within a radius using haversine formula.

    Query params:
        lat (required): Latitude of the search center
        lng (required): Longitude of the search center
        radius_km (default 10): Search radius in kilometers
        profession (optional): Filter by profession (case-insensitive)
        search (optional): Search across profession, skills, and location (case-insensitive)
        availability (default 'AVAILABLE'): Filter by availability status.
            Pass 'all' to see artisans regardless of availability.
    """
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        try:
            lat = float(request.query_params.get('lat'))
            lng = float(request.query_params.get('lng'))
        except (TypeError, ValueError):
            return Response(
                {"error": "lat and lng query parameters are required and must be numeric"},
                status=status.HTTP_400_BAD_REQUEST
            )

        radius_km = float(request.query_params.get('radius_km', 10.0))
        profession = request.query_params.get('profession', None)
        search = request.query_params.get('search', None)
        availability = request.query_params.get('availability', 'AVAILABLE')

        # Bounding-box pre-filter to reduce the haversine computation set
        lat_offset = radius_km / 111.0
        lng_offset = radius_km / (111.0 * math.cos(math.radians(lat)))

        artisans_qs = ArtisanProfile.objects.filter(
            user__is_active=True,
            latitude__isnull=False,
            longitude__isnull=False,
        ).exclude(
            latitude=0, longitude=0,  # skip artisans with unset/default GPS coords
        ).filter(
            latitude__gte=lat - lat_offset,
            latitude__lte=lat + lat_offset,
            longitude__gte=lng - lng_offset,
            longitude__lte=lng + lng_offset,
        )

        # Filter by availability (default: AVAILABLE only)
        if availability != 'all':
            artisans_qs = artisans_qs.filter(is_available=availability)

        # Filter by profession (case-insensitive)
        if profession:
            artisans_qs = artisans_qs.filter(profession__icontains=profession)

        # Search across profession, skills, and location (case-insensitive)
        if search:
            from django.db.models import Q
            artisans_qs = artisans_qs.filter(
                Q(profession__icontains=search)
                | Q(skills__icontains=search)
                | Q(location__icontains=search)
            )

        results = []
        for artisan in artisans_qs:
            try:
                artisan_lat = float(artisan.latitude)
                artisan_lng = float(artisan.longitude)
            except (TypeError, ValueError):
                continue

            # Haversine formula
            R = 6371  # Earth radius in km
            dlat = math.radians(artisan_lat - lat)
            dlng = math.radians(artisan_lng - lng)
            a = (math.sin(dlat / 2) ** 2 +
                 math.cos(math.radians(lat)) * math.cos(math.radians(artisan_lat)) *
                 math.sin(dlng / 2) ** 2)
            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
            distance = R * c

            if distance <= radius_km:
                serializer = ArtisanProfileSerializer(artisan)
                data = serializer.data
                data['distance_km'] = round(distance, 2)
                # Estimated arrival: assume 20 km/h urban speed, minimum 5 min
                data['estimated_arrival_minutes'] = max(5, round(distance / 20 * 60))
                results.append(data)

        # Sort by distance (nearest first)
        results.sort(key=lambda x: x['distance_km'])

        return Response({
            'count': len(results),
            'radius_km': radius_km,
            'results': results
        })


class ProfessionListAPIView(APIView):
    """Return distinct professions from active artisan profiles."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        professions = (
            ArtisanProfile.objects
            .filter(user__is_active=True, profession__isnull=False)
            .exclude(profession='')
            .values_list('profession', flat=True)
            .distinct()
            .order_by('profession')
        )
        return Response({'professions': list(professions)})


class PortfolioImageListCreateAPIView(generics.ListCreateAPIView):
    """
    GET  /api/artisans/portfolio/       — list portfolio images for the requesting artisan (or all for admin)
    POST /api/artisans/portfolio/       — upload a new portfolio image (artisans only)
    """
    serializer_class = PortfolioImageSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        user = self.request.user
        if user.role == User.Role.ADMIN:
            return PortfolioImage.objects.select_related('artisan').all()
        return PortfolioImage.objects.select_related('artisan').filter(artisan=user)

    def perform_create(self, serializer):
        user = self.request.user
        if user.role != User.Role.ARTISAN:
            raise ValidationError("Only artisan accounts can upload portfolio images.")
        serializer.save(artisan=user)


class PortfolioImageDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/artisans/portfolio/<pk>/  — retrieve a specific portfolio image
    PATCH  /api/artisans/portfolio/<pk>/  — update caption / order (owner or admin)
    DELETE /api/artisans/portfolio/<pk>/  — delete a portfolio image (owner or admin)
    """
    serializer_class = PortfolioImageSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        return PortfolioImage.objects.select_related('artisan').all()

    def check_object_permissions(self, request, obj):
        super().check_object_permissions(request, obj)
        # Only the owning artisan or an admin may modify/delete
        if request.method in ('PATCH', 'PUT', 'DELETE'):
            if obj.artisan != request.user and request.user.role != User.Role.ADMIN:
                raise ValidationError("You do not have permission to modify this portfolio image.")

    def perform_update(self, serializer):
        # On update, only caption and order should be mutable; artisan stays the same
        serializer.save()