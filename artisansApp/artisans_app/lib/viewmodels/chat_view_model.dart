// lib/viewmodels/chat_view_model.dart
import 'dart:async';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/chat_api_service.dart';
import 'base_view_model.dart';

class ChatViewModel extends BaseViewModel {
  final ChatApiService _chatService = ChatApiService();

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  Conversation? _activeConversation;
  Conversation? get activeConversation => _activeConversation;

  Timer? _pollTimer;
  int _lastMessageId = 0;

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

  /// Select a conversation and load its messages
  Future<void> selectConversation(Conversation conversation) async {
    _activeConversation = conversation;
    _messages = [];
    _lastMessageId = 0;
    notifyListeners();

    try {
      _messages = await _chatService.getMessages(conversation.id);
      if (_messages.isNotEmpty) {
        _lastMessageId = _messages.last.id;
      }
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Send a message in the active conversation
  Future<void> sendMessage(String text) async {
    if (_activeConversation == null || text.trim().isEmpty) return;

    try {
      final message = await _chatService.sendMessage(
        _activeConversation!.id,
        text.trim(),
      );
      _messages.add(message);
      _lastMessageId = message.id;
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  /// Start polling for new messages (replaces Firestore real-time streams)
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
    super.dispose();
  }
}