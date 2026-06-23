// lib/viewmodels/profile_view_model.dart
import '../models/user.dart';
import '../services/auth_api_service.dart';
import 'base_view_model.dart';

class ProfileViewModel extends BaseViewModel {
  final AuthApiService _authService = AuthApiService();

  AppUser? _user;
  AppUser? get user => _user;

  Future<void> fetchUserProfile() async {
    setState(ViewState.loading);
    try {
      final userData = await _authService.getCurrentUser();
      _user = AppUser.fromJson(userData);
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> signOut() async {
    await _authService.logout();
  }
}