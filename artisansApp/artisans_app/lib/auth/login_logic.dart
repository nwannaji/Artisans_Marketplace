import 'package:artisans_app/auth/signup_logic.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:artisans_app/screens/user_home_screen.dart';
import 'package:artisans_app/services/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:artisans_app/services/auth_api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  String selectedRole = 'CUSTOMER';
  bool isLoading = false;
  bool _obscurePassword = true;

  final AuthApiService _authService = AuthApiService();

  Future<void> login(BuildContext context) async {
    setState(() => isLoading = true);
    try {
      final response = await _authService.login(
        username: usernameController.text.trim(),
        password: passwordController.text.trim(),
        role: selectedRole,
      );

      if (!context.mounted) return;

      final role = response['role'] as String;
      if (role == 'CUSTOMER') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else if (role == 'ARTISAN') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ArtisanDashboardScreen()),
        );
      } else if (role == 'ADMIN') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unknown role")),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.fullMessage, style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login failed: ${e.toString()}")),
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
        title: const Text("Login"),
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
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
              ),
              const SizedBox(height: 12),
              // SECURITY: Admin login is handled separately; regular users only see Customer/Artisan
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
                  labelText: "Login as",
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
              ),
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
                        onPressed: () => login(context),
                        child: const Text("Login", style: TextStyle(fontSize: 16)),
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  );
                },
                child: const Text("No account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}