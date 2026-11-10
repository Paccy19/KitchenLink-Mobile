import '../../core/network/json.dart';

/// `GET /driver/notifications` entries: new offers, food ready, pickup
/// reminders, a delivery taken by someone else or cancelled, payouts.
class DriverNotification {
  const DriverNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.orderId = '',
    this.read = false,
    this.createdAt,
    this.data = const {},
  });

  factory DriverNotification.fromJson(Json json) => DriverNotification(
        id: str(json['id']),
        type: str(json['type'], 'general'),
        title: str(json['title']),
        body: str(json['body']),
        orderId: str(json['order_id']),
        read: boolOf(json['read']),
        createdAt: dateOrNull(json['created_at']),
        data: asJson(json['data']),
      );

  final String id;
  final String type;
  final String title;
  final String body;
  final String orderId;
  final bool read;
  final DateTime? createdAt;
  final Json data;

  bool get isOffer => type == 'delivery_offer';

  /// Updates about the worker's own trip (open the trip screen).
  bool get isTripUpdate => const {
        'delivery_ready',
        'delivery_pickup_reminder',
        'delivery_late',
        'delivery_update',
      }.contains(type);

  /// Updates that stop the worker's trip.
  bool get endsTrip => type == 'delivery_taken' || type == 'delivery_cancelled';

  /// Earnings credited and payout updates (open the Earnings tab).
  bool get isMoney => type.startsWith('payout_') || type == 'driver_earning' || type == 'driver_penalty';

  /// Pop up while the app is open, like the website's toasts.
  bool get isAlert => isOffer || isTripUpdate || endsTrip;

  DriverNotification markedRead() => DriverNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        orderId: orderId,
        read: true,
        createdAt: createdAt,
        data: data,
      );
}

class DriverNotificationList {
  const DriverNotificationList({this.items = const [], this.unreadCount = 0});

  factory DriverNotificationList.fromJson(Object? payload) {
    final items = [
      for (final item in unwrapList(payload, const ['notifications', 'items'])) DriverNotification.fromJson(item),
    ];
    final json = asJson(payload);
    return DriverNotificationList(
      items: items,
      unreadCount: intOrNull(json['unread_count']) ?? items.where((n) => !n.read).length,
    );
  }

  final List<DriverNotification> items;
  final int unreadCount;
}
