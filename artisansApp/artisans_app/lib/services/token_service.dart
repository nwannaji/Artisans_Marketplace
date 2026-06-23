// lib/services/token_service.dart

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _userRoleKey = 'user_role';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // --- Token persistence ---

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessTokenKey, value: access);
    await _storage.write(key: _refreshTokenKey, value: refresh);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userRoleKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && !_isTokenExpired(token);
  }

  // --- User info from token ---

  Map<String, dynamic>? _decodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      // Normalize base64url to base64
      String normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _isTokenExpired(String token) {
    final payload = _decodeToken(token);
    if (payload == null) return true;
    final exp = payload['exp'];
    if (exp == null) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return expiry.isBefore(DateTime.now());
  }

  /// Extracts user_id from the access token payload.
  Future<int?> getUserId() async {
    // Try stored value first
    final stored = await _storage.read(key: _userIdKey);
    if (stored != null) return int.tryParse(stored);

    // Fall back to decoding the token
    final token = await getAccessToken();
    if (token == null) return null;
    final payload = _decodeToken(token);
    if (payload == null) return null;
    return payload['user_id'] as int?;
  }

  /// Extracts role from the access token payload.
  Future<String?> getUserRole() async {
    // Try stored value first
    final stored = await _storage.read(key: _userRoleKey);
    if (stored != null) return stored;

    // Fall back to decoding the token
    final token = await getAccessToken();
    if (token == null) return null;
    final payload = _decodeToken(token);
    if (payload == null) return null;
    return payload['role'] as String?;
  }

  // --- Convenience: save user info after login ---

  Future<void> saveUserInfo({required int userId, required String role}) async {
    await _storage.write(key: _userIdKey, value: userId.toString());
    await _storage.write(key: _userRoleKey, value: role);
  }

  Future<void> clearUserInfo() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userRoleKey);
  }
}