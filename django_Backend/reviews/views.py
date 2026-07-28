from django.db.models import Avg, Count
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.response import Response

from accounts.models import ArtisanProfile
from bookings.models import Job
from .models import Review
from .serializers import (
    ReviewCreateSerializer,
    ReviewSerializer,
    ReviewUpdateSerializer,
)


class IsReviewOwner(permissions.BasePermission):
    """Only allow the review's customer to modify/delete it."""
    def has_object_permission(self, request, view, obj):
        return obj.customer == request.user


class ArtisanReviewListCreateView(generics.ListCreateAPIView):
    """GET /api/artisans/<pk>/reviews/  — list reviews (public, paginated)
    POST /api/artisans/<pk>/reviews/  — create a review (customer only)
    """
    serializer_class = ReviewSerializer

    def get_permissions(self):
        if self.request.method == 'POST':
            return [permissions.IsAuthenticated()]
        return [permissions.AllowAny()]

    def get_queryset(self):
        artisan_pk = self.kwargs['artisan_pk']
        return Review.objects.filter(
            artisan_id=artisan_pk,
        ).select_related('customer', 'job').order_by('-created_at')

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        artisan_pk = kwargs['artisan_pk']

        # Custom pagination (page size 10)
        page = int(request.query_params.get('page', 1))
        page_size = 10
        total_count = queryset.count()
        start = (page - 1) * page_size
        end = start + page_size
        page_queryset = queryset[start:end]

        serializer = self.get_serializer(page_queryset, many=True)

        # Build rating summary
        try:
            artisan = ArtisanProfile.objects.get(pk=artisan_pk)
        except ArtisanProfile.DoesNotExist:
            return Response(
                {"error": "Artisan not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        all_reviews = queryset
        distribution = {}
        for star in range(5, 0, -1):
            if star == 5:
                distribution[str(star)] = all_reviews.filter(rating__gte=4.5).count()
            elif star == 4:
                distribution[str(star)] = all_reviews.filter(rating__gte=3.5, rating__lt=4.5).count()
            elif star == 3:
                distribution[str(star)] = all_reviews.filter(rating__gte=2.5, rating__lt=3.5).count()
            elif star == 2:
                distribution[str(star)] = all_reviews.filter(rating__gte=1.5, rating__lt=2.5).count()
            elif star == 1:
                distribution[str(star)] = all_reviews.filter(rating__gte=0.5, rating__lt=1.5).count()

        summary = {
            "average_rating": artisan.rating,
            "total_reviews": total_count,
            "rating_distribution": distribution,
        }

        has_next = end < total_count

        return Response({
            "count": total_count,
            "next": f"?page={page + 1}" if has_next else None,
            "previous": f"?page={page - 1}" if page > 1 else None,
            "results": serializer.data,
            "summary": summary,
        })

    def create(self, request, *args, **kwargs):
        artisan_pk = kwargs['artisan_pk']

        # Validate artisan exists
        try:
            artisan = ArtisanProfile.objects.get(pk=artisan_pk)
        except ArtisanProfile.DoesNotExist:
            return Response(
                {"error": "Artisan not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Only customers can create reviews
        if request.user.role != 'CUSTOMER':
            return Response(
                {"error": "Only customers can review artisans."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Cannot review yourself
        if artisan.user == request.user:
            return Response(
                {"error": "You cannot review yourself."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # One review per customer per artisan
        if Review.objects.filter(customer=request.user, artisan=artisan).exists():
            return Response(
                {"error": "You have already reviewed this artisan. Use PATCH to update your review."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = ReviewCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        review = Review.objects.create(
            artisan=artisan,
            customer=request.user,
            rating=serializer.validated_data['rating'],
            comment=serializer.validated_data.get('comment', ''),
        )

        output_serializer = ReviewSerializer(review)
        return Response(output_serializer.data, status=status.HTTP_201_CREATED)


class MyArtisanReviewView(generics.RetrieveAPIView):
    """GET /api/artisans/<pk>/reviews/mine/ — get the current user's review for an artisan."""
    serializer_class = ReviewSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        artisan_pk = self.kwargs['artisan_pk']
        return get_object_or_404(
            Review, customer=self.request.user, artisan_id=artisan_pk
        )


class ReviewDetailView(generics.RetrieveUpdateDestroyAPIView):
    """PATCH /api/reviews/<pk>/  — update own review
    DELETE /api/reviews/<pk>/ — delete own review
    """
    queryset = Review.objects.select_related('customer', 'job')
    serializer_class = ReviewSerializer
    permission_classes = [permissions.IsAuthenticated, IsReviewOwner]
    lookup_url_kwarg = 'review_pk'

    def get_serializer_class(self):
        if self.request.method in ('PATCH', 'PUT'):
            return ReviewUpdateSerializer
        return ReviewSerializer

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)

        # Manually apply validated fields to the review
        validated = serializer.validated_data
        if 'rating' in validated:
            instance.rating = validated['rating']
        if 'comment' in validated:
            instance.comment = validated['comment']
        instance.save()
        # Signal will recalculate artisan rating

        # Return the full review data, not just the update fields
        output_serializer = ReviewSerializer(instance)
        return Response(output_serializer.data)

    def perform_destroy(self, instance):
        # Signal will recalculate artisan rating after deletion
        instance.delete()