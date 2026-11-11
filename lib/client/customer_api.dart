import '../api/api_client.dart';
import 'location.dart';
import 'market_models.dart';
import 'models.dart';

/// The public marketplace endpoints the home page reads (no sign-in needed),
/// as the website's api/endpoints.js.
class CustomerApi {
  CustomerApi(this.client);

  final ApiClient client;

  /// The image URL as this device can load it: relative upload paths are
  /// resolved against the API server, and a `localhost` URL is pointed at the
  /// API's host (a phone can't reach the development computer as localhost).
  String? media(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:')) return null;
    final api = Uri.tryParse(client.baseUrl);
    final parsed = Uri.tryParse(raw);
    if (api == null || parsed == null) return null;
    final origin = api.replace(path: '', query: null, fragment: null);
    if (!parsed.hasScheme) {
      if (raw.startsWith('//')) return '${api.scheme}:$raw';
      return origin.resolve(raw.startsWith('/') ? raw : '/$raw').toString();
    }
    const loopback = {'localhost', '127.0.0.1', '0.0.0.0', '::1'};
    if (loopback.contains(parsed.host) && !loopback.contains(api.host)) {
      return parsed.replace(host: api.host, port: api.hasPort ? api.port : null).toString();
    }
    return raw;
  }

  Map<String, Object?> _where(ClientLocation location, {bool withLabel = false}) =>
      location.isLocated ? {'lat': location.lat, 'lng': location.lng, if (withLabel) 'label': location.label} : {};

  String? _types(List<String> types) => types.isEmpty ? null : types.join(',');

  /// GET /home/feed — categories, featured kitchens and popular dishes.
  Future<HomeFeed> feed(ClientLocation location, List<String> vendorTypes) async {
    final data = await client.request('/home/feed${ApiClient.qs({..._where(location, withLabel: true), 'vendor_type': _types(vendorTypes)})}');
    return HomeFeed.fromJson(data);
  }

  /// GET /home/categories.
  Future<List<Category>> categories() async {
    final data = await client.request('/home/categories');
    return pickList(data, ['categories']).map(Category.fromJson).toList();
  }

  /// GET /home/vendors — every kitchen, nearest first when the location is known.
  Future<VendorPage> allVendors(ClientLocation location, List<String> vendorTypes, {int limit = 6}) async {
    final data = await client.request(
      '/home/vendors${ApiClient.qs({..._where(location), 'vendor_type': _types(vendorTypes), 'sort': 'distance', 'page': 1, 'limit': limit})}',
    );
    return VendorPage.fromJson(data);
  }

  /// GET /vendors/specials — "Tomorrow's Special" announcements.
  Future<List<SpecialEntry>> specials(ClientLocation location) async {
    final data = await client.request('/vendors/specials${ApiClient.qs(_where(location))}');
    final entries = <SpecialEntry>[];
    for (final raw in pickList(data, ['specials'])) {
      final special = Special.fromJson(raw['special']);
      if (special != null) entries.add(SpecialEntry(Vendor.fromJson(raw), special));
    }
    return entries;
  }

  /// GET /vendors/offers — upcoming Offer Days.
  Future<List<OfferDay>> offers(ClientLocation location) async {
    final data = await client.request('/vendors/offers${ApiClient.qs(_where(location))}');
    return pickList(data, ['offers']).map(OfferDay.fromJson).where((o) => o.vendor.id.isNotEmpty).toList();
  }

  /// GET /home/search — dishes and kitchens matching the query.
  Future<SearchResult> search(String query, ClientLocation location, List<String> vendorTypes) async {
    final data = await client.request(
      '/home/search${ApiClient.qs({'q': query, 'lat': location.lat, 'lng': location.lng, 'vendor_type': _types(vendorTypes)})}',
    );
    return SearchResult.fromJson(data);
  }

  // ---- Everything past the homepage (the website's api/endpoints.js). These
  // share the session's ApiClient, so its sign-in token goes with them. ----

