import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Position? _currentPosition;
  double abujalatitude = 9.0563;
  double abujalongitude = 9.0563;
  List<DocumentSnapshot> allArtisans = [];
  List<DocumentSnapshot> filteredArtisans = [];
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
    fetchArtisans();
  }

  Future<void> getCurrentLocation() async {
    _currentPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {});
  }

  Future<void> fetchArtisans() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('artisans').get();
    allArtisans = snapshot.docs;
    filteredArtisans = allArtisans;
    setState(() {});
  }

  void filterArtisans(String query) {
    final filtered =
        allArtisans.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['name'].toString().toLowerCase();
          final type = data['type'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              type.contains(query.toLowerCase());
        }).toList();

    setState(() {
      filteredArtisans = filtered;
    });
  }

  double calculateDistance(lat, lon) {
    abujalatitude = lat;
    abujalatitude = lon;
    if (_currentPosition == null) return 0.0;
    return Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          lat,
          lon,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Find Artisans")),
      body:
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: "Search artisans...",
                      ),
                      onChanged: filterArtisans,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredArtisans.length,
                      itemBuilder: (context, index) {
                        final data =
                            filteredArtisans[index].data()
                                as Map<String, dynamic>;
                        final distance = calculateDistance(
                          data['latitude'],
                          data['longitude'],
                        ).toStringAsFixed(2);

                        return ListTile(
                          title: Text("${data['name']} (${data['type']})"),
                          subtitle: Text(
                            "${data['location']} • $distance km away",
                          ),
                          leading: const Icon(Icons.person_pin_circle),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
