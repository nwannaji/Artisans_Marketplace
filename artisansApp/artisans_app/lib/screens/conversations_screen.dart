// lib/screens/conversations_screen.dart
import 'package:artisans_app/models/conversation.dart';
import 'package:artisans_app/screens/chat_screen.dart';
import 'package:artisans_app/services/chat_api_service.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/theme/app_spacing.dart';
import 'package:artisans_app/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  String _userRole = '';

  final ChatApiService _chatService = ChatApiService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final role = await AuthApiService().getUserRole();
    if (mounted) setState(() => _userRole = role ?? '');
    await _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    try {
      _conversations = await _chatService.listConversations();
      setState(() { _isLoading = false; _error = null; });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  void _openConversation(Conversation conversation) async {
    final currentUserId = await AuthApiService().getUserId();
    if (currentUserId == null) return;

    final otherUserId = conversation.clientId == currentUserId
        ? conversation.artisanId
        : conversation.clientId;
    final otherUserName = conversation.clientId == currentUserId
        ? (conversation.artisanUsername ?? 'Artisan')
        : (conversation.clientUsername ?? 'User');

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreenPage(
          currentUserId: currentUserId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          conversationId: conversation.id,
        ),
      ),
    );
    // Refresh conversations to update unread counts
    if (mounted) _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error!,
                  onRetry: _loadConversations,
                )
              : _conversations.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          return _buildConversationCard(conversation);
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    final isArtisan = _userRole == 'ARTISAN';

    return EmptyState(
      icon: isArtisan ? Icons.chat_bubble_outline : Icons.search,
      title: isArtisan ? 'No messages yet' : 'No conversations yet',
      subtitle: isArtisan
          ? 'When customers message you, your conversations will appear here.'
          : 'Find an artisan and start a conversation!',
      action: !isArtisan
          ? ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find Artisans'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/user_home');
              },
            )
          : null,
    );
  }

  Widget _buildConversationCard(Conversation conversation) {
    final lastMessage = conversation.lastMessage;
    final timeString = lastMessage != null && lastMessage['timestamp'] != null
        ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(lastMessage['timestamp'] as String))
        : '';
    final hasUnread = conversation.unreadCount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _openConversation(conversation),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  (conversation.artisanUsername ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Name + message preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.artisanUsername ?? 'Conversation #${conversation.id}',
                            style: TextStyle(
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastMessage != null
                          ? (lastMessage['message'] as String? ?? '')
                          : 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Timestamp
              Text(
                timeString,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}