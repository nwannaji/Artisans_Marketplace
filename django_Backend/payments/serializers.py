from rest_framework import serializers
from .models import Wallet, Transaction, AppSettings
from accounts.models import User
from bookings.models import Job

class WalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = Wallet
        fields = ['user', 'balance', 'created_at', 'updated_at']

class TransactionSerializer(serializers.ModelSerializer):
    wallet = WalletSerializer(read_only=True)
    job_id = serializers.PrimaryKeyRelatedField(queryset=Job.objects.all(), source='job')

    class Meta:
        model = Transaction
        fields = ['wallet', 'amount', 'transaction_type', 'status', 'reference', 'job_id', 'description', 'created_at']

    def create(self, validated_data):
        # Here you can add logic to process the transaction (e.g., deducting from the wallet, etc.)
        return Transaction.objects.create(**validated_data)

    def update(self, instance, validated_data):
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        return instance

class AppSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = AppSettings
        fields = ['key', 'value']
