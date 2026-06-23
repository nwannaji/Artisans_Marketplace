// lib/models/message.dart
import 'package:equatable/equatable.dart';

enum MessageType { text, voiceNote, location }

class ChatMessage extends Equatable {
  final int id;
  final int conversationId;
  final int senderId;
  final String? senderUsername;
  final String message;
  final MessageType messageType;
  final String? audioUrl;
  final double? audioDuration;
  final double? latitude;
  final double? longitude;
  final String locationLabel;
  final bool isAdminMessage;
  final DateTime timestamp;
  final bool isRead;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderUsername,
    required this.message,
    this.messageType = MessageType.text,
    this.audioUrl,
    this.audioDuration,
    this.latitude,
    this.longitude,
    this.locationLabel = '',
    this.isAdminMessage = false,
    required this.timestamp,
    this.isRead = false,
  });

  @override
  List<Object?> get props => [
    id, conversationId, senderId, senderUsername,
    message, messageType, audioUrl, audioDuration,
    latitude, longitude, locationLabel,
    isAdminMessage, timestamp, isRead,
  ];

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final messageTypeStr = json['message_type'] as String? ?? 'text';
    MessageType mt = MessageType.text;
    if (messageTypeStr == 'voice_note') mt = MessageType.voiceNote;
    if (messageTypeStr == 'location') mt = MessageType.location;

    return ChatMessage(
      id: json['id'] as int,
      conversationId: json['conversation'] as int,
      senderId: json['sender'] as int,
      senderUsername: json['sender_username'] as String?,
      message: json['message'] as String? ?? '',
      messageType: mt,
      audioUrl: json['audio_file_url'] as String?,
      audioDuration: json['audio_duration'] as double?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      locationLabel: json['location_label'] as String? ?? '',
      isAdminMessage: json['is_admin_message'] as bool? ?? false,
      timestamp: _parseDateTime(json['timestamp']) ?? DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
    };
  }

  /// Format duration as M:SS
  String get durationLabel {
    if (audioDuration == null) return '0:00';
    final minutes = (audioDuration! / 60).floor();
    final seconds = (audioDuration! % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}