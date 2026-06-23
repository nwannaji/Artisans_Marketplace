// lib/models/artisan.dart
import 'package:equatable/equatable.dart';

class Artisan extends Equatable {
  final int id;
  final int userId;
  final String? username;
  final String? profilePicture;
  final String? bio;
  final String? profession;
  final List<dynamic> skills;
  final double? hourlyRate;
  final double rating;
  final int jobsCompleted;
  final String? location;
  final double? latitude;
  final double? longitude;
  final List<dynamic> verificationDocuments;
  final bool isVerified;
  final bool userIsActive; // Whether the user account is activated
  final String isAvailable; // 'AVAILABLE', 'BUSY', 'ENGAGED', 'OFFLINE'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Fields populated only from nearby search response
  final double? distanceKm;
  final int? estimatedArrivalMinutes;
  final int reviewCount;

  const Artisan({
    required this.id,
    required this.userId,
    this.username,
    this.profilePicture,
    this.bio,
    this.profession,
    this.skills = const [],
    this.hourlyRate,
    this.rating = 0.0,
    this.jobsCompleted = 0,
    this.location,
    this.latitude,
    this.longitude,
    this.verificationDocuments = const [],
    this.isVerified = false,
    this.userIsActive = true,
    this.isAvailable = 'OFFLINE',
    this.createdAt,
    this.updatedAt,
    this.distanceKm,
    this.estimatedArrivalMinutes,
    this.reviewCount = 0,
  });

  String get fullName => username ?? 'Unknown';

  bool get isAvailableNow => isAvailable == 'AVAILABLE';

  String get availabilityLabel {
    switch (isAvailable) {
      case 'AVAILABLE':
        return 'Available';
      case 'BUSY':
        return 'Busy';
      case 'ENGAGED':
        return 'Engaged';
      case 'OFFLINE':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  bool get isEngaged => isAvailable == 'ENGAGED';

  @override
  List<Object?> get props => [
    id, userId, username, profilePicture, bio, profession,
    skills, hourlyRate, rating, jobsCompleted, location,
    latitude, longitude, verificationDocuments, isVerified,
    userIsActive, isAvailable, distanceKm, estimatedArrivalMinutes, reviewCount,
  ];

  Artisan copyWith({
    int? id,
    int? userId,
    String? username,
    String? profilePicture,
    String? bio,
    String? profession,
    List<dynamic>? skills,
    double? hourlyRate,
    double? rating,
    int? jobsCompleted,
    String? location,
    double? latitude,
    double? longitude,
    List<dynamic>? verificationDocuments,
    bool? isVerified,
    bool? userIsActive,
    String? isAvailable,
    double? distanceKm,
    int? estimatedArrivalMinutes,
    int? reviewCount,
  }) {
    return Artisan(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      profilePicture: profilePicture ?? this.profilePicture,
      bio: bio ?? this.bio,
      profession: profession ?? this.profession,
      skills: skills ?? this.skills,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      rating: rating ?? this.rating,
      jobsCompleted: jobsCompleted ?? this.jobsCompleted,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      verificationDocuments: verificationDocuments ?? this.verificationDocuments,
      isVerified: isVerified ?? this.isVerified,
      userIsActive: userIsActive ?? this.userIsActive,
      isAvailable: isAvailable ?? this.isAvailable,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedArrivalMinutes: estimatedArrivalMinutes ?? this.estimatedArrivalMinutes,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }

  factory Artisan.fromJson(Map<String, dynamic> json) {
    return Artisan(
      id: json['id'] as int,
      userId: json['user'] as int,
      username: json['user_username'] as String?,
      profilePicture: json['profile_picture'] as String?,
      bio: json['bio'] as String?,
      profession: json['profession'] as String?,
      skills: json['skills'] as List<dynamic>? ?? [],
      hourlyRate: _parseDouble(json['hourly_rate']),
      rating: _parseDouble(json['rating']) ?? 0.0,
      jobsCompleted: json['jobs_completed'] as int? ?? 0,
      location: json['location'] as String?,
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      verificationDocuments: json['verification_documents'] as List<dynamic>? ?? [],
      isVerified: json['is_verified'] as bool? ?? false,
      userIsActive: json['user_is_active'] as bool? ?? true,
      isAvailable: json['is_available'] as String? ?? 'OFFLINE',
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      // Nearby search extra fields
      distanceKm: _parseDouble(json['distance_km']),
      estimatedArrivalMinutes: json['estimated_arrival_minutes'] as int?,
      reviewCount: json['review_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession': profession,
      'skills': skills,
      'hourly_rate': hourlyRate,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'bio': bio,
      'is_available': isAvailable,
    };
  }

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