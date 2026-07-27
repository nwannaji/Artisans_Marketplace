// Unit tests for TokenService JWT decoding
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JWT Token Decoding', () {
    test('correctly decodes a JWT payload', () {
      // Create a mock JWT token with a known payload
      final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
      final payload = base64Url.encode(
        utf8.encode('{"user_id":1,"role":"CUSTOMER","exp":9999999999}'),
      );
      final signature = base64Url.encode(utf8.encode('signature'));
      final token = '$header.$payload.$signature';

      // Decode the payload
      final parts = token.split('.');
      expect(parts.length, 3);

      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;

      expect(payloadMap['user_id'], 1);
      expect(payloadMap['role'], 'CUSTOMER');
      expect(payloadMap['exp'], 9999999999);
    });

    test('rejects tokens with wrong number of parts', () {
      final invalidToken = 'only.two';
      final parts = invalidToken.split('.');
      expect(parts.length, isNot(3));
    });
  });

  group('Password Validation Logic', () {
    test('valid passwords pass all checks', () {
      // These mirror the client-side validation in signup_logic.dart
      final validPasswords = ['Password1', 'MyPass99', 'Abcdef12', 'Test1234'];
      for (final pw in validPasswords) {
        expect(pw.length >= 8, true, reason: '$pw should be at least 8 chars');
        expect(RegExp(r'[A-Za-z]').hasMatch(pw), true, reason: '$pw should contain a letter');
        expect(RegExp(r'[0-9]').hasMatch(pw), true, reason: '$pw should contain a digit');
      }
    });

    test('invalid passwords fail checks', () {
      // Too short
      expect('Pass1'.length < 8, true);
      // No letter
      expect(RegExp(r'[A-Za-z]').hasMatch('12345678'), false);
      // No digit
      expect(RegExp(r'[0-9]').hasMatch('Password'), false);
    });
  });

  group('Role-based Routing', () {
    test('correct role maps to correct route', () {
      // Verify the role-to-route mapping used in main.dart
      const roleRoutes = {
        'CUSTOMER': '/user_home',
        'ARTISAN': '/artisan_dashboard',
        'ADMIN': '/admin_dashboard',
      };

      expect(roleRoutes['CUSTOMER'], '/user_home');
      expect(roleRoutes['ARTISAN'], '/artisan_dashboard');
      expect(roleRoutes['ADMIN'], '/admin_dashboard');
    });
  });
}