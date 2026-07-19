import 'package:artisans_app/screens/home_screen.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
import 'package:artisans_app/auth/forgot_password_screen.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';
import 'package:artisans_app/models/user.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Login')),
        body: Consumer<AuthViewModel>(
          builder: (context, viewModel, child) {
            // Show error message if it exists
            if (viewModel.state == AuthState.error &&
                viewModel.errorMessage != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(viewModel.errorMessage!)),
                );
              });
            }

            // Navigate on success
            if (viewModel.state == AuthState.success && viewModel.currentUser != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final role = viewModel.currentUser!.role;
                if (role == UserRole.customer || role == UserRole.artisan) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                } else if (role == UserRole.admin) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
                }
              });
            }

            return Stack(
              children: [
                const _LoginForm(),
                if (viewModel.state == AuthState.loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'CUSTOMER';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<AuthViewModel>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundImage: const AssetImage('assets/images/Persona_Image.png'),
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedRole,
            items: const [
              // SECURITY: Admin login removed from UI — admin access via separate entry point
              DropdownMenuItem(value: 'CUSTOMER', child: Text('Customer')),
              DropdownMenuItem(value: 'ARTISAN', child: Text('Artisan')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedRole = value);
            },
            decoration: const InputDecoration(
              labelText: 'Login as',
              prefixIcon: Icon(Icons.badge),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              viewModel.signIn(
                _usernameController.text.trim(),
                _passwordController.text.trim(),
                _selectedRole,
              );
            },
            child: const Text('Login'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              );
            },
            child: const Text('Forgot Password?'),
          ),
        ],
      ),
    );
  }
}