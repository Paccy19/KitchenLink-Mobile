import '../../../core/network/json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.orderId,
    this.link,
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Json json) => AppNotification(
        id: str(json['id']),
        type: str(json['type'], 'general'),
        title: str(json['title']),
        body: str(json['body']),
        orderId: strOrNull(json['order_id']),
        link: strOrNull(asJson(json['data'])['link']),
        read: boolOf(json['read']),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;

  /// `order_placed`, `order_update`, `payout_update`, `account_update`,
  /// `support_message`, `chat_message`, `pickup_code`, `general`…
  final String type;
  final String title;
  final String body;
  final String? orderId;

  /// The website path the backend attaches (`/vendor-dashboard/orders?order=…`).
  final String? link;
  final bool read;
  final DateTime? createdAt;

  AppNotification markRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        orderId: orderId,
        link: link,
        read: true,
        createdAt: createdAt,
      );

  bool get isNewOrder => type == 'order_placed';

  /// The app screen this notification opens, or null when it has no target.
  String? get route => notificationRoute(this);
}

/// Maps the website link the backend attaches to a notification (or, for old
/// ones, its type and order) to a route of this app.
String? notificationRoute(AppNotification notification) {
  final link = notification.link;
  if (link != null && link.startsWith('/')) {
    final uri = Uri.tryParse(link);
    if (uri != null) {
      final path = uri.path;
      if (path.startsWith('/vendor-dashboard/orders')) {
        final id = uri.queryParameters['order'];
        return id == null ? '/orders' : '/orders/$id';
      }
      if (path.startsWith('/vendor-dashboard/messages')) {
        final id = uri.queryParameters['chat'];
        return id == null ? '/messages' : '/messages/$id';
      }
      if (path.startsWith('/vendor-dashboard/support')) {
        final id = uri.queryParameters['ticket'];
        return id == null ? '/support' : '/support/$id';
      }
      if (path.startsWith('/vendor-dashboard/wallet')) return '/wallet';
      if (path.startsWith('/vendor-dashboard/profile')) return '/settings';
      if (path.startsWith('/vendor-dashboard/notifications')) return '/notifications';
    }
  }
  switch (notification.type) {
    case 'payout_update':
      return '/wallet';
    case 'support_message':
      return '/support';
    case 'chat_message':
      return '/messages';
    case 'account_update':
      return notification.orderId == null ? null : '/orders/${notification.orderId}';
  }
  final orderId = notification.orderId;
  return orderId == null ? null : '/orders/$orderId';
}

class NotificationPage {
  const NotificationPage({this.items = const [], this.unreadCount = 0});

  factory NotificationPage.fromJson(Object? payload) {
    final map = asJson(payload);
    return NotificationPage(
      items: [for (final item in unwrapList(payload, ['notifications', 'items'])) AppNotification.fromJson(item)],
      unreadCount: intOf(map['unread_count'], intOf(asJson(map['meta'])['unread_count'])),
    );
  }

  final List<AppNotification> items;
  final int unreadCount;
}
