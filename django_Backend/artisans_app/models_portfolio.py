from django.db import models
from accounts.models import User


class PortfolioImage(models.Model):
    artisan = models.ForeignKey('accounts.User', on_delete=models.CASCADE, related_name='portfolio_images')
    image = models.ImageField(upload_to='portfolio/%Y/%m/', help_text='Portfolio image')
    caption = models.CharField(max_length=255, blank=True, help_text='Optional caption for the image')
    order = models.PositiveIntegerField(default=0, help_text='Display order (lower numbers appear first)')
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['order', 'uploaded_at']
        verbose_name = 'Portfolio Image'
        verbose_name_plural = 'Portfolio Images'

    def __str__(self):
        return f"Portfolio image for {self.artisan.username} - {self.caption or 'Untitled'}"