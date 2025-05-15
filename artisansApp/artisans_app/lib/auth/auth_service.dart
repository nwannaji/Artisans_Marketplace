import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _verificationId = '';
  final logger = Logger();

  // Send SMS code to user's phone number
  Future<void> sendVerificationCode(
    String phoneNumber,
    Function(String) onCodeSent,
  ) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        await _saveUserData();
      },
      verificationFailed: (FirebaseAuthException e) {
        logger.d('Verification failed: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // Sign in manually with SMS code
  Future<void> verifyCode(String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: smsCode,
    );

    await _auth.signInWithCredential(credential);
    await _saveUserData();
  }

  //svae new user to firestore
  Future<void> _saveUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final docRef = _firestore.collection("users").doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'uid': user.uid,
          'phone': user.phoneNumber,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // Optional: Sign out user
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Check if user is signed in
  User? get currentUser => _auth.currentUser;
}
