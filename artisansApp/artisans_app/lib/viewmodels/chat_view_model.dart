// lib/viewmodels/chat_view_model.dart
import 'dart:async';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/chat_api_service.dart';
import '../services/websocket_service.dart';
import 'base_view_model.dart';

class ChatViewModel extends BaseViewModel {
  final ChatApiService _chatService = ChatApiService();
  final WebSocketService _wsService = WebSocketService();

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  Conversation? _activeConversation;
  Conversation? get activeConversation => _activeConversation;

  Timer? _pollTimer; // Fallback polling when WebSocket is unavailable
  int _lastMessageId = 0;

  // WebSocket state tracking
  bool _useWebSocket = false;
  bool get isConnected => _wsService.isConnected;

  // Online status tracking
  final Set<int> _onlineUsers = {};
  bool isUserOnline(int userId) => _onlineUsers.contains(userId);

  // Typing indicator
  bool _isOtherUserTyping = false;
  bool get isOtherUserTyping => _isOtherUserTyping;
  Timer? _typingTimer;

  // WebSocket subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _onlineSubscription;
  StreamSubscription? _offlineSubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _typingSubscription;

  ChatViewModel() {
    _initWebSocket();
  }

  void _initWebSocket() {
    // Listen for connection state changes
    _connectionSubscription = _wsService.connectionState.listen((state) {
      if (state == WebSocketState.connected) {
        _useWebSocket = true;
        stopPolling(); // Stop REST polling when WS is connected
        // Re-join the active conversation if we were in one
        if (_activeConversation != null) {
          _wsService.joinConversation(_activeConversation!.id);
        }
      } else {
        _useWebSocket = false;
        // Only start polling if we have an active conversation
        if (_activeConversation != null) {
          startPolling();
        }
      }
    });

    // Listen for incoming messages
    _messageSubscription = _wsService.messages.listen(_onWebSocketMessage);

    // Listen for online/offline status
    _onlineSubscription = _wsService.onlineStatus.listen((userId) {
      _onlineUsers.add(userId);
      notifyListeners();
    });

    _offlineSubscription = _wsService.offlineStatus.listen((userId) {
      _onlineUsers.remove(userId);
      notifyListeners();
    });

    // Listen for read receipts
    _readReceiptSubscription = _wsService.readReceipts.listen((data) {
      final conversationId = data['conversation_id'] as int?;
      if (conversationId != null && conversationId == _activeConversation?.id) {
        // Mark messages as read in local state
        for (int i = 0; i < _messages.length; i++) {
          if (!_messages[i].isRead) {
            _messages[i] = ChatMessage(
              id: _messages[i].id,
              conversationId: _messages[i].conversationId,
              senderId: _messages[i].senderId,
              senderUsername: _messages[i].senderUsername,
              message: _messages[i].message,
              messageType: _messages[i].messageType,
              audioUrl: _messages[i].audioUrl,
              audioDuration: _messages[i].audioDuration,
              latitude: _messages[i].latitude,
              longitude: _messages[i].longitude,
              locationLabel: _messages[i].locationLabel,
              isAdminMessage: _messages[i].isAdminMessage,
              timestamp: _messages[i].timestamp,
              isRead: true,
            );
          }
        }
        notifyListeners();
      }
    });

    // Listen for typing indicators
    _typingSubscription = _wsService.typing.listen((data) {
      final convId = data['conversation_id'] as int?;
      if (convId == _activeConversation?.id) {
        _isOtherUserTyping = true;
        notifyListeners();
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          _isOtherUserTyping = false;
          notifyListeners();
        });
      }
    });

    // Attempt to connect
    _wsService.connect();
  }

  void _onWebSocketMessage(Map<String, dynamic> data) {
    try {
      final message = ChatMessage.fromJson(data);
      if (message.conversationId == _activeConversation?.id) {
        // Avoid duplicates (we may have already added from REST send)
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.add(message);
          if (message.id > _lastMessageId) {
            _lastMessageId = message.id;
          }
          notifyListeners();
        }
      }
      // Refresh conversations list to update last_message and unread_count
      loadConversations();
    } catch (_) {
      // Fallback: reload from REST
      if (_activeConversation != null) {
        _pollNewMessages();
      }
    }
  }

  // ── Conversation & Message Methods ─────────────────────────

  /// Load all conversations for the current user
  Future<void> loadConversations() async {
    setState(ViewState.loading);
    try {
      _conversations = await _chatService.listConversations();
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Create or get a conversation with another user
  Future<Conversation?> createConversation({
    required int clientId,
    required int artisanId,
    int? relatedJobId,
  }) async {
    try {
      final conversation = await _chatService.createConversation(
        clientId: clientId,
        artisanId: artisanId,
        relatedJobId: relatedJobId,
      );
      _conversations.insert(0, conversation);
      notifyListeners();
      return conversation;
    } catch (e) {
      setError(e.toString());
      return null;
    }
  }

  /// Select a conversation, load messages, and join the WebSocket room
  Future<void> selectConversation(Conversation conversation) async {
    // Leave previous conversation's WebSocket room
    if (_activeConversation != null) {
      _wsService.leaveConversation(_activeConversation!.id);
    }

    _activeConversation = conversation;
    _messages = [];
    _lastMessageId = 0;
    _isOtherUserTyping = false;
    notifyListeners();

    // Join the new conversation's WebSocket room
    _wsService.joinConversation(conversation.id);

    // Send a read receipt to mark all messages as read
    _wsService.sendReadReceipt(conversation.id);

    try {
      _messages = await _chatService.getMessages(conversation.id);
      if (_messages.isNotEmpty) {
        _lastMessageId = _messages.last.id;
      }
      notifyListeners();

      // Only start polling if WS is NOT connected
      if (!_useWebSocket) {
        startPolling();
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Send a text message in the active conversation
  Future<void> sendMessage(String text) async {
    if (_activeConversation == null || text.trim().isEmpty) return;

    try {
      final message = await _chatService.sendMessage(
        _activeConversation!.id,
        text.trim(),
      );
      // Add to local list if not already added via WebSocket
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        _lastMessageId = message.id;
        notifyListeners();
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Send a typing indicator via WebSocket
  void sendTypingIndicator() {
    if (_activeConversation != null) {
      _wsService.sendTyping(_activeConversation!.id);
    }
  }

  // ── Polling (fallback) ──────────────────────────────────────

  /// Start polling for new messages (used when WebSocket is unavailable)
  void startPolling({Duration interval = const Duration(seconds: 3)}) {
    stopPolling();
    _pollTimer = Timer.periodic(interval, (_) => _pollNewMessages());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollNewMessages() async {
    if (_activeConversation == null) return;

    try {
      final allMessages = await _chatService.getMessages(_activeConversation!.id);
      final newMessages = allMessages.where((m) => m.id > _lastMessageId).toList();
      if (newMessages.isNotEmpty) {
        _messages.addAll(newMessages);
        _lastMessageId = newMessages.last.id;
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore polling errors
    }
  }

  @override
  void dispose() {
    stopPolling();
    _typingTimer?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _onlineSubscription?.cancel();
    _offlineSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _typingSubscription?.cancel();
    // Note: do NOT dispose _wsService; it's a singleton
    super.dispose();
  }
}