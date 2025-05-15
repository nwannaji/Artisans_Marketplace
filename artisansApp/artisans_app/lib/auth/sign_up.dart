import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:artisans_app/models/user.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';

class ArtisanSignUpScreen extends StatefulWidget {
  final AppUser appUser;

  const ArtisanSignUpScreen({super.key, required this.appUser});

  @override
  State<ArtisanSignUpScreen> createState() => _ArtisanSignUpScreenState();
}

class _ArtisanSignUpScreenState extends State<ArtisanSignUpScreen> {
  @override
  void initState() {
    super.initState();
    _registerArtisan();
  }

  Future<void> _registerArtisan() async {
    _showLoadingDialog();
    final firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection('artisans').doc(widget.appUser.id);

    try {
      // Check if phone number already exists for a different user
      final existingPhone =
          await firestore
              .collection('artisans')
              .where('phone', isEqualTo: widget.appUser.phoneNumber)
              .get();

      if (existingPhone.docs.isNotEmpty &&
          existingPhone.docs.first.id != widget.appUser.id) {
        _showErrorDialog('Phone number already in use');
        return; // Exit early if there's an error
      }

      // Check if artisan already exists
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        await docRef.set({
          'uid': widget.appUser.id,
          'phone': widget.appUser.phoneNumber,
          'firstname': widget.appUser.firstName,
          'lastname': widget.appUser.lastName,
          'role': widget.appUser.role,
          'email': widget.appUser.email,
          'createdAt': Timestamp.now(),
        });
      }

      // Navigate to dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ArtisanDashboardScreen()),
        );
      }
    } catch (e) {
      _showErrorDialog(
        'Registration failed. Please try again: ${e.toString()}',
      );
    } finally {
      _hideLoadingDialog();
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  void _hideLoadingDialog() {
    Navigator.of(context, rootNavigator: true).pop(); // Closes the dialog
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: const Text('Redirecting...')));
  }
}
