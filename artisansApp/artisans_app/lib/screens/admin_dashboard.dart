import 'package:artisans_app/screens/scattered_background_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _logout() async {
    await _auth.signOut();
    if (context.mounted) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),

      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: ScatteredBackground(
        imageCount: 20,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome, Admin!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Registered Users:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(
                // Use SizedBox instead of Expanded inside scrollable widget
                height: 200,
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('users')
                          .where('role', isEqualTo: 'User')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final users = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user =
                            users[index].data() as Map<String, dynamic>;
                        return ListTile(
                          title: Text(user['email'] ?? 'No Email'),
                          subtitle: Text('User ID: ${users[index].id}'),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Registered Artisans:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(
                // Again, use SizedBox instead of Expanded
                height: 200,
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('users')
                          .where('role', isEqualTo: 'Artisan')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final artisans = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: artisans.length,
                      itemBuilder: (context, index) {
                        final artisan =
                            artisans[index].data() as Map<String, dynamic>;
                        return ListTile(
                          title: Text(artisan['email'] ?? 'No Email'),
                          subtitle: Text('Artisan ID: ${artisans[index].id}'),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
