// lib/models/job.dart
import 'package:equatable/equatable.dart';

enum JobStatus {
  pending,
  adminApproved,
  accepted,
  inProgress,
  awaitingReview,
  completed,
  cancelled,
  disputed,
  rejected;

  String get label {
    switch (this) {
      case JobStatus.pending: return 'Pending';
      case JobStatus.adminApproved: return 'Admin Approved';
      case JobStatus.accepted: return 'Accepted';
      case JobStatus.inProgress: return 'In Progress';
      case JobStatus.awaitingReview: return 'Awaiting Review';
      case JobStatus.completed: return 'Completed';
      case JobStatus.cancelled: return 'Cancelled';
      case JobStatus.disputed: return 'Disputed';
      case JobStatus.rejected: return 'Rejected';
    }
  }

  static JobStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING': return JobStatus.pending;
      case 'ADMIN_APPROVED': return JobStatus.adminApproved;
      case 'ACCEPTED': return JobStatus.accepted;
      case 'IN_PROGRESS': return JobStatus.inProgress;
      case 'AWAITING_REVIEW': return JobStatus.awaitingReview;
      case 'COMPLETED': return JobStatus.completed;
      case 'CANCELLED': return JobStatus.cancelled;
      case 'DISPUTED': return JobStatus.disputed;
      case 'REJECTED': return JobStatus.rejected;
      default: return JobStatus.pending;
    }
  }

  String toApiString() {
    switch (this) {
      case JobStatus.pending: return 'PENDING';
      case JobStatus.adminApproved: return 'ADMIN_APPROVED';
      case JobStatus.accepted: return 'ACCEPTED';
      case JobStatus.inProgress: return 'IN_PROGRESS';
      case JobStatus.awaitingReview: return 'AWAITING_REVIEW';
      case JobStatus.completed: return 'COMPLETED';
      case JobStatus.cancelled: return 'CANCELLED';
      case JobStatus.disputed: return 'DISPUTED';
      case JobStatus.rejected: return 'REJECTED';
    }
  }
}

class Job extends Equatable {
  final int id;
  final int customerId;
  final String? customerUsername;
  final int? artisanId;
  final String? artisanUsername;
  final String description;
  final DateTime? scheduledTime;
  final double agreedPrice;
  final String? location;
  final double? latitude;
  final double? longitude;
  final JobStatus status;
  final int? adminApprovedBy;
  final DateTime? adminApprovedAt;
  final double? rating;
  final String? review;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Job({
    required this.id,
    required this.customerId,
    this.customerUsername,
    this.artisanId,
    this.artisanUsername,
    required this.description,
    this.scheduledTime,
    required this.agreedPrice,
    this.location,
    this.latitude,
    this.longitude,
    required this.status,
    this.adminApprovedBy,
    this.adminApprovedAt,
    this.rating,
    this.review,
    this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [
    id, customerId, customerUsername, artisanId, artisanUsername,
    description, scheduledTime, agreedPrice, location, latitude, longitude,
    status, adminApprovedBy, adminApprovedAt,
    rating, review, createdAt,
  ];

  Job copyWith({
    int? id,
    int? customerId,
    String? customerUsername,
    int? artisanId,
    String? artisanUsername,
    String? description,
    DateTime? scheduledTime,
    double? agreedPrice,
    String? location,
    double? latitude,
    double? longitude,
    JobStatus? status,
    int? adminApprovedBy,
    DateTime? adminApprovedAt,
    double? rating,
    String? review,
    DateTime? createdAt,
  }) {
    return Job(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerUsername: customerUsername ?? this.customerUsername,
      artisanId: artisanId ?? this.artisanId,
      artisanUsername: artisanUsername ?? this.artisanUsername,
      description: description ?? this.description,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      agreedPrice: agreedPrice ?? this.agreedPrice,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      adminApprovedBy: adminApprovedBy ?? this.adminApprovedBy,
      adminApprovedAt: adminApprovedAt ?? this.adminApprovedAt,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] as int,
      customerId: json['customer'] as int,
      customerUsername: json['customer_username'] as String?,
      artisanId: json['artisan'] as int?,
      artisanUsername: json['artisan_username'] as String?,
      description: json['description'] as String? ?? '',
      scheduledTime: _parseDateTime(json['scheduled_time']),
      agreedPrice: _parseDouble(json['agreed_price']) ?? 0.0,
      location: json['location'] as String?,
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      status: JobStatus.fromString(json['status'] as String?),
      adminApprovedBy: json['admin_approved_by'] as int?,
      adminApprovedAt: _parseDateTime(json['admin_approved_at']),
      rating: _parseDouble(json['rating']),
      review: json['review'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  /// Serialize for creating a new job (POST /api/bookings/)
  Map<String, dynamic> toCreateJson() {
    return {
      'description': description,
      'scheduled_time': scheduledTime?.toIso8601String(),
      'agreed_price': agreedPrice,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
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