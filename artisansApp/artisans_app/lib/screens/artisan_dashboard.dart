import 'package:artisans_app/auth/location_service.dart';
import 'package:artisans_app/screens/chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'rating_selector.dart';

class ArtisanDashboardScreen extends StatefulWidget {
  const ArtisanDashboardScreen({super.key});

  @override
  State<ArtisanDashboardScreen> createState() => _ArtisanDashboardScreenState();
}

class _ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),
      appBar: AppBar(
        title: const Text(
          'Artisan Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 45, 99, 153),
      ),
      body: Stack(
        children: [
          // Background Image
          Center(
            child: ClipOval(
              child: Opacity(
                opacity: 0.3,
                child: Image.asset(
                  'assets/setting.webp',
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

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
  String _LocationData = '';
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
    final location = await _locationService.getNearestPlaceDescription();
    setState(() {
      _locationController.text = location;
      _LocationData = location;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color.fromARGB(255, 96, 154, 85),
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Expertise: ${widget.data['occupation'] ?? ''}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Location: ${_LocationData.isEmpty ? 'Fetching...' : _LocationData}',
                        style: const TextStyle(fontSize: 14),
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
                label: const Text('Chat'),
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

  // Widget _buildRatingSelector() {
  //   return Row(
  //     crossAxisAlignment: CrossAxisAlignment.center,
  //     children: [
  //       const Text('Ratings:', style: TextStyle(fontSize: 14)),
  //       const SizedBox(width: 6),

  //       // Star icons (tappable)
  //       Row(
  //         children: List.generate(5, (index) {
  //           return GestureDetector(
  //             onTap: () {
  //               setState(() {
  //                 _selectedRating = index + 1.0;
  //               });
  //             },
  //             child: Icon(
  //               index < _selectedRating ? Icons.star : Icons.star_border,
  //               color: Colors.amber,
  //               size: 20,
  //             ),
  //           );
  //         }),
  //       ),

  //       const SizedBox(width: 6),

  //       // Numeric value beside stars
  //       Text(
  //         '${_selectedRating.toStringAsFixed(1)} Stars',
  //         style: const TextStyle(fontSize: 14),
  //       ),
  //     ],
  //   );
  // }
}
