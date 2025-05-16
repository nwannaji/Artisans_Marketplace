import 'dart:io';

import 'package:artisans_app/auth/chat_service.dart';
import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class ChatScreenPage extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String receiverId;

  const ChatScreenPage({
    required this.chatId,
    required this.currentUserId,
    required this.receiverId,
    super.key,
  });

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    await _chatService.sendMessage(
      chatId: widget.chatId,
      message: text,
      senderId: widget.currentUserId,
      receiverId: widget.receiverId,
    );

    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      String imageUrl = await _chatService.uploadImage(
        File(pickedFile.path),
        widget.chatId,
      );

      await _chatService.sendMessage(
        chatId: widget.chatId,
        message: '',
        senderId: widget.currentUserId,
        receiverId: widget.receiverId,
        mediaUrl: imageUrl,
        mediaType: 'image',
        isImage: true,
      );

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _chatService.markMessagesAsRead(widget.chatId, widget.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 188, 194, 197),
        appBar: AppBar(
          title: const Text('Chat', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.teal,
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
          ],
        ),
        body: ScatteredBackground(
          imageCount: 20,
          child: Column(
            children: [
              // Messages List
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _chatService.getMessages(widget.chatId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data?.docs ?? [];

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final data = messages[index];
                        final isMe = data['senderId'] == widget.currentUserId;

                        // Safely get data as Map<String, dynamic>
                        final dataMap = data.data() as Map<String, dynamic>;
                        // Check if this message is an image
                        final bool isImage = dataMap['isImage'] ?? false;
                        // final imageUrl = data['mediaUrl'];

                        return Align(
                          alignment:
                              isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.blue[100] : Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            // Show image or text message
                            child:
                                isImage
                                    ? Image.network(
                                      dataMap['mediaUrl'] ?? '',
                                      width: 200, // adjust size as needed
                                      height: 200,
                                      fit: BoxFit.cover,
                                    )
                                    : Text(dataMap['message'] ?? ''),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Message Input
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    // Upload Image
                    IconButton(
                      icon: const Icon(Icons.image, color: Colors.teal),
                      onPressed: _sendImage,
                    ),

                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText:
                              'Type a message...'
                              '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Send button
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
