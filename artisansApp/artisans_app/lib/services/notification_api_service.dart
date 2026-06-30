// lib/services/notification_api_service.dart

import '../models/notification.dart';
import 'api_client.dart';

class NotificationApiService {
  final ApiClient _apiClient = ApiClient();

  /// Get notifications for the current user.
  /// Set [unreadOnly] to true to fetch only unread notifications.
  Future<List<AppNotification>> getNotifications({bool unreadOnly = false}) async {
    final queryParams = unreadOnly ? {'is_read': 'false'} : null;
    final result = await _apiClient.getList(
      '/api/notifications/notifications/',
      queryParams: queryParams,
    );
    return result
        .map((json) => AppNotification.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Mark a single notification as read.
  Future<AppNotification> markAsRead(int id) async {
    final result = await _apiClient.patch(
      '/api/notifications/notifications/$id/',
      body: {'is_read': true},
    );
    return AppNotification.fromJson(result);
  }

  /// Mark all notifications as read.
  Future<void> markAllRead() async {
    await _apiClient.post('/api/notifications/notifications/mark-all-read/');
  }

  /// Get the unread notification count for the current user.
  Future<int> getUnreadCount() async {
    final result = await _apiClient.get(
      '/api/notifications/notifications/unread-count/',
    );
    return result['unread_count'] as int? ?? 0;
  }
}