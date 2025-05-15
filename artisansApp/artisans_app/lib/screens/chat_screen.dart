import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ChatScreenPage extends StatefulWidget {
  final String peerPhone;

  const ChatScreenPage({
    super.key,
    required this.peerPhone,
    required employerPhone,
    required artisanPhone,
  });

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final TextEditingController _messageController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;
  final picker = ImagePicker();

  String get chatId {
    List<String> phones = [user!.phoneNumber!, widget.peerPhone];
    phones.sort();
    return phones.join("_");
  }

  Future<void> sendTextMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    await _sendMessageToFirestore(message: message);
    _messageController.clear();
  }

  Future<void> _sendMessageToFirestore({
    required String message,
    String? mediaUrl,
    String? mediaType,
  }) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
          'sender': user!.phoneNumber,
          'receiver': widget.peerPhone,
          'message': message,
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
  }

  Future<void> pickAndSendImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final storageRef = FirebaseStorage.instance.ref().child(
      'chat_media/$chatId/$fileName.jpg',
    );

    try {
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await _sendMessageToFirestore(
        message: "📷 Image",
        mediaUrl: downloadUrl,
        mediaType: "image",
      );
    } catch (e) {
      // Handle any error that occurs during file upload
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Widget buildMessageBubble(Map<String, dynamic> data, bool isSentByMe) {
    final hasMedia = data['mediaUrl'] != null;

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSentByMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasMedia && data['mediaType'] == 'image')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Image.network(
                  data['mediaUrl'],
                  width: 200,
                  fit: BoxFit.cover,
                ),
              ),
            Text(
              data['message'] ?? '',
              style: TextStyle(
                color: isSentByMe ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFF8E1),
      appBar: AppBar(
        title: Text(
          "Chat with ${widget.peerPhone}",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Color.fromARGB(255, 45, 99, 153),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Example logout for Firebase:
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                // Navigate to Login screen
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('chats')
                      .doc(chatId)
                      .collection('messages')
                      .orderBy('timestamp')
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final isSentByMe = data['sender'] == user!.phoneNumber;
                    return buildMessageBubble(data, isSentByMe);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: pickAndSendImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    sendTextMessage();
                    _messageController.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
