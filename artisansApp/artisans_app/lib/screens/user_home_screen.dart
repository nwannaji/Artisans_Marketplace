import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logger/logger.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Position? _currentPosition;
  List<DocumentSnapshot> allArtisans = [];
  List<Map<String, dynamic>> filteredArtisans = [];
  final searchController = TextEditingController();
  final Map<String, LatLng> _locationCache = {};
  GoogleMapController? mapController;
  Logger logger = Logger();

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
    fetchArtisans();
  }

  Future<void> getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {});
    } catch (e) {
      logger.d("Location error: $e");
    }
  }

  Future<void> fetchArtisans() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('artisan-details').get();
    allArtisans = snapshot.docs;
    await applyFilters();
  }

  Future<void> applyFilters() async {
    final query = searchController.text.toLowerCase();
    List<Map<String, dynamic>> tempList = [];

    for (var doc in allArtisans) {
      final data = doc.data() as Map<String, dynamic>;
      final occupation = (data['occupation'] ?? '').toString().toLowerCase();
      final location = (data['location'] ?? '').toString();

      if (occupation.contains(query) ||
          location.toLowerCase().contains(query)) {
        LatLng? artisanLatLng = _locationCache[location];

        if (artisanLatLng == null && location.isNotEmpty) {
          try {
            List<Location> locations = await locationFromAddress(location);
            if (locations.isNotEmpty) {
              artisanLatLng = LatLng(
                locations.first.latitude,
                locations.first.longitude,
              );
              _locationCache[location] = artisanLatLng;
            }
          } catch (e) {
            logger.d("Geocoding failed for $location: $e");
          }
        }

        if (artisanLatLng != null && _currentPosition != null) {
          final distanceInMeters = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            artisanLatLng.latitude,
            artisanLatLng.longitude,
          );
          data['distance_km'] = (distanceInMeters / 1000).toStringAsFixed(2);
          data['latLng'] = artisanLatLng;
          tempList.add(data);
        }
      }
    }

    tempList.sort(
      (a, b) =>
          (double.parse(a['distance_km']) - double.parse(b['distance_km']))
              .round(),
    );
    setState(() => filteredArtisans = tempList);
  }

  Set<Marker> _buildMarkers() {
    return filteredArtisans.map((artisan) {
      final LatLng latLng = artisan['latLng'];
      return Marker(
        markerId: MarkerId(artisan['firstName']),
        position: latLng,
        infoWindow: InfoWindow(
          title: "${artisan['firstName']} ${artisan['lastName']}",
          snippet: "${artisan['occupation']} • ${artisan['distance_km']} km",
        ),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 188, 194, 197),
      appBar: AppBar(
        title: const Text(
          "Find Artisans Nearby",
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
      body:
          _currentPosition == null
              ? const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              )
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: "Search by occupation or location",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: fetchArtisans,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(40, 50),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            backgroundColor: Colors.blue,
                          ),
                          child: const Icon(Icons.search, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        zoom: 12,
                      ),
                      markers: _buildMarkers(),
                      onMapCreated: (controller) => mapController = controller,
                      myLocationEnabled: true,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredArtisans.length,
                      itemBuilder: (context, index) {
                        final artisan = filteredArtisans[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage(
                              artisan['profilePicture'] ?? '',
                            ),
                          ),
                          title: Text(
                            "${index + 1}. ${artisan['firstName']} ${artisan['lastName']}",
                          ),
                          subtitle: Text(
                            "${artisan['occupation']} • ${artisan['distance_km']} km away",
                          ),
                          trailing: Text(artisan['location'] ?? ''),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
