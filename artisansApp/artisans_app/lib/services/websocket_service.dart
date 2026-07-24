// lib/services/websocket_service.dart
//
// WebSocket service for real-time chat messaging.
// Manages connection lifecycle, JWT authentication, automatic reconnection
// with exponential backoff, heartbeat keep-alive, and message routing.
//
// Falls back gracefully — if WebSocket is unavailable, the app continues
// to use REST polling via ChatApiService.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'token_service.dart';

/// Connection state of the WebSocket.
enum WebSocketState { disconnected, connecting, connected }

/// Singleton service that manages a single WebSocket connection to the chat server.
///
/// Usage:
///   final ws = WebSocketService();
///   ws.connect();
///   ws.messages.listen((data) => ...);
///   ws.joinConversation(conversationId);
///   ws.sendChatMessage(conversationId, 'Hello!');
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final TokenService _tokenService = TokenService();

  WebSocketChannel? _channel;
  WebSocketState _state = WebSocketState.disconnected;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // Stream controllers for different message types
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<int> _onlineStatusController =
      StreamController<int>.broadcast();
  final StreamController<int> _offlineStatusController =
      StreamController<int>.broadcast();
  final StreamController<WebSocketState> _connectionStateController =
      StreamController<WebSocketState>.broadcast();

  // ── Public API ─────────────────────────────────────────────

  /// Stream of incoming chat messages (serialized ChatMessage data).
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Stream of typing indicators: {user_id, username, conversation_id}.
  Stream<Map<String, dynamic>> get typing => _typingController.stream;

  /// Stream of read receipts: {conversation_id, reader_id}.
  Stream<Map<String, dynamic>> get readReceipts => _readReceiptController.stream;

  /// Stream of user IDs that came online.
  Stream<int> get onlineStatus => _onlineStatusController.stream;

  /// Stream of user IDs that went offline.
  Stream<int> get offlineStatus => _offlineStatusController.stream;

  /// Stream of connection state changes.
  Stream<WebSocketState> get connectionState => _connectionStateController.stream;

  /// Current connection state.
  WebSocketState get state => _state;

  /// Whether the WebSocket is currently connected.
  bool get isConnected => _state == WebSocketState.connected;

  // ── Connection Management ──────────────────────────────────

  /// Connect to the WebSocket server with JWT authentication.
  Future<void> connect() async {
    if (_state == WebSocketState.connected || _state == WebSocketState.connecting) {
      return;
    }

    _state = WebSocketState.connecting;
    _connectionStateController.add(_state);

    try {
      final token = await _tokenService.getAccessToken();
      if (token == null) {
        _state = WebSocketState.disconnected;
        _connectionStateController.add(_state);
        return;
      }

      final wsBaseUrl = dotenv.env['WS_BASE_URL'] ?? 'ws://10.0.2.2:8000/ws/chat/';
      final uri = Uri.parse('$wsBaseUrl?token=$token');

      _channel = WebSocketChannel.connect(uri);

      _state = WebSocketState.connected;
      _reconnectAttempts = 0;
      _connectionStateController.add(_state);

      _startHeartbeat();

      _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _state = WebSocketState.disconnected;
      _connectionStateController.add(_state);
      _scheduleReconnect();
    }
  }

  /// Disconnect from the WebSocket server. Call on logout.
  void disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect
    _channel?.sink.close();
    _channel = null;
    _state = WebSocketState.disconnected;
    _connectionStateController.add(_state);
  }

  /// Dispose all resources. Call when the app is shutting down.
  void dispose() {
    disconnect();
    _messageController.close();
    _typingController.close();
    _readReceiptController.close();
    _onlineStatusController.close();
    _offlineStatusController.close();
    _connectionStateController.close();
  }

  // ── Sending Messages ────────────────────────────────────────

  /// Send a text message to a conversation.
  void sendChatMessage(int conversationId, String message) {
    _send({
      'type': 'chat_message',
      'conversation_id': conversationId,
      'message': message,
    });
  }

  /// Send a typing indicator for a conversation.
  void sendTyping(int conversationId) {
    _send({
      'type': 'typing',
      'conversation_id': conversationId,
    });
  }

  /// Send a read receipt for a conversation.
  void sendReadReceipt(int conversationId) {
    _send({
      'type': 'read_receipt',
      'conversation_id': conversationId,
    });
  }

  /// Join a conversation's real-time group.
  void joinConversation(int conversationId) {
    _send({
      'type': 'join_conversation',
      'conversation_id': conversationId,
    });
  }

  /// Leave a conversation's real-time group.
  void leaveConversation(int conversationId) {
    _send({
      'type': 'leave_conversation',
      'conversation_id': conversationId,
    });
  }

  // ── Private Methods ─────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    if (_state != WebSocketState.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {
      // Connection lost; reconnect will handle
    }
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'chat_message':
          final msgData = json['data'] as Map<String, dynamic>? ?? json;
          _messageController.add(msgData);
          break;
        case 'user_typing':
          _typingController.add(json);
          break;
        case 'messages_read':
          _readReceiptController.add(json);
          break;
        case 'user_online':
          final userId = json['user_id'] as int?;
          if (userId != null) _onlineStatusController.add(userId);
          break;
        case 'user_offline':
          final userId = json['user_id'] as int?;
          if (userId != null) _offlineStatusController.add(userId);
          break;
        case 'heartbeat_ack':
          // Connection is alive
          break;
        case 'error':
          // Server sent an error — log but don't crash
          break;
      }
    } catch (_) {
      // Ignore malformed messages
    }
  }

  void _onError(Object error) {
    _state = WebSocketState.disconnected;
    _connectionStateController.add(_state);
    _scheduleReconnect();
  }

  void _onDone() {
    _state = WebSocketState.disconnected;
    _connectionStateController.add(_state);
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _send({'type': 'heartbeat'});
    });
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      return; // Give up after max attempts
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...
    final delay = Duration(seconds: min(30, 1 << _reconnectAttempts));
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => connect());
  }

  int min(int a, int b) => a < b ? a : b;
}