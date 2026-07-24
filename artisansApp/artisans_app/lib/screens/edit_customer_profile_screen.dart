// lib/screens/edit_customer_profile_screen.dart
//
// Screen for customers to edit their profile: bio, address, and profile picture.
// Uses the dedicated self-service endpoint
// PATCH /api/auth/me/customer-profile/ — no profile ID required.

import 'dart:io';
import 'package:artisans_app/widgets/profile_avatar.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/viewmodels/profile_view_model.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class EditCustomerProfileScreen extends StatefulWidget {
  const EditCustomerProfileScreen({super.key});

  @override
  State<EditCustomerProfileScreen> createState() => _EditCustomerProfileScreenState();
}

class _EditCustomerProfileScreenState extends State<EditCustomerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPicture = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final authService = AuthApiService();
      final userData = await authService.getCurrentUser();
      final customerProfile = userData['customer_profile'] as Map<String, dynamic>?;

      if (customerProfile != null) {
        final bio = customerProfile['bio'] as String?;
        final address = customerProfile['address'] as String?;

        if (bio != null && bio.isNotEmpty) {
          _bioController.text = bio;
        }
        if (address != null && address.isNotEmpty) {
          _addressController.text = address;
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _bioController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // --- Profile picture upload ---

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isUploadingPicture = true);
    try {
      final authService = AuthApiService();
      await authService.uploadProfilePicture(File(pickedFile.path));

      if (!mounted) return;
      await context.read<ProfileViewModel>().fetchUserProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated!'),
          backgroundColor: Colors.green,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload picture: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPicture = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Change Profile Picture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // --- Save profile ---

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final authService = AuthApiService();
      await authService.updateMyCustomerProfile(
        bio: _bioController.text.trim(),
        address: _addressController.text.trim(),
      );

      // Refresh the profile so the profile screen stays in sync
      if (mounted) {
        await context.read<ProfileViewModel>().fetchUserProfile();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Return true to signal refresh
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final photoUrl = context.watch<ProfileViewModel>().user?.photoUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Profile picture ---
                    Center(
                      child: GestureDetector(
                        onTap: _isUploadingPicture ? null : _showImageSourceDialog,
                        child: Stack(
                          children: [
                            ProfileAvatar(
                              imageUrl: photoUrl,
                              name: context.watch<ProfileViewModel>().user?.fullName ?? '',
                              radius: 50,
                            ),
                            if (_isUploadingPicture)
                              Positioned.fill(
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                ),
                              ),
                            if (!_isUploadingPicture)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        photoUrl == null ? 'Tap to add a photo' : 'Tap to change photo',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Address ---
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. 12 Allen Avenue, Ikeja, Lagos',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Bio ---
                    TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'About / Bio',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                        hintText: 'Tell artisans a bit about yourself...',
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 24),

                    // --- Save button ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Profile', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}