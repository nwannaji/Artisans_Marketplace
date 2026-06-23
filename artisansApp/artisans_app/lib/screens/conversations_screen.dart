// lib/screens/conversations_screen.dart
import 'package:artisans_app/models/conversation.dart';
import 'package:artisans_app/screens/chat_screen.dart';
import 'package:artisans_app/services/chat_api_service.dart';
import 'package:artisans_app/services/auth_api_service.dart';
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadConversations, child: const Text('Retry')),
                    ],
                  ),
                )
              : _conversations.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      child: ListView.builder(
                          itemCount: _conversations.length,
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            return _buildConversationTile(conversation);
                          },
                        ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    final isArtisan = _userRole == 'ARTISAN';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isArtisan ? Icons.chat_bubble_outline : Icons.search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isArtisan
                  ? 'No messages yet'
                  : 'No conversations yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isArtisan
                  ? 'When customers message you, your conversations will appear here.'
                  : 'Find an artisan and start a conversation!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            if (!isArtisan) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Find Artisans'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/user_home');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final lastMessage = conversation.lastMessage;
    final timeString = lastMessage != null && lastMessage['timestamp'] != null
        ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(lastMessage['timestamp'] as String))
        : '';
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor,
        child: Text(
          (conversation.artisanUsername ?? '?')[0].toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.artisanUsername ?? 'Conversation #${conversation.id}',
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (hasUnread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      subtitle: lastMessage != null
          ? Text(
              lastMessage['message'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            )
          : const Text('No messages yet'),
      trailing: Text(timeString, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      onTap: () => _openConversation(conversation),
    );
  }
}