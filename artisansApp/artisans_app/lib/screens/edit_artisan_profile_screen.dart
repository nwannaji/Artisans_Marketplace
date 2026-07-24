// lib/screens/edit_artisan_profile_screen.dart
//
// Screen for artisans to edit their profile: profession, skills, hourly rate,
// bio, location, and profile picture. Uses the dedicated self-service endpoint
// PATCH /api/auth/me/artisan-profile/ — no profile ID required.

import 'dart:io';
import 'package:artisans_app/widgets/profile_avatar.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/location_service.dart';
import 'package:artisans_app/viewmodels/profile_view_model.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class EditArtisanProfileScreen extends StatefulWidget {
  const EditArtisanProfileScreen({super.key});

  @override
  State<EditArtisanProfileScreen> createState() => _EditArtisanProfileScreenState();
}

class _EditArtisanProfileScreenState extends State<EditArtisanProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _professionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();
  final _skillInputController = TextEditingController();
  final _scrollController = ScrollController();

  List<String> _skills = [];
  double? _latitude;
  double? _longitude;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPicture = false;
  bool _isDetectingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final authService = AuthApiService();
      final userData = await authService.getCurrentUser();
      final artisanProfile = userData['artisan_profile'] as Map<String, dynamic>?;

      if (artisanProfile != null) {
        final profession = artisanProfile['profession'] as String?;
        final hourlyRate = artisanProfile['hourly_rate'];
        final location = artisanProfile['location'] as String?;
        final bio = artisanProfile['bio'] as String?;
        final skills = artisanProfile['skills'];
        final latitude = artisanProfile['latitude'];
        final longitude = artisanProfile['longitude'];

        if (profession != null && profession.isNotEmpty) {
          _professionController.text = profession;
        }
        if (hourlyRate != null) {
          final rate = hourlyRate is String
              ? double.tryParse(hourlyRate)
              : (hourlyRate as num?)?.toDouble();
          if (rate != null) _hourlyRateController.text = rate.toStringAsFixed(0);
        }
        if (location != null && location.isNotEmpty) {
          _locationController.text = location;
        }
        if (bio != null && bio.isNotEmpty) {
          _bioController.text = bio;
        }
        if (skills is List && skills.isNotEmpty) {
          _skills = skills.whereType<String>().toList();
        }
        // Load stored coordinates
        if (latitude != null) {
          _latitude = latitude is String ? double.tryParse(latitude) : (latitude as num?)?.toDouble();
        }
        if (longitude != null) {
          _longitude = longitude is String ? double.tryParse(longitude) : (longitude as num?)?.toDouble();
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _professionController.dispose();
    _hourlyRateController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    _skillInputController.dispose();
    _scrollController.dispose();
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

  // --- Skills chip management ---

  void _addSkill() {
    final skill = _skillInputController.text.trim();
    if (skill.isNotEmpty && !_skills.contains(skill)) {
      setState(() {
        _skills.add(skill);
        _skillInputController.clear();
      });
    }
  }

  void _removeSkill(String skill) {
    setState(() {
      _skills.remove(skill);
    });
  }

  // --- Location detection ---

  Future<void> _detectLocation() async {
    setState(() => _isDetectingLocation = true);
    try {
      final locationService = LocationService();
      final result = await locationService.getCurrentLocationWithAddress();
      if (result != null && mounted) {
        setState(() {
          _latitude = result.latitude;
          _longitude = result.longitude;
          _locationController.text = result.address;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location detected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect your location. Please check location permissions.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
    }
  }

  // --- Save profile ---

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{
        'profession': _professionController.text.trim(),
        'location': _locationController.text.trim(),
        'bio': _bioController.text.trim(),
        'skills': _skills,
      };

      // Only send hourly_rate if it's not empty
      final rate = double.tryParse(_hourlyRateController.text);
      if (rate != null) {
        data['hourly_rate'] = rate.toString();
      }

      // Include coordinates if available
      if (_latitude != null) data['latitude'] = _latitude.toString();
      if (_longitude != null) data['longitude'] = _longitude.toString();

      final authService = AuthApiService();
      await authService.updateMyArtisanProfile(data);

      // Refresh the profile so the dashboard and profile screens stay in sync
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
              controller: _scrollController,
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
                        'Tap to change photo',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Profession ---
                    TextFormField(
                      controller: _professionController,
                      decoration: const InputDecoration(
                        labelText: 'Profession *',
                        prefixIcon: Icon(Icons.work),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Electrician, Plumber, Painter',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Profession is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // --- Skills ---
                    const Text('Skills', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _skills.map((skill) => Chip(
                        label: Text(skill),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _removeSkill(skill),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _skillInputController,
                            decoration: const InputDecoration(
                              labelText: 'Add a skill',
                              border: OutlineInputBorder(),
                              hintText: 'e.g. Wiring, Installation',
                            ),
                            onFieldSubmitted: (_) => _addSkill(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _addSkill,
                          icon: const Icon(Icons.add),
                          tooltip: 'Add skill',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- Hourly Rate ---
                    TextFormField(
                      controller: _hourlyRateController,
                      decoration: const InputDecoration(
                        labelText: 'Hourly Rate (₦)',
                        prefixIcon: Icon(Icons.payment),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. 5000',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // --- Location ---
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        prefixIcon: const Icon(Icons.location_on),
                        border: const OutlineInputBorder(),
                        hintText: 'e.g. Lagos, Ikeja',
                        suffixIcon: IconButton(
                          icon: _isDetectingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location),
                          tooltip: 'Detect my location',
                          onPressed: _isDetectingLocation ? null : _detectLocation,
                        ),
                      ),
                    ),
                    if (_latitude != null && _longitude != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 12),
                        child: Text(
                          '$_latitude, $_longitude',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                        hintText: 'Tell customers about yourself and your experience...',
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