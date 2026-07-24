// lib/models/conversation.dart
import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  final int id;
  final int clientId;
  final String? clientUsername;
  final int artisanId;
  final String? artisanUsername;
  final int? adminId;
  final int? relatedJobId;
  final String conversationType;
  final bool isActive;
  final int messageTtlDays;
  final DateTime? createdAt;
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;
  final bool otherUserOnline;

  const Conversation({
    required this.id,
    required this.clientId,
    this.clientUsername,
    required this.artisanId,
    this.artisanUsername,
    this.adminId,
    this.relatedJobId,
    this.conversationType = 'client_artisan',
    this.isActive = true,
    this.messageTtlDays = 14,
    this.createdAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.otherUserOnline = false,
  });

  /// Human-readable label for the TTL setting.
  String get ttlLabel {
    switch (messageTtlDays) {
      case 0:
        return 'Never expire';
      case 7:
        return '1 week';
      case 14:
        return '2 weeks';
      case 30:
        return '1 month';
      default:
        return '$messageTtlDays days';
    }
  }

  @override
  List<Object?> get props => [
    id, clientId, clientUsername, artisanId, artisanUsername,
    adminId, relatedJobId, conversationType, isActive, messageTtlDays,
    createdAt, lastMessage, unreadCount, otherUserOnline,
  ];

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as int,
      clientId: json['client'] as int,
      clientUsername: json['client_username'] as String?,
      artisanId: json['artisan'] as int,
      artisanUsername: json['artisan_username'] as String?,
      adminId: json['admin'] as int?,
      relatedJobId: json['related_job'] as int?,
      conversationType: json['conversation_type'] as String? ?? 'client_artisan',
      isActive: json['is_active'] as bool? ?? true,
      messageTtlDays: json['message_ttl_days'] as int? ?? 14,
      createdAt: _parseDateTime(json['created_at']),
      lastMessage: json['last_message'] as Map<String, dynamic>?,
      unreadCount: json['unread_count'] as int? ?? 0,
      otherUserOnline: json['other_user_online'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'client': clientId,
      'artisan': artisanId,
      'related_job': relatedJobId,
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}