// lib/services/api_client.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_exception.dart';
import 'token_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final TokenService _tokenService = TokenService();

  String get baseUrl {
    final url = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
    return url;
  }

  // --- Core request methods ---
  // Each method tries the request. On 401 (TokenExpiredException), it
  // attempts a token refresh and retries once.

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    return _withRefresh<Map<String, dynamic>>(() async {
      final uri = _buildUri(path, queryParams);
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers);
      return _handleMapResponse(response);
    });
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _withRefresh<Map<String, dynamic>>(() async {
      final uri = _buildUri(path);
      final headers = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
      return _handleMapResponse(response);
    });
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _withRefresh<Map<String, dynamic>>(() async {
      final uri = _buildUri(path);
      final headers = await _getHeaders();
      final response = await http.patch(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
      return _handleMapResponse(response);
    });
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _withRefresh<Map<String, dynamic>>(() async {
      final uri = _buildUri(path);
      final headers = await _getHeaders();
      final response = await http.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
      return _handleMapResponse(response);
    });
  }

  Future<void> delete(String path) async {
    await _withRefresh<void>(() async {
      final uri = _buildUri(path);
      final headers = await _getHeaders();
      final response = await http.delete(uri, headers: headers);
      if (response.statusCode == 401) {
        throw TokenExpiredException();
      }
      if (response.statusCode != 204 && response.statusCode != 200) {
        _throwError(response);
      }
    });
  }

  // --- List endpoint (returns list of items) ---

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    return _withRefresh<List<dynamic>>(() async {
      final uri = _buildUri(path, queryParams);
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers);
      return _handleListResponse(response);
    });
  }

  // --- File upload ---

  /// Map of common file extensions to MIME types for explicit content-type
  /// setting on multipart uploads.  Mobile devices sometimes send
  /// application/octet-stream when the real type is image/jpeg etc.
  static const _mimeTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required File file,
    required String fieldName,
    Map<String, String>? fields,
  }) async {
    return _withRefresh<Map<String, dynamic>>(() async {
      final uri = _buildUri(path);
      final headers = await _getHeaders(multipart: true);
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);

      // Explicitly set the content type from the file extension so the server
      // always receives a proper MIME type (e.g. image/jpeg) instead of the
      // generic application/octet-stream that some platforms default to.
      final ext = file.path.split('.').last.toLowerCase();
      final contentType = _mimeTypes[ext];
      final multipartFile = await http.MultipartFile.fromPath(
        fieldName,
        file.path,
        contentType: contentType != null ? MediaType.parse(contentType) : null,
      );
      request.files.add(multipartFile);

      if (fields != null) {
        request.fields.addAll(fields);
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleMapResponse(response);
    });
  }

  // --- Auto-refresh wrapper ---
  // On TokenExpiredException, refreshes the token and retries once.

  Future<T> _withRefresh<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on TokenExpiredException {
      // Attempt to refresh the token
      final refreshed = await refreshToken();
      if (refreshed) {
        // Retry the original request with the new token
        return await request();
      }
      // Refresh failed — rethrow so the caller knows auth is needed
      rethrow;
    }
  }

  // --- URI and header helpers ---

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final url = '$baseUrl$path';
    if (queryParams == null || queryParams.isEmpty) {
      return Uri.parse(url);
    }
    final params = queryParams.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse(url).replace(queryParameters: params);
  }

  Future<Map<String, String>> _getHeaders({bool multipart = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = await _tokenService.getAccessToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (multipart) {
      headers.remove('Content-Type'); // Let multipart set its own
    }
    return headers;
  }

  // --- Response handling ---

  /// Handles responses that should return a Map (single objects).
  Map<String, dynamic> _handleMapResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw TokenExpiredException();
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return {'data': decoded};
      return {'data': decoded};
    }
    _throwError(response);
  }

  List<dynamic> _handleListResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw TokenExpiredException();
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return [];
      final decoded = jsonDecode(response.body);
      if (decoded is List) return decoded;
      // Paginated response: DRF returns {"count": N, "results": [...]}
      if (decoded is Map<String, dynamic> && decoded.containsKey('results')) {
        return decoded['results'] as List<dynamic>;
      }
      return [decoded];
    }
    _throwError(response);
  }

  Never _throwError(http.Response response) {
    String message;
    Map<String, dynamic>? errors;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        errors = body;
        // Try common top-level error keys first
        message = body['detail']?.toString() ??
            body['message']?.toString() ??
            body['error']?.toString() ??
            '';
        // If no top-level key, flatten all field-level errors
        if (message.isEmpty) {
          final parts = <String>[];
          body.forEach((key, value) {
            if (value is List) {
              for (final v in value) {
                parts.add('$key: $v');
              }
            } else {
              parts.add('$key: $value');
            }
          });
          message = parts.isNotEmpty
              ? parts.join('\n')
              : 'Request failed with status ${response.statusCode}';
        }
      } else if (body is List) {
        // Handle list error responses
        final parts = body.map((e) => e.toString()).toList();
        message = parts.isNotEmpty ? parts.join('\n') : 'Request failed with status ${response.statusCode}';
      } else {
        message = 'Request failed with status ${response.statusCode}';
      }
    } catch (_) {
      // Response body is not valid JSON (e.g., HTML error page from Django)
      if (response.statusCode == 400) {
        message = 'Bad request. Please check your connection settings and try again.';
      } else if (response.statusCode == 403) {
        message = 'You do not have permission to perform this action.';
      } else if (response.statusCode == 404) {
        message = 'The requested resource was not found.';
      } else if (response.statusCode == 429) {
        message = 'Too many requests. Please wait a moment and try again.';
      } else if (response.statusCode >= 500) {
        message = 'Server error. Please try again later.';
      } else {
        message = 'Request failed with status ${response.statusCode}';
      }
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: message,
      errors: errors,
    );
  }

  // --- Token refresh ---

  Future<bool> refreshToken() async {
    final refresh = await _tokenService.getRefreshToken();
    if (refresh == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/api/auth/token/refresh/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = data['access'] as String?;
        final newRefresh = data['refresh'] as String?;
        if (newAccess != null) {
          await _tokenService.saveTokens(
            access: newAccess,
            refresh: newRefresh ?? refresh,
          );
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}