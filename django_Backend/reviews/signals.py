from django.db.models import Avg, Count
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import Review


def recalculate_artisan_rating(artisan):
    """Recalculate an ArtisanProfile's aggregate rating from all Reviews."""
    if artisan is None:
        return
    agg = Review.objects.filter(artisan=artisan).aggregate(
        avg_rating=Avg('rating'),
        review_count=Count('id'),
    )
    artisan.rating = round(agg['avg_rating'] or 0, 1)
    artisan.save(update_fields=['rating'])


@receiver(post_save, sender=Review)
def on_review_saved(sender, instance, **kwargs):
    recalculate_artisan_rating(instance.artisan)


@receiver(post_delete, sender=Review)
def on_review_deleted(sender, instance, **kwargs):
    recalculate_artisan_rating(instance.artisan)