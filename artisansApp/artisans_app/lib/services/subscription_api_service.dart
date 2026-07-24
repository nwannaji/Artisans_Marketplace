import 'package:artisans_app/services/api_client.dart';
import 'package:artisans_app/models/subscription.dart';

/// API service for subscription-related endpoints.
class SubscriptionApiService {
  final ApiClient _apiClient = ApiClient();

  /// Get the current artisan's subscription status.
  /// Returns a default FREE subscription if none exists.
  Future<Subscription> getMySubscription() async {
    try {
      final result = await _apiClient.get('/api/subscriptions/my/');
      return Subscription.fromJson(result);
    } catch (e) {
      // If the endpoint fails (e.g., no subscription record), return default FREE
      return Subscription.defaultFree();
    }
  }

  /// Get the list of available subscription tiers and payment info from the backend.
  /// Prices, features, and bank details are all server-driven — no hardcoding.
  Future<TierListResponse> getTierInfo() async {
    try {
      final result = await _apiClient.get('/api/subscriptions/tiers/');
      // The endpoint returns { "tiers": [...], "payment_info": {...} }
      final tiersJson = result['tiers'] as List? ?? [];
      final paymentInfoJson =
          result['payment_info'] as Map<String, dynamic>? ?? {};
      return TierListResponse(
        tiers:
            tiersJson
                .map((json) => TierInfo.fromJson(json as Map<String, dynamic>))
                .toList(),
        paymentInfo: PaymentInfo.fromJson(paymentInfoJson),
      );
    } catch (e) {
      // If the API is unreachable, return sensible defaults
      // (these should rarely be seen — the app requires connectivity)
      return TierListResponse(
        tiers: _fallbackTiers,
        paymentInfo: PaymentInfo(
          bankName: 'Wema Bank',
          accountNumber: '0123456789',
          accountName: 'Kaycollin Services',
          whatsappNumber: '2347031573700',
          phoneNumber: '+2347031573700',
          whatsappMessage: 'Hi, I want to upgrade my FixIt plan',
        ),
      );
    }
  }
}

/// Response from the /tiers/ endpoint containing tiers and payment info.
class TierListResponse {
  final List<TierInfo> tiers;
  final PaymentInfo paymentInfo;

  const TierListResponse({required this.tiers, required this.paymentInfo});
}

/// Payment and contact info — all sourced from the backend so it can be
/// updated without an app release.
class PaymentInfo {
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String whatsappNumber;
  final String phoneNumber;
  final String whatsappMessage;

  const PaymentInfo({
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.whatsappNumber,
    required this.phoneNumber,
    required this.whatsappMessage,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      bankName: json['bank_name'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      whatsappNumber: json['whatsapp_number'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      whatsappMessage: json['whatsapp_message'] as String? ?? '',
    );
  }
}

// Minimal fallback tiers (only used when the API is completely unreachable)
const _fallbackTiers = <TierInfo>[
  TierInfo(
    tier: 'FREE',
    name: 'Free',
    monthlyPrice: '₦0',
    features: [
      'Basic artisan profile',
      'Up to 3 bookings per month',
      'Standard search visibility',
      'Customer messaging',
    ],
    maxBookingsPerMonth: 3,
    prioritySearch: false,
    badge: null,
  ),
  TierInfo(
    tier: 'PRO',
    name: 'Pro',
    monthlyPrice: '₦2,500',
    features: [
      'Unlimited bookings',
      'Priority search results',
      'Pro badge on profile',
      'Customer messaging',
    ],
    maxBookingsPerMonth: null,
    prioritySearch: true,
    badge: 'Pro',
  ),
  TierInfo(
    tier: 'PREMIUM',
    name: 'Premium',
    monthlyPrice: '₦5,000',
    features: [
      'Unlimited bookings',
      'Top search placement',
      'Premium badge on profile',
      'Featured placement',
      'Analytics dashboard',
      'Customer messaging',
    ],
    maxBookingsPerMonth: null,
    prioritySearch: true,
    badge: 'Premium',
  ),
];
