// lib/services/artisan_api_service.dart

import '../models/artisan.dart';
import 'api_client.dart';

class ArtisanApiService {
  final ApiClient _apiClient = ApiClient();

  /// List artisans with optional filters
  /// [includeInactive] - when true, includes artisans whose user account is not yet activated (admin use)
  Future<List<Artisan>> listArtisans({
    String? profession,
    String? search,
    double? minRating,
    double? maxRating,
    double? minRate,
    double? maxRate,
    String? ordering,
    bool includeInactive = false,
  }) async {
    final queryParams = <String, dynamic>{};
    if (profession != null) queryParams['profession'] = profession;
    if (search != null) queryParams['search'] = search;
    if (minRating != null) queryParams['min_rating'] = minRating.toString();
    if (maxRating != null) queryParams['max_rating'] = maxRating.toString();
    if (minRate != null) queryParams['min_rate'] = minRate.toString();
    if (maxRate != null) queryParams['max_rate'] = maxRate.toString();
    if (ordering != null) queryParams['ordering'] = ordering;
    if (includeInactive) queryParams['is_active'] = 'all';

    final result = await _apiClient.getList('/api/artisans/', queryParams: queryParams.isEmpty ? null : queryParams);
    return result.map((json) => Artisan.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Search for nearby available artisans within a radius
  /// [availability] filters by status: 'AVAILABLE', 'BUSY', 'ENGAGED', 'OFFLINE', or 'all' for any status
  Future<List<Artisan>> getNearbyArtisans({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
    String? profession,
    String? search,
    String availability = 'AVAILABLE',
  }) async {
    final queryParams = <String, dynamic>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius_km': radiusKm.toString(),
      'availability': availability,
    };
    // When a search term is provided without a profession chip,
    // use it as the profession filter for nearby search (backend uses icontains)
    if (profession != null) {
      queryParams['profession'] = profession;
    } else if (search != null) {
      queryParams['profession'] = search;
    }
    // Also pass search to the backend for broader search (profession + skills + location)
    if (search != null && profession == null) {
      queryParams['search'] = search;
    }

    final result = await _apiClient.get('/api/artisans/nearby/', queryParams: queryParams);
    final results = result['results'] as List<dynamic>;
    return results.map((json) => Artisan.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Get a single artisan's details
  Future<Artisan> getArtisanDetail(int pk) async {
    final result = await _apiClient.get('/api/artisans/$pk/');
    return Artisan.fromJson(result);
  }

  /// Create an artisan profile (for artisans completing their profile)
  Future<Artisan> createArtisanProfile(Map<String, dynamic> data) async {
    final result = await _apiClient.post('/api/artisans/create/', body: data);
    final profile = result['artisan_profile'] ?? result;
    return Artisan.fromJson(profile as Map<String, dynamic>);
  }

  /// Update an artisan profile
  Future<Artisan> updateArtisanProfile(int pk, Map<String, dynamic> data) async {
    final result = await _apiClient.patch('/api/artisans/$pk/verify/', body: data);
    return Artisan.fromJson(result);
  }

  /// Toggle artisan availability status (AVAILABLE, BUSY, OFFLINE).
  /// Optionally sends current GPS location (coordinates + reverse-geocoded address).
  Future<String> toggleAvailability(String status, {double? latitude, double? longitude, String? location}) async {
    final body = <String, dynamic>{'is_available': status};
    if (latitude != null && longitude != null) {
      body['latitude'] = latitude.toStringAsFixed(6);
      body['longitude'] = longitude.toStringAsFixed(6);
    }
    if (location != null && location.isNotEmpty) {
      body['location'] = location;
    }
    final result = await _apiClient.patch('/api/auth/me/availability/', body: body);
    return result['is_available'] as String;
  }

  /// Fetch list of distinct professions from active artisans
  Future<List<String>> fetchProfessions() async {
    final result = await _apiClient.get('/api/artisans/professions/');
    return List<String>.from(result['professions'] as List<dynamic>);
  }

  /// Verify or reject an artisan (admin only)
  Future<Artisan> verifyArtisan(int pk, {required bool verified}) async {
    final result = await _apiClient.patch('/api/artisans/$pk/verify/', body: {
      'is_verified': verified,
    });
    return Artisan.fromJson(result);
  }

  /// Activate or deactivate a user account (admin only)
  Future<Map<String, dynamic>> activateUser(int userId, {required bool isActive}) async {
    return await _apiClient.patch('/api/auth/users/$userId/activate/', body: {
      'is_active': isActive,
    });
  }

  /// Update artisan's GPS location without changing availability status
  Future<Map<String, dynamic>> updateLocation({
    required double latitude,
    required double longitude,
    String? location,
  }) async {
    final body = <String, dynamic>{
      'latitude': latitude.toStringAsFixed(6),
      'longitude': longitude.toStringAsFixed(6),
    };
    if (location != null) body['location'] = location;
    return await _apiClient.patch('/api/auth/me/update-location/', body: body);
  }
}