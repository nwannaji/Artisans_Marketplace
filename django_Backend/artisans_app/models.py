from django.db import models
from accounts.models import User
from django.core.validators import MinValueValidator, MaxValueValidator

class ArtisanProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='artisan_profile')
    profession = models.CharField(max_length=100)
    bio = models.TextField(blank=True, null=True)
    rating = models.FloatField(default=0.0, validators=[MinValueValidator(0), MaxValueValidator(5)])
    jobs_completed = models.PositiveIntegerField(default=0)
    location = models.CharField(max_length=255)
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2)
    skills = models.JSONField(default=list)
    certificates = models.JSONField(default=list)  # Stores paths to certificate files
    bank_account = models.CharField(max_length=50)
    bank_name = models.CharField(max_length=100)
    is_verified = models.BooleanField(default=False)
    verification_documents = models.JSONField(default=list)  # Stores paths to verification docs
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"{self.user.username} - {self.profession}"