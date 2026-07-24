// chat_screen.dart
import 'dart:async';
import 'package:artisans_app/models/message.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/chat_api_service.dart';
import 'package:artisans_app/services/voice_note_service.dart';
import 'package:artisans_app/services/websocket_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/widgets/audio_player_bubble.dart';
import 'package:artisans_app/widgets/location_message_bubble.dart';
import 'package:artisans_app/widgets/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatScreenPage extends StatefulWidget {
  final int currentUserId;
  final int otherUserId;
  final String otherUserName;
  final int? conversationId;
  final int messageTtlDays;

  const ChatScreenPage({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.conversationId,
    this.messageTtlDays = 14,
  });

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final ChatApiService _chatService = ChatApiService();
  final VoiceNoteService _voiceNoteService = VoiceNoteService();
  final WebSocketService _wsService = WebSocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int? _conversationId;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false;
  double _recordingDuration = 0;
  Timer? _recordingTimer;
  late int _currentTtlDays;
  bool _isOtherOnline = false;
  bool _isOtherTyping = false;

  // WebSocket subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _onlineSubscription;
  StreamSubscription? _offlineSubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _typingSubscription;
  Timer? _typingClearTimer;

  @override
  void initState() {
    super.initState();
    _currentTtlDays = widget.messageTtlDays;
    _initializeChat();
    _initWebSocket();
  }

  void _initWebSocket() {
    // Listen for incoming messages
    _messageSubscription = _wsService.messages.listen((data) {
      if (!mounted) return;
      try {
        final message = ChatMessage.fromJson(data);
        if (message.conversationId == _conversationId) {
          // Avoid duplicates
          if (!_messages.any((m) => m.id == message.id)) {
            setState(() {
              _messages.add(message);
            });
            _scrollToTop();
          }
        }
      } catch (_) {}
    });

    // Listen for online/offline status
    _onlineSubscription = _wsService.onlineStatus.listen((userId) {
      if (userId == widget.otherUserId && mounted) {
        setState(() => _isOtherOnline = true);
      }
    });

    _offlineSubscription = _wsService.offlineStatus.listen((userId) {
      if (userId == widget.otherUserId && mounted) {
        setState(() => _isOtherOnline = false);
      }
    });

    // Listen for read receipts
    _readReceiptSubscription = _wsService.readReceipts.listen((data) {
      if (!mounted) return;
      final convId = data['conversation_id'] as int?;
      if (convId == _conversationId) {
        setState(() {
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
        });
      }
    });

    // Listen for typing indicators
    _typingSubscription = _wsService.typing.listen((data) {
      final userId = data['user_id'] as int?;
      final convId = data['conversation_id'] as int?;
      if (userId == widget.otherUserId && convId == _conversationId && mounted) {
        setState(() => _isOtherTyping = true);
        _typingClearTimer?.cancel();
        _typingClearTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _typingClearTimer?.cancel();
    _messageSubscription?.cancel();
    _onlineSubscription?.cancel();
    _offlineSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _typingSubscription?.cancel();
    // Leave the conversation room when leaving the screen
    if (_conversationId != null) {
      _wsService.leaveConversation(_conversationId!);
    }
    _voiceNoteService.dispose();
    super.dispose();
  }

  Future<void> _checkOnlineStatus() async {
    try {
      final isOnline = await _chatService.checkOnlineStatus(widget.otherUserId);
      if (mounted) {
        setState(() => _isOtherOnline = isOnline);
      }
    } catch (_) {
      // Silently fail — online status is non-critical
    }
  }

  Future<void> _initializeChat() async {
    try {
      if (widget.conversationId != null) {
        _conversationId = widget.conversationId;
      } else {
        final role = await AuthApiService().getUserRole();
        final int clientId;
        final int artisanId;
        if (role == 'ARTISAN') {
          clientId = widget.otherUserId;
          artisanId = widget.currentUserId;
        } else {
          clientId = widget.currentUserId;
          artisanId = widget.otherUserId;
        }

        final conversation = await _chatService.createConversation(
          clientId: clientId,
          artisanId: artisanId,
        );
        _conversationId = conversation.id;
      }

      await _loadMessages();
      setState(() => _isLoading = false);
      _scrollToTop();

      // Join the WebSocket room for this conversation
      _wsService.joinConversation(_conversationId!);
      _wsService.sendReadReceipt(_conversationId!);

      // Fallback: also check online status via REST in case WS is not connected
      _checkOnlineStatus();
    } catch (e) {
      debugPrint('Chat initialization error: $e');
      setState(() => _isLoading = false);
      _showSnackBar('Failed to initialize chat. Please try again.');
    }
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    try {
      final loaded = await _chatService.getMessages(_conversationId!);
      // Reverse so newest messages appear at the top
      _messages = loaded.reversed.toList();
      setState(() {});
      _scrollToTop();
    } catch (e) {
      debugPrint('Load messages error: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _conversationId == null) return;

    setState(() => _isSending = true);
    try {
      final message = await _chatService.sendMessage(_conversationId!, text);
      _messages.insert(0, message);
      _messageController.clear();
      setState(() {});
      _scrollToTop();
    } catch (e) {
      debugPrint('Message sending failed: $e');
      _showSnackBar('Failed to send message.');
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final result = await _voiceNoteService.stopRecording();
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
      });

      if (result != null && _conversationId != null) {
        setState(() => _isSending = true);
        try {
          final message = await _chatService.sendVoiceNote(
            _conversationId!,
            result.file,
            duration: result.durationSeconds,
          );
          _messages.insert(0, message);
          setState(() {});
          _scrollToTop();
        } catch (e) {
          debugPrint('Voice note sending failed: $e');
          _showSnackBar('Failed to send voice note.');
        } finally {
          setState(() => _isSending = false);
        }
      }
    } else {
      final started = await _voiceNoteService.startRecording();
      if (started) {
        setState(() => _isRecording = true);
        _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (mounted) {
            setState(() {
              _recordingDuration = _voiceNoteService.recordingDurationSeconds;
            });
          }
        });
      } else {
        _showSnackBar('Microphone permission required to record voice notes.');
      }
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _voiceNoteService.cancelRecording();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
  }

  Future<void> _shareLocation() async {
    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
    );
    if (result == null || _conversationId == null) return;

    setState(() => _isSending = true);
    try {
      final message = await _chatService.sendLocation(
        _conversationId!,
        latitude: result.latitude,
        longitude: result.longitude,
        label: result.label,
      );
      _messages.insert(0, message);
      setState(() {});
      _scrollToTop();
    } catch (e) {
      debugPrint('Location sharing failed: $e');
      _showSnackBar('Failed to share location.');
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    if (_conversationId == null) return;
    try {
      await _chatService.deleteMessage(_conversationId!, message.id);
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
      _showSnackBar('Message deleted');
    } catch (e) {
      debugPrint('Delete message failed: $e');
      _showSnackBar('Failed to delete message.');
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _ttlBannerText() {
    switch (_currentTtlDays) {
      case 0:
        return 'Messages in this conversation are kept indefinitely';
      case 7:
        return 'Messages older than 1 week are automatically removed';
      case 14:
        return 'Messages older than 2 weeks are automatically removed';
      case 30:
        return 'Messages older than 1 month are automatically removed';
      default:
        return 'Messages older than $_currentTtlDays days are automatically removed';
    }
  }

  void _showTtlDialog() {
    final options = [
      (0, 'Never expire', Icons.all_inclusive),
      (7, '1 week', Icons.calendar_view_week),
      (14, '2 weeks', Icons.calendar_today),
      (30, '1 month', Icons.date_range),
    ];

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Message retention'),
        children: options.map((opt) {
          final (days, label, icon) = opt;
          return RadioListTile<int>(
            title: Text(label),
            value: days,
            groupValue: _currentTtlDays,
            onChanged: (value) async {
              if (value != null && _conversationId != null) {
                // Pop dialog first to avoid using context across async gap
                Navigator.pop(context);
                try {
                  await _chatService.updateConversationTtl(
                    _conversationId!, ttlDays: value,
                  );
                  if (!mounted) return;
                  setState(() => _currentTtlDays = value);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Retention set to $label')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Failed to update retention setting.')),
                  );
                }
              }
            },
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(ChatMessage message) {
    // Only allow sender to delete their own messages
    if (message.senderId != widget.currentUserId) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete message', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat with ${widget.otherUserName}'),
            Text(
              _isOtherTyping
                  ? 'typing...'
                  : (_isOtherOnline ? 'Online' : 'Offline'),
              style: TextStyle(
                fontSize: 12,
                color: _isOtherTyping
                    ? Theme.of(context).primaryColor
                    : (_isOtherOnline ? Colors.green : Colors.grey),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer),
            tooltip: 'Message retention',
            onPressed: _showTtlDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Auto-delete notice (dynamic based on TTL)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _ttlBannerText(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageItem(_messages[index]);
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    final isSender = message.senderId == widget.currentUserId;
    final timeString = DateFormat('hh:mm a').format(message.timestamp);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: GestureDetector(
          onLongPress: isSender ? () => _showMessageOptions(message) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSender ? AppColors.primary.withValues(alpha: 0.2) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.messageType == MessageType.voiceNote && message.audioUrl != null)
                  AudioPlayerBubble(
                    audioUrl: message.audioUrl!,
                    durationSeconds: message.audioDuration,
                    isSender: isSender,
                  )
                else if (message.messageType == MessageType.location &&
                    message.latitude != null && message.longitude != null)
                  LocationMessageBubble(
                    latitude: message.latitude!,
                    longitude: message.longitude!,
                    label: message.locationLabel,
                    isSender: isSender,
                  )
                else
                  Text(message.message),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeString, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    if (isSender) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 15,
                        color: message.isRead ? Colors.blue : Colors.black54,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Recording ${_formatDuration(_recordingDuration)}',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: _cancelRecording,
            ),
            IconButton(
              icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
              onPressed: _toggleRecording,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          // Attachment button (location + more options)
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _isSending ? null : _showAttachmentMenu,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              foregroundColor: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          // Microphone button
          IconButton(
            icon: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.mic),
            onPressed: _isSending ? null : _toggleRecording,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              foregroundColor: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          // Text input
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              minLines: 1,
              maxLines: 5,
              onChanged: (_) => _wsService.sendTyping(_conversationId ?? 0),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isSending ? null : _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Share', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: Icon(Icons.location_on, color: Theme.of(context).primaryColor),
              title: const Text('Share Location'),
              subtitle: const Text('Share your current or pinned location'),
              onTap: () {
                Navigator.pop(context);
                _shareLocation();
              },
            ),
          ],
        ),
      ),
    );
  }
}