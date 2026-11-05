import '../../../core/network/api_client.dart';
import '../models/app_notification.dart';

class NotificationsRepository {
  const NotificationsRepository(this._api);
  final ApiClient _api;

  Future<NotificationPage> list({int limit = 50, bool unreadOnly = false}) async =>
      NotificationPage.fromJson(
        await _api.get('/vendor/notifications', query: {
          'limit': limit,
          if (unreadOnly) 'unread': 'true',
        }),
      );

  Future<void> markRead(String id) => _api.post('/vendor/notifications/$id/read');

  Future<void> markAllRead() => _api.post('/vendor/notifications/read-all');
}
