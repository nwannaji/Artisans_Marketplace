// lib/models/review.dart
import 'package:equatable/equatable.dart';

/// Represents a single review/rating left by a customer for an artisan.
/// Fetched from GET /api/artisans/{pk}/reviews/
class Review extends Equatable {
  final int id;
  final int? artisan;
  final int? customer;
  final String customerName;
  final double rating;
  final String? comment;
  final String? review; // Kept for backward compat with old job-based reviews
  final bool hasJobContext;
  final String? jobDescription;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Review({
    required this.id,
    this.artisan,
    this.customer,
    required this.customerName,
    required this.rating,
    this.comment,
    this.review,
    this.hasJobContext = false,
    this.jobDescription,
    this.createdAt,
    this.updatedAt,
  });

  /// Convenience getter: prefer comment, fall back to review for backward compat
  String? get displayComment => comment ?? review;

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as int,
      artisan: json['artisan'] as int?,
      customer: json['customer'] as int?,
      customerName: json['customer_name'] as String? ?? 'Anonymous',
      rating: _parseDouble(json['rating']) ?? 0.0,
      comment: json['comment'] as String?,
      review: json['review'] as String?,
      hasJobContext: json['has_job_context'] as bool? ?? false,
      jobDescription: json['job_description'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (artisan != null) 'artisan': artisan,
      if (customer != null) 'customer': customer,
      'customer_name': customerName,
      'rating': rating,
      if (comment != null) 'comment': comment,
      if (review != null) 'review': review,
      if (hasJobContext) 'has_job_context': hasJobContext,
      if (jobDescription != null) 'job_description': jobDescription,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, customerName, rating, comment, review, hasJobContext, jobDescription, createdAt, updatedAt];

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