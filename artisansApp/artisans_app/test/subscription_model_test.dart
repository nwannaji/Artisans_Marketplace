// Unit tests for Subscription model and PaymentInfo
import 'package:flutter_test/flutter_test.dart';
import 'package:artisans_app/models/subscription.dart';
import 'package:artisans_app/services/subscription_api_service.dart';

void main() {
  group('Subscription', () {
    test('defaultFree creates a FREE tier subscription', () {
      final sub = Subscription.defaultFree();

      expect(sub.tier, SubscriptionTier.free);
      expect(sub.effectiveTier, SubscriptionTier.free);
      expect(sub.isActive, false);
      expect(sub.isFree, true);
      expect(sub.maxBookingsPerMonth, 3);
    });

    test('fromJson creates subscription from API response', () {
      final json = {
        'id': 1,
        'artisan': 5,
        'artisan_username': 'test_artisan',
        'tier': 'PRO',
        'effective_tier': 'PRO',
        'is_active': true,
        'expires_at': '2025-12-31T23:59:59Z',
        'notes': null,
      };

      final sub = Subscription.fromJson(json);

      expect(sub.tier, SubscriptionTier.pro);
      expect(sub.effectiveTier, SubscriptionTier.pro);
      expect(sub.isActive, true);
      expect(sub.artisanId, 5);
      expect(sub.artisanUsername, 'test_artisan');
      expect(sub.isPro, true);
    });

    test('fromJson handles missing optional fields with defaults', () {
      final json = {
        'id': 2,
        'tier': 'FREE',
        'effective_tier': 'FREE',
        'is_active': false,
      };

      final sub = Subscription.fromJson(json);

      expect(sub.tier, SubscriptionTier.free);
      expect(sub.effectiveTier, SubscriptionTier.free);
      expect(sub.isActive, false);
      expect(sub.isFree, true);
    });

    test('toJson produces correct API format', () {
      final sub = Subscription(
        id: 1,
        artisanId: 5,
        artisanUsername: 'test_artisan',
        tier: SubscriptionTier.pro,
        effectiveTier: SubscriptionTier.pro,
        isActive: true,
      );

      final json = sub.toJson();

      expect(json['artisan'], 5);
      expect(json['tier'], 'PRO');
      expect(json['effective_tier'], 'PRO');
      expect(json['is_active'], true);
    });

    test('tierLabel returns correct display name', () {
      expect(Subscription.defaultFree().tierLabel, 'Free');

      final proSub = Subscription(
        artisanId: 1,
        artisanUsername: 'a',
        tier: SubscriptionTier.pro,
        effectiveTier: SubscriptionTier.pro,
        isActive: true,
      );
      expect(proSub.tierLabel, 'Pro');

      final premiumSub = Subscription(
        artisanId: 1,
        artisanUsername: 'a',
        tier: SubscriptionTier.premium,
        effectiveTier: SubscriptionTier.premium,
        isActive: true,
      );
      expect(premiumSub.tierLabel, 'Premium');
    });

    test('badge returns correct value for each tier', () {
      expect(Subscription.defaultFree().badge, isNull);

      final proSub = Subscription(
        artisanId: 1,
        artisanUsername: 'a',
        tier: SubscriptionTier.pro,
        effectiveTier: SubscriptionTier.pro,
        isActive: true,
      );
      expect(proSub.badge, 'Pro');

      final premiumSub = Subscription(
        artisanId: 1,
        artisanUsername: 'a',
        tier: SubscriptionTier.premium,
        effectiveTier: SubscriptionTier.premium,
        isActive: true,
      );
      expect(premiumSub.badge, 'Premium');
    });
  });

  group('TierInfo', () {
    test('fromJson creates tier info from API response', () {
      final json = {
        'tier': 'PREMIUM',
        'name': 'Premium',
        'monthly_price': '₦5,000',
        'features': ['Unlimited bookings', 'Top search placement'],
        'max_bookings_per_month': null,
        'priority_search': true,
        'badge': 'Premium',
      };

      final tier = TierInfo.fromJson(json);

      expect(tier.tier, 'PREMIUM');
      expect(tier.name, 'Premium');
      expect(tier.monthlyPrice, '₦5,000');
      expect(tier.features.length, 2);
      expect(tier.prioritySearch, true);
    });
  });

  group('PaymentInfo', () {
    test('fromJson creates payment info with all fields', () {
      final json = {
        'bank_name': 'Wema Bank',
        'account_number': '0123456789',
        'account_name': 'Kaycollin Services',
        'whatsapp_number': '2347031573700',
        'phone_number': '+2347031573700',
        'whatsapp_message': 'Hi, I want to upgrade my FixIt plan',
      };

      // Import the service that contains PaymentInfo
      final info = PaymentInfo.fromJson(json);

      expect(info.bankName, 'Wema Bank');
      expect(info.accountNumber, '0123456789');
      expect(info.accountName, 'Kaycollin Services');
    });

    test('fromJson handles missing fields with empty string defaults', () {
      final json = <String, dynamic>{};

      final info = PaymentInfo.fromJson(json);

      expect(info.bankName, '');
      expect(info.accountNumber, '');
      expect(info.accountName, '');
    });
  });
}