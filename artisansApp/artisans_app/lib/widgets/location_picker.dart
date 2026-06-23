// lib/widgets/location_picker.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// A full-screen page that shows a map and lets the user pick a location.
/// Returns a `LocationResult` when popped, or null if cancelled.
class LocationPickerPage extends StatefulWidget {
  /// Initial camera position (defaults to user's current location if null)
  final LatLng? initialPosition;

  const LocationPickerPage({super.key, this.initialPosition});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  bool _loading = true;
  final TextEditingController _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _selectedPosition = widget.initialPosition;
      _loading = false;
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Default to a central location if service is off
        setState(() {
          _selectedPosition = const LatLng(6.5244, 3.3792); // Lagos
          _loading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _selectedPosition = const LatLng(6.5244, 3.3792);
            _loading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _selectedPosition = const LatLng(6.5244, 3.3792);
          _loading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _selectedPosition = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_selectedPosition!),
      );
    } catch (e) {
      setState(() {
        _selectedPosition = const LatLng(6.5244, 3.3792);
        _loading = false;
      });
    }
  }

  void _confirmSelection() {
    if (_selectedPosition == null) return;
    Navigator.pop(context, LocationResult(
      latitude: _selectedPosition!.latitude,
      longitude: _selectedPosition!.longitude,
      label: _labelController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        actions: [
          TextButton.icon(
            onPressed: _loading || _selectedPosition == null ? null : _confirmSelection,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('Share', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedPosition ?? const LatLng(6.5244, 3.3792),
                      zoom: 14,
                    ),
                    onMapCreated: (controller) => _mapController = controller,
                    markers: _selectedPosition != null
                        ? {
                            Marker(
                              markerId: const MarkerId('selected'),
                              position: _selectedPosition!,
                              draggable: true,
                              onDragEnd: (pos) => setState(() => _selectedPosition = pos),
                            ),
                          }
                        : {},
                    onTap: (pos) => setState(() => _selectedPosition = pos),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _labelController,
                        decoration: InputDecoration(
                          hintText: 'Add a label (e.g., "My office")',
                          prefixIcon: const Icon(Icons.label_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPosition != null)
                        Text(
                          'Lat: ${_selectedPosition!.latitude.toStringAsFixed(6)}, Lng: ${_selectedPosition!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class LocationResult {
  final double latitude;
  final double longitude;
  final String label;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.label = '',
  });
}