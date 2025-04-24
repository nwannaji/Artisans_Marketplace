import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';

class RegisterArtisanScreen extends StatefulWidget {
  const RegisterArtisanScreen({super.key});

  @override
  State<RegisterArtisanScreen> createState() => _RegisterArtisanScreenState();
}

class _RegisterArtisanScreenState extends State<RegisterArtisanScreen> {
  final _formKey = GlobalKey<FormState>();

  final _controllers = {
    'email': TextEditingController(),
    'password': TextEditingController(),
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'profession': TextEditingController(),
    'bio': TextEditingController(),
    'hourlyRate': TextEditingController(),
    'bankAccount': TextEditingController(),
    'bankName': TextEditingController(),
    'skills': TextEditingController(),
  };

  String _location = '';
  double _latitude = 9.0563;
  double _longitude = 7.4985;
  final List<String> _skills = [];
  final List<String> _certificates = [];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _location =
            '${placemarks.first.locality}, ${placemarks.first.administrativeArea}';
      });
    } catch (e) {
      _showError('Error getting location: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadCertificate() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        setState(() => _certificates.add(pickedFile.path));
      }
    } catch (e) {
      _showError('Error uploading certificate: ${e.toString()}');
    }
  }

  void _addSkill() {
    final skill = _controllers['skills']!.text.trim();
    if (skill.isNotEmpty) {
      setState(() {
        _skills.add(skill);
        _controllers['skills']!.clear();
      });
    }
  }

  void _removeSkill(String skill) {
    setState(() => _skills.remove(skill));
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.registerArtisan(
        email: _controllers['email']!.text,
        password: _controllers['password']!.text,
        name: _controllers['name']!.text,
        phone: _controllers['phone']!.text,
        profession: _controllers['profession']!.text,
        bio: _controllers['bio']!.text,
        location: _location,
        latitude: _latitude,
        longitude: _longitude,
        hourlyRate: double.parse(_controllers['hourlyRate']!.text),
        skills: _skills,
        bankAccount: _controllers['bankAccount']!.text,
        bankName: _controllers['bankName']!.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful!')),
        );
        Navigator.pushReplacementNamed(context, '/artisan-dashboard');
      }
    } catch (e) {
      _showError('Registration failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _buildTextField({
    required String key,
    required String label,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(labelText: label),
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator:
          validator ??
          (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your $label';
            }
            return null;
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register as Artisan')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        key: 'email',
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _buildTextField(
                        key: 'password',
                        label: 'Password',
                        obscure: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      _buildTextField(key: 'name', label: 'Full Name'),
                      _buildTextField(
                        key: 'phone',
                        label: 'Phone Number',
                        keyboardType: TextInputType.phone,
                      ),
                      _buildTextField(key: 'profession', label: 'Profession'),
                      _buildTextField(key: 'bio', label: 'Bio', maxLines: 3),
                      const SizedBox(height: 16),
                      Text('Location: $_location'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _getCurrentLocation,
                        child: const Text('Refresh Location'),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        key: 'hourlyRate',
                        label: 'Hourly Rate',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your hourly rate';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Skills:'),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              key: 'skills',
                              label: 'Add a skill',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _addSkill,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8.0,
                        children:
                            _skills.map((skill) {
                              return Chip(
                                label: Text(skill),
                                onDeleted: () => _removeSkill(skill),
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Certificates:'),
                      Wrap(
                        spacing: 8.0,
                        children:
                            _certificates.map((cert) {
                              return Chip(
                                label: Text(cert.split('/').last),
                                onDeleted:
                                    () => setState(
                                      () => _certificates.remove(cert),
                                    ),
                              );
                            }).toList(),
                      ),
                      ElevatedButton(
                        onPressed: _uploadCertificate,
                        child: const Text('Upload Certificate'),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(key: 'bankName', label: 'Bank Name'),
                      _buildTextField(
                        key: 'bankAccount',
                        label: 'Bank Account',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _submitForm,
                        child: const Text('Register'),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
