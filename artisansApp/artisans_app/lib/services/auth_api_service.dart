// lib/services/auth_api_service.dart

import 'dart:io';
import 'api_client.dart';
import 'token_service.dart';

class AuthApiService {
  final ApiClient _apiClient = ApiClient();
  final TokenService _tokenService = TokenService();

  // --- Register ---

  /// Register a new user.
  /// Returns a map with user data. For CUSTOMER role, tokens are included.
  /// For ARTISAN/ADMIN, a message about awaiting approval is included.
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String password2,
    required String role,
    String? phoneNumber,
    String? profession,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'email': email,
      'password': password,
      'password2': password2,
      'role': role,
    };
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      body['phone_number'] = phoneNumber;
    }
    if (profession != null && profession.isNotEmpty) {
      body['profession'] = profession;
    }

    final response = await _apiClient.post('/api/auth/register/', body: body);

    // If tokens were returned (customer accounts), save them
    if (response.containsKey('tokens')) {
      final tokens = response['tokens'] as Map<String, dynamic>;
      await _tokenService.saveTokens(
        access: tokens['access'] as String,
        refresh: tokens['refresh'] as String,
      );
      await _tokenService.saveUserInfo(
        userId: response['user_id'] as int,
        role: response['role'] as String,
      );
    }

    return response;
  }

  // --- Login ---

  /// Log in a user. Returns user data including tokens.
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String role,
  }) async {
    final response = await _apiClient.post('/api/auth/login/', body: {
      'username': username,
      'password': password,
      'role': role,
    });

    if (response.containsKey('tokens')) {
      final tokens = response['tokens'] as Map<String, dynamic>;
      await _tokenService.saveTokens(
        access: tokens['access'] as String,
        refresh: tokens['refresh'] as String,
      );
      await _tokenService.saveUserInfo(
        userId: response['user_id'] as int,
        role: response['role'] as String,
      );
    }

    return response;
  }

  // --- Logout ---

  /// Logout from the server (blacklist the refresh token) and clear local tokens.
  /// If the server call fails (e.g. token already expired), still clear local tokens.
  Future<void> logout() async {
    try {
      final refreshToken = await _tokenService.getRefreshToken();
      if (refreshToken != null) {
        await _apiClient.post('/api/auth/logout/', body: {
          'refresh': refreshToken,
        });
      }
    } catch (_) {
      // Server logout failed — still clear local tokens
    }
    await _tokenService.clearTokens();
  }

  // --- Get current user ---

  /// Fetch the current authenticated user's profile from the API.
  Future<Map<String, dynamic>> getCurrentUser() async {
    return await _apiClient.get('/api/auth/me/');
  }

  // --- Check authentication ---

  /// Returns true if the user has a valid (non-expired) access token.
  Future<bool> isAuthenticated() async {
    return await _tokenService.isAuthenticated();
  }

  /// Returns the stored user role.
  Future<String?> getUserRole() async {
    return await _tokenService.getUserRole();
  }

  /// Returns the stored user ID.
  Future<int?> getUserId() async {
    return await _tokenService.getUserId();
  }

  // --- Update profile ---

  /// Update the current user's profile (email, phone number).
  Future<Map<String, dynamic>> updateProfile({
    String? email,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{};
    if (email != null) body['email'] = email;
    if (phoneNumber != null) body['phone_number'] = phoneNumber;
    return await _apiClient.patch('/api/auth/me/', body: body);
  }

  // --- Change password ---

  /// Change the current user's password.
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return await _apiClient.post('/api/auth/change-password/', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Admin: list all customer accounts
  Future<List<Map<String, dynamic>>> listCustomers({String? search}) async {
    final queryParams = <String, dynamic>{};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    final result = await _apiClient.getList('/api/auth/customers/', queryParams: queryParams.isEmpty ? null : queryParams);
    return result.map((json) => json as Map<String, dynamic>).toList();
  }

  // --- Profile picture upload ---

  /// Upload or update the current user's profile picture.
  /// Returns a map with 'photo_url' on success.
  Future<Map<String, dynamic>> uploadProfilePicture(File imageFile) async {
    return await _apiClient.uploadFile(
      '/api/auth/me/upload-picture/',
      file: imageFile,
      fieldName: 'profile_picture',
    );
  }

  // --- Artisan profile update ---

  /// Update the current artisan's profile (profession, skills, hourly_rate, bio, location).
  /// Only works for artisan-role users. Returns the full updated profile.
  Future<Map<String, dynamic>> updateMyArtisanProfile(Map<String, dynamic> data) async {
    return await _apiClient.patch('/api/auth/me/artisan-profile/', body: data);
  }

  /// Fetch the current artisan's full profile data.
  /// Only works for artisan-role users.
  Future<Map<String, dynamic>> getMyArtisanProfile() async {
    return await _apiClient.get('/api/auth/me/artisan-profile/');
  }
}