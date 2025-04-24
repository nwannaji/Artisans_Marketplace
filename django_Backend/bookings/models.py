from django.db import models
from accounts.models import User, ArtisanProfile
from django.core.validators import MinValueValidator, MaxValueValidator

class Job(models.Model):
    class Status(models.TextChoices):
        SCHEDULED = 'SCHEDULED', 'Scheduled'
        IN_PROGRESS = 'IN_PROGRESS', 'In Progress'
        COMPLETED = 'COMPLETED', 'Completed'
        CANCELLED = 'CANCELLED', 'Cancelled'
        DISPUTED = 'DISPUTED', 'Disputed'
    
    customer = models.ForeignKey(
        User, 
        on_delete=models.CASCADE, 
        related_name='customer_jobs',
        limit_choices_to={'role': User.Role.CUSTOMER}
    )
    artisan = models.ForeignKey(
        ArtisanProfile, 
        on_delete=models.CASCADE, 
        related_name='artisan_jobs'
    )
    description = models.TextField()
    scheduled_time = models.DateTimeField()
    agreed_price = models.DecimalField(max_digits=10, decimal_places=2)
    location = models.CharField(max_length=255)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, blank=True, null=True)
    status = models.CharField(
        max_length=20, 
        choices=Status.choices, 
        default=Status.SCHEDULED
    )
    rating = models.FloatField(
        blank=True, 
        null=True,
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    review = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"Job #{self.id} - {self.artisan.user.username} for {self.customer.username}"