  Future<Json> _json(String path, {String method = 'GET', Object? body}) async {
    final data = await client.request(path, method: method, body: body);
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  static String _id(String value) => ApiClient.id(value);

  // Kitchens.
  Future<Storefront> storefront(String vendorId, ClientLocation location) async =>
      Storefront.fromJson(await client.request('/vendors/${_id(vendorId)}${ApiClient.qs(_where(location))}'));

  Future<DeliveryQuote> deliveryQuote(String vendorId, double lat, double lng) async =>
      DeliveryQuote.fromJson(await client.request('/vendors/${_id(vendorId)}/delivery-quote${ApiClient.qs({'lat': lat, 'lng': lng})}'));

  /// GET /home/vendors — one page of every kitchen (or of the Big Event ones).
  Future<Json> vendorsPage(
    ClientLocation location, {
    List<String> vendorTypes = const [],
    String? categoryId,
    String sort = 'distance',
    int page = 1,
    int limit = 9,
    bool events = false,
    int? guests,
  }) =>
      _json('/home/vendors${ApiClient.qs({
        ..._where(location),
        'category_id': categoryId,
        'vendor_type': _types(vendorTypes),
        'events': events ? 1 : null,
        'guests': events ? guests : null,
        'sort': sort,
        'page': page,
        'limit': limit,
      })}');

  /// GET /home/vendors/map — every open kitchen, for the map.
  Future<List<Json>> mapVendors(ClientLocation location, {String? categoryId, List<String> vendorTypes = const []}) async => pickList(
        await client.request('/home/vendors/map${ApiClient.qs({..._where(location), 'category_id': categoryId, 'vendor_type': _types(vendorTypes)})}'),
        ['vendors'],
      );

  /// GET /geo/route — the road route between two points.
  Future<Json> route(double fromLat, double fromLng, double toLat, double toLng) =>
      _json('/geo/route${ApiClient.qs({'from_lat': fromLat, 'from_lng': fromLng, 'to_lat': toLat, 'to_lng': toLng})}');

  // Basket.
  Future<Json> cart() => _json('/cart');
  Future<Json> addToCart(String dishId, int quantity) => _json('/cart', method: 'POST', body: {'menu_item_id': dishId, 'quantity': quantity});
  Future<Json> setCartQuantity(String dishId, int quantity) => _json('/cart/${_id(dishId)}', method: 'PATCH', body: {'quantity': quantity});
  Future<Json> removeFromCart(String dishId) => _json('/cart/${_id(dishId)}', method: 'DELETE');
  Future<Json> clearCart() => _json('/cart', method: 'DELETE');
  Future<Json> replaceCart(List<Json> items) => _json('/cart', method: 'PUT', body: {'items': items});

  // Wishlist.
  Future<Json> wishlist() => _json('/wishlist');
  Future<Json> addToWishlist(String dishId) => _json('/wishlist', method: 'POST', body: {'menu_item_id': dishId});
  Future<Json> removeFromWishlist(String dishId) => _json('/wishlist/${_id(dishId)}', method: 'DELETE');

  // Orders.
  Future<List<CustomerOrder>> orders() async =>
      pickList(await client.request('/orders${ApiClient.qs({'limit': 50})}'), ['orders']).map(CustomerOrder.new).toList();
  Future<CustomerOrder> order(String id) async => CustomerOrder(await _json('/orders/${_id(id)}'));
  Future<CustomerOrder> checkout(Json payload) async => CustomerOrder(await _json('/orders/checkout', method: 'POST', body: payload));
  Future<CustomerOrder> cancelOrder(String id, String reason) async =>
      CustomerOrder(await _json('/orders/${_id(id)}/cancel', method: 'POST', body: {'reason': reason}));
  Future<Json> live(String id) => _json('/orders/${_id(id)}/live');
  Future<Json> payBalance(String id) => _json('/orders/${_id(id)}/pay-balance', method: 'POST', body: <String, dynamic>{});
  Future<Json> quoteSwitchToDelivery(String id, Json location) =>
      _json('/orders/${_id(id)}/switch-to-delivery/quote', method: 'POST', body: {'delivery_location': location});
  Future<Json> switchToDelivery(String id, Json payload) => _json('/orders/${_id(id)}/switch-to-delivery', method: 'POST', body: payload);
  Future<Json> changeRefundDestination(String id, String phone) =>
      _json('/orders/${_id(id)}/refund-destination', method: 'PUT', body: {'phone': phone});
  Future<Json> eventQuote(Json payload) => _json('/orders/event-quote', method: 'POST', body: payload);
  Future<CustomerOrder> eventCheckout(Json payload) async => CustomerOrder(await _json('/orders/event-checkout', method: 'POST', body: payload));

  // Chats with kitchens.
  Future<List<Json>> chats() async => pickList(await client.request('/chats'), ['conversations']);
  Future<String> openChatWith(String vendorId) async {
    final data = await _json('/chats/with/${_id(vendorId)}', method: 'POST');
    final conversation = data['conversation'];
    return conversation is Map ? '${conversation['id'] ?? ''}' : '';
  }

  Future<Json> chat(String id, {String? after, String? before}) => _json('/chats/${_id(id)}${ApiClient.qs({'after': after, 'before': before})}');
  Future<Json> sendChat(String id, String body) => _json('/chats/${_id(id)}/messages', method: 'POST', body: {'body': body});
  Future<void> markChatRead(String id) => client.request('/chats/${_id(id)}/read', method: 'POST');

  // Help & Support.
  Future<List<Json>> tickets() async => pickList(await client.request('/support'), ['tickets']);
  Future<Json> ticket(String id) async => _ticket(await _json('/support/${_id(id)}'));
  Future<Json> createTicket(Json payload) async => _ticket(await _json('/support', method: 'POST', body: payload));
  Future<Json> replyTicket(String id, String message) async =>
      _ticket(await _json('/support/${_id(id)}/messages', method: 'POST', body: {'message': message}));
  static Json _ticket(Json data) => data['ticket'] is Map ? (data['ticket'] as Map).cast<String, dynamic>() : <String, dynamic>{};

  // Notifications.
  Future<Json> notifications() => _json('/notifications${ApiClient.qs({'limit': 30})}');
  Future<void> markNotificationRead(String id) => client.request('/notifications/${_id(id)}/read', method: 'POST');
  Future<void> markAllNotificationsRead() => client.request('/notifications/read-all', method: 'POST');
}
