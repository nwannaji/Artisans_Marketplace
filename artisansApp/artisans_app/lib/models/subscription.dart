/// Subscription tier enum and model for artisan subscriptions.
/// No in-app payments — admin manually activates after offline payment.
enum SubscriptionTier { free, pro, premium }

class Subscription {
  final int? id;
  final int artisanId;
  final String artisanUsername;
  final SubscriptionTier tier;
  final SubscriptionTier effectiveTier;
  final bool isActive;
  final DateTime? expiresAt;
  final String? notes;

  const Subscription({
    this.id,
    required this.artisanId,
    required this.artisanUsername,
    required this.tier,
    required this.effectiveTier,
    required this.isActive,
    this.expiresAt,
    this.notes,
  });

  // Convenience getters
  bool get isFree => effectiveTier == SubscriptionTier.free;
  bool get isPro => effectiveTier == SubscriptionTier.pro;
  bool get isPremium => effectiveTier == SubscriptionTier.premium;

  String get tierLabel {
    switch (effectiveTier) {
      case SubscriptionTier.pro:
        return 'Pro';
      case SubscriptionTier.premium:
        return 'Premium';
      case SubscriptionTier.free:
        return 'Free';
    }
  }

  String? get badge {
    switch (effectiveTier) {
      case SubscriptionTier.pro:
        return 'Pro';
      case SubscriptionTier.premium:
        return 'Premium';
      case SubscriptionTier.free:
        return null;
    }
  }

  /// Maximum bookings per month. null = unlimited.
  int? get maxBookingsPerMonth {
    switch (effectiveTier) {
      case SubscriptionTier.free:
        return 3;
      case SubscriptionTier.pro:
      case SubscriptionTier.premium:
        return null; // unlimited
    }
  }

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as int?,
      artisanId: json['artisan'] as int? ?? 0,
      artisanUsername: json['artisan_username'] as String? ?? '',
      tier: _parseTier(json['tier'] as String? ?? 'FREE'),
      effectiveTier: _parseTier(json['effective_tier'] as String? ?? 'FREE'),
      isActive: json['is_active'] as bool? ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }

  /// Factory for the default FREE response (when no subscription exists)
  factory Subscription.defaultFree({int artisanId = 0, String artisanUsername = '', int currentMonthBookings = 0}) {
    return Subscription(
      tier: SubscriptionTier.free,
      effectiveTier: SubscriptionTier.free,
      isActive: false,
      artisanId: artisanId,
      artisanUsername: artisanUsername,
    );
  }

  static SubscriptionTier _parseTier(String tier) {
    switch (tier.toUpperCase()) {
      case 'PRO':
        return SubscriptionTier.pro;
      case 'PREMIUM':
        return SubscriptionTier.premium;
      default:
        return SubscriptionTier.free;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'artisan': artisanId,
      'artisan_username': artisanUsername,
      'tier': tier.name.toUpperCase(),
      'effective_tier': effectiveTier.name.toUpperCase(),
      'is_active': isActive,
      'expires_at': expiresAt?.toIso8601String(),
      'notes': notes,
    };
  }

  Subscription copyWith({
    int? id,
    int? artisanId,
    String? artisanUsername,
    SubscriptionTier? tier,
    SubscriptionTier? effectiveTier,
    bool? isActive,
    DateTime? expiresAt,
    String? notes,
  }) {
    return Subscription(
      id: id ?? this.id,
      artisanId: artisanId ?? this.artisanId,
      artisanUsername: artisanUsername ?? this.artisanUsername,
      tier: tier ?? this.tier,
      effectiveTier: effectiveTier ?? this.effectiveTier,
      isActive: isActive ?? this.isActive,
      expiresAt: expiresAt ?? this.expiresAt,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() => 'Subscription($tierLabel, active=$isActive)';
}

/// Tier info for the public plans/pricing screen.
class TierInfo {
  final String tier;
  final String name;
  final String monthlyPrice;
  final List<String> features;
  final int? maxBookingsPerMonth;
  final bool prioritySearch;
  final String? badge;

  const TierInfo({
    required this.tier,
    required this.name,
    required this.monthlyPrice,
    required this.features,
    this.maxBookingsPerMonth,
    required this.prioritySearch,
    this.badge,
  });

  factory TierInfo.fromJson(Map<String, dynamic> json) {
    return TierInfo(
      tier: json['tier'] as String,
      name: json['name'] as String,
      monthlyPrice: json['monthly_price'] as String,
      features: (json['features'] as List).cast<String>(),
      maxBookingsPerMonth: json['max_bookings_per_month'] as int?,
      prioritySearch: json['priority_search'] as bool,
      badge: json['badge'] as String?,
    );
  }
}