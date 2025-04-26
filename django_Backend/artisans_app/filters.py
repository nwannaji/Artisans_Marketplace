# apps/artisans/filters.py
import django_filters
from accounts.models import ArtisanProfile

class ArtisanFilter(django_filters.FilterSet):
    min_rating = django_filters.NumberFilter(field_name='rating', lookup_expr='gte')
    max_rating = django_filters.NumberFilter(field_name='rating', lookup_expr='lte')
    min_rate = django_filters.NumberFilter(field_name='hourly_rate', lookup_expr='gte')
    max_rate = django_filters.NumberFilter(field_name='hourly_rate', lookup_expr='lte')
    profession = django_filters.CharFilter(field_name='profession', lookup_expr='icontains')
    location = django_filters.CharFilter(field_name='location', lookup_expr='icontains')
    
    class Meta:
        model = ArtisanProfile
        fields = {
            'profession': ['exact'],
            'location': ['exact'],
            'rating': ['gte', 'lte'],
            'hourly_rate': ['gte', 'lte'],
        }