import 'package:artisans_app/widgets/scattered_background_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final password2Controller = TextEditingController();
  final phoneController = TextEditingController();
  final professionController = TextEditingController();
  String selectedRole = 'CUSTOMER';
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _isArtisan => selectedRole == 'ARTISAN';

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!value.contains(RegExp(r'[A-Za-z]'))) return 'Password must contain at least one letter';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Password must contain at least one digit';
    return null;
  }

  Future<void> signup(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      final response = await authViewModel.signUp(
        username: usernameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
        password2: password2Controller.text.trim(),
        role: selectedRole,
        phoneNumber: phoneController.text.trim(),
        profession: _isArtisan ? professionController.text.trim() : null,
      );

      if (!context.mounted) return;

      if (response != null && response.containsKey('tokens')) {
        // Customer accounts are auto-activated — go to role-based home screen
        final role = selectedRole;
        if (role == 'ARTISAN') {
          Navigator.pushReplacementNamed(context, '/artisan_dashboard');
        } else {
          Navigator.pushReplacementNamed(context, '/user_home');
        }
      } else if (response != null) {
        // Artisan/Admin accounts need admin approval
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account created! Awaiting admin approval."),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        // signUp returned null — show error from ViewModel
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authViewModel.errorMessage ?? 'Signup failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        // SECURITY: Don't expose raw exception details to the user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signup failed. Please check your details and try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sign Up"),
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 8),
                CircleAvatar(
                  radius: 56,
                  backgroundImage: const AssetImage('assets/images/artisan_persona.png'),
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: "Username",
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Username is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Email is required';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: "Phone Number (optional)",
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password2Controller,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // SECURITY: Admin accounts should only be created server-side.
                // Customers and Artisans can self-register.
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  items: const [
                    DropdownMenuItem(value: 'CUSTOMER', child: Text('Customer')),
                    DropdownMenuItem(value: 'ARTISAN', child: Text('Artisan')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => selectedRole = value);
                  },
                  decoration: const InputDecoration(
                    labelText: "Select Role",
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isArtisan) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: professionController,
                    decoration: const InputDecoration(
                      labelText: "What do you do? (e.g. Plumber, Electrician, Painter)",
                      prefixIcon: Icon(Icons.work),
                      border: OutlineInputBorder(),
                    ),
                    validator: _isArtisan
                        ? (value) =>
                            value == null || value.trim().isEmpty ? 'Enter your trade or profession' : null
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => signup(context),
                          child: const Text("Register", style: TextStyle(fontSize: 16)),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text("Already have an account? Login"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}