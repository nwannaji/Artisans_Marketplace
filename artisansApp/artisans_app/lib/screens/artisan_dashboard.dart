import 'package:artisans_app/auth/location_service.dart';
import 'package:artisans_app/screens/chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'rating_selector.dart';
import 'dart:math';

class ArtisanDashboardScreen extends StatelessWidget {
  final int imageCount;
  const ArtisanDashboardScreen({super.key, this.imageCount = 25});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final random = Random();
    // Generate random Positioned widgets
    List<Widget> scatteredImages = List.generate(imageCount, (index) {
      double top = random.nextDouble() * screenSize.height;
      double left = random.nextDouble() * screenSize.width;

      return Positioned(
        top: top,
        left: left,
        child: Opacity(
          opacity: 0.05,
          child: Image.asset('assets/setting.webp', width: 60, height: 60),
        ),
      );
    });
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),
      appBar: AppBar(
        title: const Text(
          'Artisan Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.teal,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Logout', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ...scatteredImages,
          // Stream for fetching artisan details
          StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('artisan-details')
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No artisans found.'));
              }

              // If data exists, map through all the artisan documents
              final artisanData = snapshot.data!.docs;

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: ListView.builder(
                  itemCount: artisanData.length,
                  itemBuilder: (context, index) {
                    final data =
                        artisanData[index].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: ArtisanCard(data: data),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ArtisanCard extends StatefulWidget {
  final Map<String, dynamic> data;

  const ArtisanCard({super.key, required this.data});

  @override
  State<ArtisanCard> createState() => _ArtisanCardState();
}

class _ArtisanCardState extends State<ArtisanCard> {
  final TextEditingController _locationController = TextEditingController();
  final LocationService _locationService = LocationService();
  String _locationData = '';
  double _userRating = 0.0;

  void _handleRatingChange(double rating) {
    setState(() {
      _userRating = rating;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchAndSetLocation(); // Fetch location when card is built
  }

  Future<void> _fetchAndSetLocation() async {
    try {
      final location = await _locationService.getNearestPlaceDescription();
      if (!mounted) return;
      setState(() {
        _locationController.text = location;
        _locationData = location;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        "Failed to fetch location:${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color.fromARGB(255, 12, 12, 11),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 8,
      shadowColor: Colors.grey.withAlpha(128),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                // Profile picture
                CircleAvatar(
                  radius: 30,
                  backgroundImage:
                      widget.data['profilePicture'] != null
                          ? NetworkImage(widget.data['profilePicture'])
                          : const AssetImage('assets/artisan-logo.jpg')
                              as ImageProvider,
                ),
                const SizedBox(width: 12),

                // Artisan Information
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.data['firstName'] ?? ''} ${widget.data['lastName'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Expertise: ${widget.data['occupation'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Location: ${_locationData.isEmpty ? 'Fetching...' : _locationData}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RatingSelector(
                        initialRating: _userRating,
                        onRatingSelected: _handleRatingChange,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Chat Button
            Align(
              alignment: Alignment.bottomLeft,
              child: TextButton.icon(
                onPressed: () => _startChat(context, widget.data),
                icon: const Icon(Icons.chat, size: 16),
                label: const Text(
                  'Chat',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startChat(BuildContext context, Map<String, dynamic> data) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChatScreenPage(
                employerPhone: currentUser.phoneNumber ?? '',
                artisanPhone: data['phoneNumber'] ?? '',
                peerPhone: '',
              ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to start chat.')),
      );
    }
  }
}
