from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0004_alter_user_managers_alter_artisanprofile_hourly_rate_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='artisanprofile',
            name='is_available',
            field=models.CharField(
                default='OFFLINE',
                help_text="Artisan's current availability status",
                max_length=10,
                choices=[
                    ('AVAILABLE', 'Available'),
                    ('BUSY', 'Busy'),
                    ('OFFLINE', 'Offline'),
                ],
            ),
        ),
    ]