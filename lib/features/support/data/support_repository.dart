import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/support.dart';

class SupportRepository {
  const SupportRepository(this._api);
  final ApiClient _api;

  Future<SupportList> list() async => SupportList.fromJson(await _api.get('/vendor/support'));

  Future<int> unreadCount() async =>
      intOf(asJson(await _api.get('/vendor/support/unread-count'))['unread_count']);

  /// Opens a ticket. [orderId] (optional) must be one of the kitchen's orders.
  Future<SupportTicket> create({
    required String subject,
    required String message,
    String category = 'other',
    String? orderId,
  }) async {
    final json = asJson(await _api.post('/vendor/support', data: {
      'subject': subject.trim(),
      'message': message.trim(),
      'category': category,
      if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
    }));
    return SupportTicket.fromJson(asJson(json['ticket']));
  }

  /// A ticket with its messages (opening it marks it read).
  Future<SupportTicket> ticket(String id) async =>
      SupportTicket.fromJson(asJson(asJson(await _api.get('/vendor/support/$id'))['ticket']));

  Future<SupportTicket> reply(String id, String message) async => SupportTicket.fromJson(
        asJson(asJson(await _api.post('/vendor/support/$id/messages', data: {'message': message.trim()}))['ticket']),
      );
}
