import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Send text or media message
  Future<void> sendMessage({
    required String chatId,
    required String message,
    required String senderId,
    required String receiverId,
    String? mediaUrl,
    String? mediaType,
    bool isImage = false,
  }) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
          'senderId': senderId,
          'receiverId': receiverId,
          'message': message,
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
          'isImage': isImage,
        });

    // Optional: Update chat metadata for last message
    await _firestore.collection('chats').doc(chatId).set({
      'lastMessage': message,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'participants': [senderId, receiverId],
    }, SetOptions(merge: true));
  }

  /// Upload image to Firebase Storage and return its URL
  Future<String> uploadImage(File imageFile, String chatId) async {
    try {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      Reference ref = _storage.ref().child('chat_images/$chatId/$fileName.jpg');
      UploadTask uploadTask = ref.putFile(imageFile);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Image upload failed: $e');
    }
  }

  /// Get real-time stream of messages
  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    final unreadMessages =
        await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('receiverId', isEqualTo: userId)
            .where('read', isEqualTo: false)
            .get();

    for (final doc in unreadMessages.docs) {
      await doc.reference.update({'read': true});
    }
  }

  /// Delete a message
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Edit a message
  Future<void> editMessage(
    String chatId,
    String messageId,
    String newMessage,
  ) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'message': newMessage, 'edited': true});
  }

  /// Get list of chats for a user (based on participation)
  Stream<QuerySnapshot> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastTimestamp', descending: true)
        .snapshots();
  }
}
