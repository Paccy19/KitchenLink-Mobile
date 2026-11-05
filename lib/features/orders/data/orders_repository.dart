import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/order.dart';

class OrderPage {
  const OrderPage({required this.orders, required this.meta});

  factory OrderPage.fromJson(Object? payload) => OrderPage(
        orders: [for (final item in unwrapList(payload, ['orders', 'items'])) VendorOrder.fromJson(item)],
        meta: PageMeta.fromJson(asJson(payload)['meta']),
      );

  final List<VendorOrder> orders;
  final PageMeta meta;
}

class OrdersRepository {
  const OrdersRepository(this._api);
  final ApiClient _api;

  /// A page of orders, newest first. [status] filters by the kitchen status.
  Future<OrderPage> list({OrderStatus? status, int page = 1, int limit = 20}) async =>
      OrderPage.fromJson(
        await _api.get('/vendor/orders', query: {
          if (status != null) 'status': status.code,
          'page': page,
          'limit': limit,
        }),
      );

  Future<VendorOrder> detail(String id) async =>
      VendorOrder.fromJson(asJson(await _api.get('/vendor/orders/$id')));

  /// Moves an order to [status]; the backend validates the transition.
  Future<VendorOrder> updateStatus(String id, OrderStatus status, {String? note}) async =>
      VendorOrder.fromJson(
        asJson(await _api.patch('/vendor/orders/$id/status', data: {
          'status': status.code,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        })),
      );

  /// Pickup / kitchen-delivered orders: complete with the customer's code.
  Future<VendorOrder> collect(String id, String code) async => VendorOrder.fromJson(
        asJson(await _api.post('/vendor/orders/$id/collect', data: {'pickup_code': code})),
      );
}
