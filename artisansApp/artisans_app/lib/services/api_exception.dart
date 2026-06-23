// lib/services/api_exception.dart

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  ApiException({
    this.statusCode,
    required this.message,
    this.errors,
  });

  /// Extracts all field-level error messages from DRF validation errors.
  /// DRF returns errors like {"username": ["A user with that username already exists."]}
  /// This flattens them into a readable string.
  String get fullMessage {
    if (errors == null || errors!.isEmpty) return message;
    final parts = <String>[];
    errors!.forEach((key, value) {
      // Show non_field_errors without the key prefix (it's not user-friendly)
      final displayKey = key == 'non_field_errors' ? '' : '$key: ';
      if (value is List) {
        for (final v in value) {
          parts.add('$displayKey$v');
        }
      } else if (value is String) {
        parts.add('$displayKey$value');
      } else {
        parts.add('$displayKey$value');
      }
    });
    return parts.isNotEmpty ? parts.join('\n') : message;
  }

  @override
  String toString() => 'ApiException($statusCode): $fullMessage';
}

class AuthException extends ApiException {
  AuthException({
    int? statusCode,
    required String message,
    Map<String, dynamic>? errors,
  }) : super(statusCode: statusCode, message: message, errors: errors);
}

class TokenExpiredException extends ApiException {
  TokenExpiredException()
      : super(statusCode: 401, message: 'Token expired. Please log in again.');
}