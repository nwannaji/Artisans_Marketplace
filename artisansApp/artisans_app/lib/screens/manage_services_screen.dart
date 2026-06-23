// lib/screens/manage_services_screen.dart
import 'package:artisans_app/services/artisan_api_service.dart';
import 'package:artisans_app/services/auth_api_service.dart';
import 'package:artisans_app/services/location_service.dart';
import 'package:flutter/material.dart';

class ManageServicesScreen extends StatefulWidget {
  const ManageServicesScreen({super.key});

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends State<ManageServicesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _professionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();
  final _skillsController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDetectingLocation = false;
  int? _profileId;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // Use /api/auth/me/ to get the user's own artisan profile
      // (listArtisans only returns verified artisans, so the user's own
      // empty profile won't appear there)
      final userData = await AuthApiService().getCurrentUser();
      final artisanProfile = userData['artisan_profile'] as Map<String, dynamic>?;

      if (artisanProfile != null) {
        _profileId = artisanProfile['id'] as int?;
        final profession = artisanProfile['profession'] as String?;
        final hourlyRate = artisanProfile['hourly_rate'];
        final location = artisanProfile['location'] as String?;
        final bio = artisanProfile['bio'] as String?;
        final skills = artisanProfile['skills'];

        // Load stored coordinates
        final latVal = artisanProfile['latitude'];
        final lngVal = artisanProfile['longitude'];
        _latitude = _parseDouble(latVal);
        _longitude = _parseDouble(lngVal);

        if (profession != null && profession.isNotEmpty) {
          _professionController.text = profession;
        }
        if (hourlyRate != null) {
          final rate = hourlyRate is String ? double.tryParse(hourlyRate) : (hourlyRate as num?)?.toDouble();
          if (rate != null) _hourlyRateController.text = rate.toStringAsFixed(0);
        }
        if (location != null && location.isNotEmpty) {
          _locationController.text = location;
        }
        if (bio != null && bio.isNotEmpty) {
          _bioController.text = bio;
        }
        if (skills is List && skills.isNotEmpty) {
          _skillsController.text = skills.join(', ');
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
    _skillsController.dispose();
    super.dispose();
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Detect current GPS location and reverse-geocode to fill the location field.
  Future<void> _detectLocation() async {
    setState(() => _isDetectingLocation = true);
    try {
      final locationService = LocationService();
      final result = await locationService.getCurrentLocationWithAddress();
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _latitude = result.latitude;
          _longitude = result.longitude;
          _locationController.text = result.address;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location detected: ${result.address}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect location. Please enter it manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profileId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find your artisan profile. Please re-login.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _isSaving = true);

    try {
      final skills = _skillsController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final data = <String, dynamic>{
        'profession': _professionController.text.trim(),
        'location': _locationController.text.trim(),
        'bio': _bioController.text.trim(),
        'skills': skills,
      };

      // Include GPS coordinates if available
      if (_latitude != null) data['latitude'] = _latitude!.toStringAsFixed(6);
      if (_longitude != null) data['longitude'] = _longitude!.toStringAsFixed(6);

      // Only send hourly_rate if it's not empty
      final rate = double.tryParse(_hourlyRateController.text);
      if (rate != null) {
        data['hourly_rate'] = rate.toString();
      }

      await ArtisanApiService().updateArtisanProfile(_profileId!, data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Services'),
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
                    Text(
                      _profileId != null && _professionController.text.isNotEmpty
                          ? 'Edit Your Profile'
                          : 'Complete Your Artisan Profile',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _professionController,
                      decoration: const InputDecoration(
                        labelText: 'Profession',
                        prefixIcon: Icon(Icons.work),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Electrician, Plumber, Painter',
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Profession is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hourlyRateController,
                      decoration: const InputDecoration(
                        labelText: 'Hourly Rate (₦)',
                        prefixIcon: Icon(Icons.payment),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. 5000',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => value == null || value.trim().isEmpty ? 'Hourly rate is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        prefixIcon: const Icon(Icons.location_on),
                        border: const OutlineInputBorder(),
                        hintText: 'e.g. Lagos, Ikeja',
                        suffixIcon: _isDetectingLocation
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.my_location),
                                tooltip: 'Detect my location',
                                onPressed: _detectLocation,
                              ),
                      ),
                    ),
                    if (_latitude != null && _longitude != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 12),
                        child: Text(
                          'GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _skillsController,
                      decoration: const InputDecoration(
                        labelText: 'Skills (comma-separated)',
                        prefixIcon: Icon(Icons.build),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Wiring, Installation, Repair',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'About / Bio',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
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
                            : const Text('Save Profile',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}