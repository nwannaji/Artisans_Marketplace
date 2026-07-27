from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0010_user_last_active'),
    ]

    operations = [
        migrations.AddField(
            model_name='otpverification',
            name='attempts',
            field=models.PositiveIntegerField(default=0, help_text='Number of failed verification attempts. Locked after 5 failures.'),
        ),
    ]