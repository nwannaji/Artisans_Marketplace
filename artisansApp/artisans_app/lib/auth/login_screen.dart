import 'package:artisans_app/screens/user_home_screen.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
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
                if (role == UserRole.customer) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
                } else if (role == UserRole.artisan) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ArtisanDashboardScreen()));
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
              DropdownMenuItem(value: 'CUSTOMER', child: Text('Customer')),
              DropdownMenuItem(value: 'ARTISAN', child: Text('Artisan')),
              DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
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
        ],
      ),
    );
  }
}