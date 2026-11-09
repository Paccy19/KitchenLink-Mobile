import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/support.dart';

/// Support tickets. The vendor app uses `/vendor/support`; the delivery worker
/// app passes `/driver/support` (same request and response shapes).
class SupportRepository {
  const SupportRepository(this._api, {this.basePath = '/vendor/support'});
  final ApiClient _api;
  final String basePath;

  Future<SupportList> list() async => SupportList.fromJson(await _api.get(basePath));

  Future<int> unreadCount() async =>
      intOf(asJson(await _api.get('$basePath/unread-count'))['unread_count']);

  /// Opens a ticket. [orderId] (optional) must be one of the kitchen's orders.
  Future<SupportTicket> create({
    required String subject,
    required String message,
    String category = 'other',
    String? orderId,
  }) async {
    final json = asJson(await _api.post(basePath, data: {
      'subject': subject.trim(),
      'message': message.trim(),
      'category': category,
      if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
    }));
    return SupportTicket.fromJson(asJson(json['ticket']));
  }

  /// A ticket with its messages (opening it marks it read).
  Future<SupportTicket> ticket(String id) async =>
      SupportTicket.fromJson(asJson(asJson(await _api.get('$basePath/$id'))['ticket']));

  Future<SupportTicket> reply(String id, String message) async => SupportTicket.fromJson(
        asJson(asJson(await _api.post('$basePath/$id/messages', data: {'message': message.trim()}))['ticket']),
      );
}
