// Refactored LoginScreen with best practices

import 'package:artisans_app/auth/sign_up.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:artisans_app/models/user.dart' as custom_user;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  final String _defaultRole = 'Artisan';
  String _verificationId = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('+234')) return trimmed;
    if (trimmed.startsWith('0')) return '+234${trimmed.substring(1)}';
    return '+234$trimmed';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _showLoadingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoadingDialog() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _verifyPhoneNumber() async {
    final phone = _formatPhoneNumber(_phoneController.text);
    if (phone.length < 10) {
      _showSnackBar('Enter a valid phone number.');
      return;
    }

    _showLoadingDialog();

    try {
      await FirebaseAuth.instance.signOut(); // Ensure clean session

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _showErrorDialog('Verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() => _verificationId = verificationId);
          _showSnackBar('Verification code sent to $phone');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      _showErrorDialog('Phone verification failed: $e');
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _signInWithCode() async {
    final smsCode = _codeController.text.trim();
    if (_verificationId.isEmpty || smsCode.isEmpty) {
      _showSnackBar('Please enter the verification code.');
      return;
    }

    _showLoadingDialog();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
      await _signInWithCredential(credential);
    } catch (e) {
      _showErrorDialog('Invalid code or session expired. Try again.');
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _signInWithCredential(AuthCredential credential) async {
    try {
      final authResult = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = authResult.user;
      if (user == null) {
        _showErrorDialog('User info could not be retrieved.');
        return;
      }

      final docRef = FirebaseFirestore.instance
          .collection('artisans')
          .doc(user.uid);
      final doc = await docRef.get();

      if (!mounted) return;

      if (doc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ArtisanProfileScreen()),
        );
      } else {
        final appUser = custom_user.AppUser(
          id: user.uid,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phoneNumber: user.phoneNumber ?? '',
          role: _defaultRole,
          email: null,
          password: null,
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ArtisanSignUpScreen(appUser: appUser),
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Sign-in failed. Please try again.\n$e');
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.lightBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3F3),
        appBar: AppBar(
          title: const Center(
            child: Text('Login', style: TextStyle(color: Colors.white)),
          ),
          backgroundColor: const Color(0xFF2D6399),
        ),
        body: Stack(
          children: [
            Center(
              child: ClipOval(
                child: Opacity(
                  opacity: 0.3,
                  child: Image.asset(
                    'assets/setting.webp',
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: ClipOval(
                      child: Container(
                        width: 60,
                        height: 60,
                        color: Colors.white,
                        child: Image.asset(
                          'assets/artisan-png.webp',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    label: 'First Name',
                    controller: _firstNameController,
                  ),
                  _buildTextField(
                    label: 'Last Name',
                    controller: _lastNameController,
                  ),
                  _buildTextField(
                    label: 'Phone Number',
                    controller: _phoneController,
                    isNumber: true,
                  ),
                  _buildButton('Send Code', _verifyPhoneNumber),
                  _buildTextField(
                    label: 'Verification Code',
                    controller: _codeController,
                    isNumber: true,
                  ),
                  _buildButton('Verify and Login', _signInWithCode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
