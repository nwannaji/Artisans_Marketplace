// chat_screen.dart
import 'dart:async';
import 'package:artisans_app/models/message.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/chat_api_service.dart';
import 'package:artisans_app/services/voice_note_service.dart';
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

  const ChatScreenPage({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.conversationId,
  });

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final ChatApiService _chatService = ChatApiService();
  final VoiceNoteService _voiceNoteService = VoiceNoteService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int? _conversationId;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false;
  double _recordingDuration = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _voiceNoteService.dispose();
    super.dispose();
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
      _scrollToBottom();
    } catch (e) {
      debugPrint('Chat initialization error: $e');
      setState(() => _isLoading = false);
      _showSnackBar('Failed to initialize chat. Please try again.');
    }
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    try {
      _messages = await _chatService.getMessages(_conversationId!);
      setState(() {});
      _scrollToBottom();
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
      _messages.add(message);
      _messageController.clear();
      setState(() {});
      _scrollToBottom();
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
          _messages.add(message);
          setState(() {});
          _scrollToBottom();
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
      _messages.add(message);
      setState(() {});
      _scrollToBottom();
    } catch (e) {
      debugPrint('Location sharing failed: $e');
      _showSnackBar('Failed to share location.');
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.otherUserName}'),
      ),
      body: Column(
        children: [
          // Auto-delete notice
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
                      'Messages older than 2 weeks are automatically removed',
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
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSender ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Colors.grey.shade300,
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