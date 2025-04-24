import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../models/artisan.dart';
import '../widgets/artisan_card.dart';
import 'job_detail.dart';

class SearchArtisansScreen extends StatefulWidget {
  const SearchArtisansScreen({super.key});

  @override
  SearchArtisansScreenState createState() => SearchArtisansScreenState();
}

class SearchArtisansScreenState extends State<SearchArtisansScreen> {
  final _professionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxDistanceController = TextEditingController(text: '10');
  final _minRatingController = TextEditingController();
  final _maxHourlyRateController = TextEditingController();

  double _userLat = 9.0563;
  double _userLng = 7.4985;
  bool _isLoading = false;
  List<Artisan> _artisans = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permissions are permanently denied, we cannot request permissions.',
        );
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchArtisans() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final artisans = await apiService.searchArtisans(
        profession:
            _professionController.text.isEmpty
                ? null
                : _professionController.text,
        location:
            _locationController.text.isEmpty ? null : _locationController.text,
        maxDistance:
            _maxDistanceController.text.isEmpty
                ? null
                : double.parse(_maxDistanceController.text),
        minRating:
            _minRatingController.text.isEmpty
                ? null
                : double.parse(_minRatingController.text),
        maxHourlyRate:
            _maxHourlyRateController.text.isEmpty
                ? null
                : double.parse(_maxHourlyRateController.text),
        userLat: _userLat,
        userLng: _userLng,
      );

      setState(() => _artisans = artisans);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching artisans: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Search Artisans')),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _professionController,
                          decoration: InputDecoration(
                            labelText: 'Profession',
                            hintText: 'e.g. Plumber, Electrician',
                          ),
                        ),
                        TextField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            labelText: 'Location',
                            hintText: 'e.g. City, Neighborhood',
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _maxDistanceController,
                                decoration: InputDecoration(
                                  labelText: 'Max Distance (km)',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _minRatingController,
                                decoration: InputDecoration(
                                  labelText: 'Min Rating',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _maxHourlyRateController,
                          decoration: InputDecoration(
                            labelText: 'Max Hourly Rate',
                            prefixText: '\$',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _searchArtisans,
                          child: Text('Search'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        _artisans.isEmpty
                            ? Center(child: Text('No artisans found'))
                            : ListView.builder(
                              itemCount: _artisans.length,
                              itemBuilder: (context, index) {
                                final artisan = _artisans[index];
                                return ArtisanCard(
                                  artisan: artisan,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => JobDetailScreen(
                                              artisan: artisan,
                                            ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                  ),
                ],
              ),
    );
  }
}
