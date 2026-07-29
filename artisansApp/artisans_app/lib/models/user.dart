// lib/models/user.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum UserRole { customer, artisan, admin }

class AppUser extends Equatable {
  final int id;
  final String username;
  final String email;
  final String? phoneNumber;
  final UserRole role;
  final bool isActive;
  final bool isVerified;
  final String? photoUrl;

  // Profile fields (populated from /api/auth/me/)
  final Map<String, dynamic>? artisanProfile;
  final Map<String, dynamic>? customerProfile;

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    required this.role,
    this.isActive = true,
    this.isVerified = false,
    this.photoUrl,
    this.artisanProfile,
    this.customerProfile,
  });

  String get fullName => username;

  @override
  List<Object?> get props => [
    id, username, email, phoneNumber, role, isActive, isVerified, photoUrl,
  ];

  AppUser copyWith({
    int? id,
    String? username,
    String? email,
    String? phoneNumber,
    UserRole? role,
    bool? isActive,
    bool? isVerified,
    String? photoUrl,
    Map<String, dynamic>? artisanProfile,
    Map<String, dynamic>? customerProfile,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      photoUrl: photoUrl ?? this.photoUrl,
      artisanProfile: artisanProfile ?? this.artisanProfile,
      customerProfile: customerProfile ?? this.customerProfile,
    );
  }

  /// Parse from login/register response
  factory AppUser.fromAuthResponse(Map<String, dynamic> json) {
    return AppUser(
      id: json['user_id'] as int,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: _parseRole(json['role'] as String?),
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  /// Parse from /api/auth/me/ response
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['user_id'] as int,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      role: _parseRole(json['role'] as String?),
      isActive: json['is_active'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      photoUrl: _resolveUrl(json['photo_url'] as String?),
      artisanProfile: json['artisan_profile'] as Map<String, dynamic>?,
      customerProfile: json['customer_profile'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': id,
      'username': username,
      'email': email,
      'phone_number': phoneNumber,
      'role': role.apiValue,
      'is_active': isActive,
      'is_verified': isVerified,
    };
  }

  static UserRole _parseRole(String? role) {
    switch (role?.toUpperCase()) {
      case 'CUSTOMER':
      case 'USER':
        return UserRole.customer;
      case 'ARTISAN':
        return UserRole.artisan;
      case 'ADMIN':
      case 'ADMINISTRATOR':
        return UserRole.admin;
      default:
        return UserRole.customer;
    }
  }

  /// Resolve a relative URL (e.g. "/media/...") to a full absolute URL.
  ///
  /// - Cloudinary / absolute URLs (starting with http) are returned as-is.
  /// - Relative ``/media/`` paths are routed through the authenticated
  ///   ``/api/media/`` endpoint so the Flutter app can fetch them with
  ///   an auth token (important in production where Django doesn't serve
  ///   /media/ directly).
  /// - Other relative paths are prefixed with the API base URL.
  static String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    final base = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
    // Route media files through the authenticated endpoint
    if (url.startsWith('/media/')) {
      return '$base/api/media/${url.substring('/media/'.length)}';
    }
    return '$base$url';
  }
}

extension on UserRole {
  String get apiValue {
    switch (this) {
      case UserRole.customer: return 'CUSTOMER';
      case UserRole.artisan: return 'ARTISAN';
      case UserRole.admin: return 'ADMIN';
    }
  }
}