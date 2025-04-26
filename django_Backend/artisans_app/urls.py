from django.urls import path
from .views import ArtisanListAPIView, ArtisanDetailAPIView, ArtisanProfileUpdateAPIView, ArtisanProfileCreateAPIView

app_name = 'artisans_app'

urlpatterns = [
    path('', ArtisanListAPIView.as_view(), name='list'), 
    path('create/', ArtisanProfileCreateAPIView.as_view(), name='create'),
    path('<int:pk>/', ArtisanDetailAPIView.as_view(), name='detail'),
    path('<int:pk>/verify/', ArtisanProfileUpdateAPIView.as_view(), name='verify'),
]
