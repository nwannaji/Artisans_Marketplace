import 'package:artisans_app/auth/forgot_password_screen.dart';
import 'package:artisans_app/auth/signup_logic.dart';
import 'package:artisans_app/widgets/scattered_background_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';
import 'package:artisans_app/models/user.dart';

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

  Future<void> login(BuildContext context) async {
    setState(() => isLoading = true);
    try {
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      final user = await authViewModel.signIn(
        usernameController.text.trim(),
        passwordController.text.trim(),
        selectedRole,
      );

      if (!context.mounted) return;

      if (user != null) {
        if (user.role == UserRole.customer) {
          Navigator.pushReplacementNamed(context, '/user_home');
        } else if (user.role == UserRole.artisan) {
          Navigator.pushReplacementNamed(context, '/artisan_dashboard');
        } else if (user.role == UserRole.admin) {
          Navigator.pushReplacementNamed(context, '/admin_dashboard');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unknown role")),
          );
        }
      } else {
        // AuthViewModel already set the error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authViewModel.errorMessage ?? 'Login failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        // SECURITY: Don't expose raw exception details to the user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login failed. Please check your credentials and try again.'),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text("Forgot Password?"),
                ),
              ),
              const SizedBox(height: 4),
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