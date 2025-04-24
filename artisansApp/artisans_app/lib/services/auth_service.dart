import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  bool isLoading = true;
  String? _userRole;

  User? get user => _user;
  String? get userRole => _userRole;

  Stream<User?> get userStream => _auth.authStateChanges();

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      isLoading = true;
      if (user != null) {
        _getUserRole(user.uid);
      } else {
        _userRole = null;
      }
      notifyListeners();
    });
  }

  Future<void> _getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        _userRole = doc.data()?['role'];
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user role: $e');
      }
    }
  }

  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['role'] ?? 'customer';
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user role: $e');
      }
      return 'customer';
    }
  }

  Future<void> signInWithEmailAndPassword(
    String email,
    String password,
    String role,
  ) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      // Verify role matches
      final userRole = await getUserRole(_auth.currentUser!.uid);
      if (userRole != role) {
        await _auth.signOut();
        throw Exception('User does not have the selected role');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> registerArtisan({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String profession,
    required String bio,
    required String location,
    required double latitude,
    required double longitude,
    required double hourlyRate,
    required List<String> skills,
    required String bankAccount,
    required String bankName,
  }) async {
    // Register with Firebase Auth
    UserCredential userCredential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    // Save artisan data to Firestore
    await FirebaseFirestore.instance
        .collection('artisans')
        .doc(userCredential.user!.uid)
        .set({
          'uid': userCredential.user!.uid,
          'name': name,
          'email': email,
          'phone': phone,
          'profession': profession,
          'bio': bio,
          'location': location,
          'latitude': latitude,
          'longitude': longitude,
          'hourlyRate': hourlyRate,
          'skills': skills,
          'bankAccount': bankAccount,
          'bankName': bankName,
          'createdAt': Timestamp.now(),
        });
  }
}
