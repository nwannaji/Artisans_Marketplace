// lib/viewmodels/auth_view_model.dart
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_api_service.dart';
import '../services/api_exception.dart';

enum AuthState { idle, loading, success, error }

class AuthViewModel extends ChangeNotifier {
  final AuthApiService _authService = AuthApiService();

  AuthState _state = AuthState.idle;
  AuthState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  void _setState(AuthState state) {
    _state = state;
    notifyListeners();
  }

  /// Handle user sign-in
  Future<AppUser?> signIn(String username, String password, String role) async {
    _setState(AuthState.loading);
    _errorMessage = null;

    try {
      final response = await _authService.login(
        username: username,
        password: password,
        role: role,
      );

      _currentUser = AppUser.fromAuthResponse(response);
      _setState(AuthState.success);
      return _currentUser;
    } on ApiException catch (e) {
      _errorMessage = _getErrorMessage(e);
      _setState(AuthState.error);
      return null;
    } catch (e) {
      // SECURITY: Don't expose raw exception details
      _errorMessage = 'An unexpected error occurred. Please try again.';
      _setState(AuthState.error);
      return null;
    }
  }

  /// Handle user sign-up
  Future<Map<String, dynamic>?> signUp({
    required String username,
    required String email,
    required String password,
    required String password2,
    required String role,
    String? phoneNumber,
    String? profession,
  }) async {
    _setState(AuthState.loading);
    _errorMessage = null;

    try {
      final response = await _authService.register(
        username: username,
        email: email,
        password: password,
        password2: password2,
        role: role,
        phoneNumber: phoneNumber,
        profession: profession,
      );

      if (response.containsKey('tokens')) {
        // Customer account — automatically logged in
        _currentUser = AppUser.fromAuthResponse(response);
        _setState(AuthState.success);
      } else {
        // Artisan/Admin account — awaiting approval
        _setState(AuthState.success);
      }
      return response;
    } on ApiException catch (e) {
      _errorMessage = _getErrorMessage(e);
      _setState(AuthState.error);
      return null;
    } catch (e) {
      // SECURITY: Don't expose raw exception details
      _errorMessage = 'An unexpected error occurred. Please try again.';
      _setState(AuthState.error);
      return null;
    }
  }

  /// Log out
  Future<void> signOut() async {
    await _authService.logout();
    _currentUser = null;
    _setState(AuthState.idle);
  }

  /// Check if user is already authenticated (for app startup)
  Future<bool> checkAuth() async {
    final isAuth = await _authService.isAuthenticated();
    if (isAuth) {
      try {
        final userData = await _authService.getCurrentUser();
        _currentUser = AppUser.fromJson(userData);
        _setState(AuthState.success);
        return true;
      } catch (e) {
        // Token might be invalid, clear it
        await _authService.logout();
        _setState(AuthState.idle);
        return false;
      }
    }
    _setState(AuthState.idle);
    return false;
  }

  String _getErrorMessage(ApiException e) {
    if (e.errors != null) {
      // Try to extract field-specific errors from Django validation
      final errors = e.errors!;
      if (errors.containsKey('non_field_errors')) {
        return (errors['non_field_errors'] as List).join(', ');
      }
      if (errors.containsKey('detail')) {
        return errors['detail'].toString();
      }
      // Return first error field
      for (final key in errors.keys) {
        if (key != 'tokens') {
          final value = errors[key];
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
          return value.toString();
        }
      }
    }
    return e.message;
  }
}