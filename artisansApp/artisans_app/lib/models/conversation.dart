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
  final DateTime? createdAt;
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;

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
    this.createdAt,
    this.lastMessage,
    this.unreadCount = 0,
  });

  @override
  List<Object?> get props => [
    id, clientId, clientUsername, artisanId, artisanUsername,
    adminId, relatedJobId, conversationType, isActive, createdAt, lastMessage,
    unreadCount,
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
      createdAt: _parseDateTime(json['created_at']),
      lastMessage: json['last_message'] as Map<String, dynamic>?,
      unreadCount: json['unread_count'] as int? ?? 0,
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