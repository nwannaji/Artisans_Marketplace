from django.db import migrations


def set_verified_artisans_available(apps, schema_editor):
    """Set is_available='AVAILABLE' for all verified artisans with a profession set,
    so existing data isn't hidden as OFFLINE."""
    ArtisanProfile = apps.get_model('accounts', 'ArtisanProfile')
    ArtisanProfile.objects.filter(
        is_verified=True,
        profession__isnull=False,
    ).exclude(
        profession=''
    ).update(is_available='AVAILABLE')


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0005_artisanprofile_is_available'),
    ]

    operations = [
        migrations.RunPython(
            set_verified_artisans_available,
            reverse_code=migrations.RunPython.noop,
        ),
    ]