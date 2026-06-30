// lib/models/review.dart
import 'package:equatable/equatable.dart';

/// Represents a single review/rating left by a customer for an artisan.
/// Fetched from GET /api/artisans/{pk}/reviews/
class Review extends Equatable {
  final int id;
  final String customerName;
  final double rating;
  final String? review;
  final String? description;
  final DateTime? createdAt;

  const Review({
    required this.id,
    required this.customerName,
    required this.rating,
    this.review,
    this.description,
    this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as int,
      customerName: json['customer_name'] as String? ?? 'Anonymous',
      rating: _parseDouble(json['rating']) ?? 0.0,
      review: json['review'] as String?,
      description: json['description'] as String?,
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  /// Rating distribution summary returned alongside reviews.
  factory Review.summaryFromJson(Map<String, dynamic> json) {
    // This factory isn't for Review objects; use RatingSummary.fromJson instead.
    throw UnsupportedError('Use RatingSummary.fromJson for summary data');
  }

  @override
  List<Object?> get props => [id, customerName, rating, review, description, createdAt];

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Aggregate rating summary for an artisan.
class RatingSummary extends Equatable {
  final double averageRating;
  final int totalReviews;
  final Map<int, int> ratingDistribution; // {5: 15, 4: 5, 3: 2, 2: 1, 1: 0}

  const RatingSummary({
    required this.averageRating,
    required this.totalReviews,
    required this.ratingDistribution,
  });

  factory RatingSummary.fromJson(Map<String, dynamic> json) {
    final distRaw = json['rating_distribution'] as Map<String, dynamic>? ?? {};
    final distribution = <int, int>{};
    for (final entry in distRaw.entries) {
      distribution[int.parse(entry.key)] = entry.value as int;
    }

    return RatingSummary(
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      ratingDistribution: distribution,
    );
  }

  @override
  List<Object?> get props => [averageRating, totalReviews, ratingDistribution];
}