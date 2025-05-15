import 'dart:io';
import 'package:artisans_app/auth/location_service.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ArtisanProfileScreen extends StatefulWidget {
  const ArtisanProfileScreen({super.key});

  @override
  State<ArtisanProfileScreen> createState() => _ArtisanProfileScreenState();
}

final _formKey = GlobalKey<FormState>();

class _ArtisanProfileScreenState extends State<ArtisanProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _expertiseController = TextEditingController();
  final _locationController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankNameController = TextEditingController();

  LocationService locationService = LocationService();
  final List<String> _status = [];
  File? _profileImage;
  String profileImageUrl = '';
  final ImagePicker _picker = ImagePicker();
  final double _selectedRating = 0.0;

  @override
  void initState() {
    super.initState();
    locationService.getNearestPlaceDescription().then((description) {
      setState(() {
        _locationController.text = description;
      });
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveProfile() async {
    _showLoadingDialog();
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fill in all required fields');
      return;
    }

    if (_profileImage == null) {
      _showSnackBar('Please select a profile picture');
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Upload profile picture to Firebase
      final fileName = '${uid}_profile.jpg';
      final ref = FirebaseStorage.instance.ref().child(
        'profile_pictures/$fileName',
      );
      await ref.putFile(_profileImage!);
      profileImageUrl = await ref.getDownloadURL();

      final docRef = FirebaseFirestore.instance
          .collection('artisan-details')
          .doc(uid);
      final snapshot = await docRef.get();

      double newAverage = 0.0;
      int newRatingCount = 1;

      if (snapshot.exists) {
        final data = snapshot.data()!;
        double currentAverage = (data['ratings'] ?? 0).toDouble();
        int currentCount = (data['ratingCount'] ?? 0);
        newRatingCount = currentCount + 1;
        newAverage =
            ((currentAverage * currentCount) + _selectedRating) /
            newRatingCount;
      } else {
        newAverage = _selectedRating;
      }

      await docRef.set({
        'firstName': _firstNameController.text,
        'lastName': _lastNameController.text,
        'profilePicture': profileImageUrl,
        'occupation': _expertiseController.text,
        'location': _locationController.text,
        'accountNumber': _accountNumberController.text,
        'bankName': _bankNameController.text,
        'ratings': newAverage,
        'ratingCount': newRatingCount,
        'status': _status,
      }, SetOptions(merge: true));

      _showSnackBar('Profile saved successfully!');

      // Clear fields after save
      _clearFields();

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/artisan_dashboard',
          arguments: uid, // pass artisanId here
        );
      }
    } catch (e) {
      _showErrorDialog('Error saving profile: ${e.toString()}');
    } finally {
      _hideLoadingDialog();
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _expertiseController.dispose();
    _locationController.dispose();
    _accountNumberController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  void _clearFields() {
    _firstNameController.clear();
    _lastNameController.clear();
    _expertiseController.clear();
    _locationController.clear();
    _accountNumberController.clear();
    _bankNameController.clear();
    setState(() {
      _profileImage = null;
    });
  }

  Future<void> _pickProfilePhoto() async {
    _showLoadingDialog();
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showErrorDialog('Error picking profile image: ${e.toString()}');
    } finally {
      _hideLoadingDialog();
    }
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
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
        keyboardType:
            label == 'Account Number'
                ? TextInputType.number
                : TextInputType.text,
        validator: (value) {
          if (!readOnly && (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }
          return null;
        },
      ),
    );
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents dismissal on outside touch
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.amber),
        );
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
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),
      appBar: AppBar(
        title: Center(
          child: const Text(
            'Artisan Profile',
            style: TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.teal,
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickProfilePhoto,
                      child: CircleAvatar(
                        radius: 45,
                        backgroundImage:
                            _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                        child:
                            _profileImage == null
                                ? const Icon(Icons.person, size: 45)
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTextField('First Name', _firstNameController),
                        _buildTextField('Last Name', _lastNameController),
                        _buildTextField('Occupation', _expertiseController),
                        _buildTextField(
                          'Location',
                          _locationController,
                          readOnly: true,
                        ),
                        _buildTextField(
                          'Account Number',
                          _accountNumberController,
                        ),
                        _buildTextField('Bank Name', _bankNameController),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Profile',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ArtisanDashboardScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Go to Dashboard",
                      style: TextStyle(color: Color.fromARGB(255, 3, 6, 165)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
