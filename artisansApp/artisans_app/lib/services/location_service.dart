import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Represents a resolved location with coordinates and a human-readable address.
class LocationResult {
  final double latitude;
  final double longitude;
  final String address;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  @override
  String toString() => 'LocationResult($address, $latitude, $longitude)';
}

class LocationService {
  // Request permission and get the current GPS position
  Future<Position> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied. Please enable in app settings.');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Try to get current position, returning null instead of throwing on failure.
  Future<Position?> getCurrentPositionOrNull() async {
    try {
      return await getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocode coordinates to a human-readable address string.
  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.name != null && p.name!.isNotEmpty) p.name!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) p.administrativeArea!,
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
      return '$lat, $lng';
    } catch (_) {
      return '$lat, $lng';
    }
  }

  /// Get the current location with both GPS coordinates and a human-readable address.
  /// Returns null if location is unavailable.
  Future<LocationResult?> getCurrentLocationWithAddress() async {
    final position = await getCurrentPositionOrNull();
    if (position == null) return null;

    final address = await getAddressFromCoordinates(position.latitude, position.longitude);
    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
  }

  /// Get a human-readable description of the current location.
  /// Falls back to a generic message if location is unavailable.
  Future<String> getNearestPlaceDescription() async {
    try {
      final position = await getCurrentPosition();
      return await getAddressFromCoordinates(position.latitude, position.longitude);
    } catch (e) {
      return 'Location unavailable';
    }
  }
}