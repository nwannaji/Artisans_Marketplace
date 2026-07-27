// Unit tests for AppUser model
import 'package:flutter_test/flutter_test.dart';
import 'package:artisans_app/models/user.dart';

void main() {
  group('AppUser', () {
    test('fromAuthResponse creates user with all fields', () {
      final response = {
        'user_id': 1,
        'email': 'test@example.com',
        'role': 'CUSTOMER',
        'is_active': true,
        'tokens': {
          'access': 'access-token',
          'refresh': 'refresh-token',
        },
      };

      final user = AppUser.fromAuthResponse(response);

      expect(user.id, 1);
      expect(user.email, 'test@example.com');
      expect(user.role, UserRole.customer);
      expect(user.isActive, true);
    });

    test('fromAuthResponse handles ARTISAN role', () {
      final response = {
        'user_id': 2,
        'email': 'artisan@example.com',
        'role': 'ARTISAN',
        'is_active': false,
        'tokens': {
          'access': 'access-token',
          'refresh': 'refresh-token',
        },
      };

      final user = AppUser.fromAuthResponse(response);

      expect(user.role, UserRole.artisan);
      expect(user.isActive, false);
    });

    test('fromAuthResponse handles ADMIN role', () {
      final response = {
        'user_id': 3,
        'email': 'admin@example.com',
        'role': 'ADMIN',
        'is_active': true,
        'tokens': {
          'access': 'access-token',
          'refresh': 'refresh-token',
        },
      };

      final user = AppUser.fromAuthResponse(response);

      expect(user.role, UserRole.admin);
    });

    test('fromJson creates user from profile response', () {
      final json = {
        'user_id': 1,
        'username': 'testuser',
        'email': 'test@example.com',
        'role': 'CUSTOMER',
        'is_active': true,
        'is_verified': true,
        'phone_number': '+1234567890',
      };

      final user = AppUser.fromJson(json);

      expect(user.id, 1);
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.role, UserRole.customer);
      expect(user.isVerified, true);
      expect(user.phoneNumber, '+1234567890');
    });

    test('fromAuthResponse throws on missing tokens', () {
      final response = {
        'user_id': 1,
        'email': 'test@example.com',
        'role': 'CUSTOMER',
        'is_active': true,
        // No 'tokens' key
      };

      expect(
        () => AppUser.fromAuthResponse(response),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('UserRole', () {
    test('UserRole has all expected values', () {
      expect(UserRole.values.length, 3);
      expect(UserRole.values, contains(UserRole.customer));
      expect(UserRole.values, contains(UserRole.artisan));
      expect(UserRole.values, contains(UserRole.admin));
    });
  });
}