// lib/services/chat_api_service.dart

import 'dart:io';

import '../models/conversation.dart';
import '../models/message.dart';
import 'api_client.dart';

class ChatApiService {
  final ApiClient _apiClient = ApiClient();

  /// List conversations for the current user
  Future<List<Conversation>> listConversations() async {
    final result = await _apiClient.getList('/api/chats/conversations/');
    return result.map((json) => Conversation.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Create a new conversation
  Future<Conversation> createConversation({
    required int clientId,
    required int artisanId,
    int? relatedJobId,
  }) async {
    final body = <String, dynamic>{
      'client': clientId,
      'artisan': artisanId,
    };
    if (relatedJobId != null) body['related_job'] = relatedJobId;

    final result = await _apiClient.post('/api/chats/conversations/', body: body);
    return Conversation.fromJson(result);
  }

  /// Get a single conversation
  Future<Conversation> getConversation(int id) async {
    final result = await _apiClient.get('/api/chats/conversations/$id/');
    return Conversation.fromJson(result);
  }

  /// Get messages for a conversation
  Future<List<ChatMessage>> getMessages(int conversationId) async {
    final result = await _apiClient.getList('/api/chats/conversations/$conversationId/messages/');
    return result.map((json) => ChatMessage.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Send a text message in a conversation
  Future<ChatMessage> sendMessage(int conversationId, String message) async {
    final result = await _apiClient.post(
      '/api/chats/conversations/$conversationId/messages/',
      body: {'message': message},
    );
    return ChatMessage.fromJson(result);
  }

  /// Send a voice note message in a conversation
  Future<ChatMessage> sendVoiceNote(int conversationId, File audioFile, {double? duration}) async {
    final fields = <String, String>{
      'message': '🎤 Voice note',
      'message_type': 'voice_note',
    };
    if (duration != null) {
      fields['audio_duration'] = duration.toString();
    }

    final result = await _apiClient.uploadFile(
      '/api/chats/conversations/$conversationId/messages/',
      file: audioFile,
      fieldName: 'audio_file',
      fields: fields,
    );
    return ChatMessage.fromJson(result);
  }

  /// Share a location in a conversation
  Future<ChatMessage> sendLocation(int conversationId, {
    required double latitude,
    required double longitude,
    String label = '',
  }) async {
    final result = await _apiClient.post(
      '/api/chats/conversations/$conversationId/messages/',
      body: {
        'message': label.isNotEmpty ? '📍 $label' : '📍 Shared location',
        'message_type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'location_label': label,
      },
    );
    return ChatMessage.fromJson(result);
  }

  /// Admin: list all conversations
  Future<List<Conversation>> adminListConversations() async {
    final result = await _apiClient.getList('/api/chats/admin/conversations/');
    return result.map((json) => Conversation.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Admin: send a message in any conversation
  Future<ChatMessage> adminSendMessage(int conversationId, String message) async {
    final result = await _apiClient.post(
      '/api/chats/admin/conversations/$conversationId/messages/',
      body: {'message': message},
    );
    return ChatMessage.fromJson(result);
  }
}