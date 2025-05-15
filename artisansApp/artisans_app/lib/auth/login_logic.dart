import 'package:artisans_app/auth/signup_logic.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:artisans_app/screens/user_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> login(BuildContext context) async {
    setState(() => isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      // Fetch user role from Firestore
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(credential.user!.uid)
              .get();

      if (!doc.exists) {
        throw Exception("User profile not found.");
      }
      final role = doc.data()?['role'];

      // Redirect based on role
      if (role == 'User') {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      } else if (role == 'Artisan') {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ArtisanProfileScreen()),
          );
        }
      } else if (role == 'Admin') {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Unknown role")));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login failed: ${e.toString()}")),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),
      appBar: AppBar(
        title: const Text("Login", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              isLoading
                  ? const CircularProgressIndicator(
                    color: Color.fromARGB(255, 159, 113, 6),
                  )
                  : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => login(context),
                    child: const Text(
                      "Login",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  );
                },
                child: const Text(
                  "No account? Sign Up",
                  style: TextStyle(color: Color.fromARGB(255, 3, 6, 165)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
