// lib/models/dispute.dart
import 'package:equatable/equatable.dart';

enum DisputeStatus { open, inReview, resolved, closed }

enum DisputeReason { poorService, notCompleted, overCharging, other }

class Dispute extends Equatable {
  final int id;
  final int jobId;
  final DisputeReason reason;
  final String details;
  final DisputeStatus status;
  final String? resolution;
  final int? resolvedById;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const Dispute({
    required this.id,
    required this.jobId,
    required this.reason,
    required this.details,
    this.status = DisputeStatus.open,
    this.resolution,
    this.resolvedById,
    this.createdAt,
    this.resolvedAt,
  });

  @override
  List<Object?> get props => [
    id, jobId, reason, details, status, resolution,
    resolvedById, createdAt, resolvedAt,
  ];

  factory Dispute.fromJson(Map<String, dynamic> json) {
    return Dispute(
      id: json['id'] as int,
      jobId: (json['job_id'] ?? json['job']) as int,
      reason: _parseReason(json['reason'] as String?),
      details: json['details'] as String? ?? '',
      status: _parseStatus(json['status'] as String?),
      resolution: json['resolution'] as String?,
      resolvedById: (json['resolved_by_id'] ?? json['resolved_by']) as int?,
      createdAt: _parseDateTime(json['created_at']),
      resolvedAt: _parseDateTime(json['resolved_at']),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'job_id': jobId,
      'reason': _reasonToApi(reason),
      'details': details,
    };
  }

  static DisputeReason _parseReason(String? reason) {
    switch (reason) {
      case 'poor_service': return DisputeReason.poorService;
      case 'not_completed': return DisputeReason.notCompleted;
      case 'over_charging': return DisputeReason.overCharging;
      default: return DisputeReason.other;
    }
  }

  static String _reasonToApi(DisputeReason reason) {
    switch (reason) {
      case DisputeReason.poorService: return 'poor_service';
      case DisputeReason.notCompleted: return 'not_completed';
      case DisputeReason.overCharging: return 'over_charging';
      case DisputeReason.other: return 'other';
    }
  }

  static DisputeStatus _parseStatus(String? status) {
    switch (status) {
      case 'open': return DisputeStatus.open;
      case 'in_review': return DisputeStatus.inReview;
      case 'resolved': return DisputeStatus.resolved;
      case 'closed': return DisputeStatus.closed;
      default: return DisputeStatus.open;
    }
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}