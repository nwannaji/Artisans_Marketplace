// lib/models/notification.dart

import 'package:equatable/equatable.dart';

class AppNotification extends Equatable {
  final int id;
  final String notificationType;
  final String title;
  final String message;
  final String? relatedObjectType;
  final int? relatedObjectId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.notificationType,
    required this.title,
    required this.message,
    this.relatedObjectType,
    this.relatedObjectId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      notificationType: json['notification_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      relatedObjectType: json['related_object_type'] as String?,
      relatedObjectId: json['related_object_id'] as int?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'notification_type': notificationType,
      'title': title,
      'message': message,
      'related_object_type': relatedObjectType,
      'related_object_id': relatedObjectId,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AppNotification copyWith({
    int? id,
    String? notificationType,
    String? title,
    String? message,
    String? relatedObjectType,
    int? relatedObjectId,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      notificationType: notificationType ?? this.notificationType,
      title: title ?? this.title,
      message: message ?? this.message,
      relatedObjectType: relatedObjectType ?? this.relatedObjectType,
      relatedObjectId: relatedObjectId ?? this.relatedObjectId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        notificationType,
        title,
        message,
        relatedObjectType,
        relatedObjectId,
        isRead,
        createdAt,
      ];
}