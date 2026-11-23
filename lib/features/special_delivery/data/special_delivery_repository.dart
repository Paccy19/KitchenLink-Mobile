import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// Big-event delivery for the kitchen, one for one with the website's
/// `vendorApi.coverage` and `vendorApi.specialDeliveries`:
///  - `/vendor/delivery-coverage`: where the kitchen delivers (never the price,
///    which KitchenLink sets);
///  - `/vendor/special-deliveries`: requests for deliveries outside that, with
///    the review, the formal quotations and the negotiation chat.
/// The server decides every step (`allowed_actions`); responses stay JSON so
/// the screens show exactly what it sends.
class SpecialDeliveryRepository {
  const SpecialDeliveryRepository(this._api);
  final ApiClient _api;

  static String _path(String id, [String rest = '']) => '/vendor/special-deliveries/${Uri.encodeComponent(id)}$rest';

  // ---- coverage ----

  Future<Json> coverage() async => asJson(await _api.get('/vendor/delivery-coverage'));

  /// Saves where the kitchen delivers. Prices are never sent (the server refuses them).
  Future<Json> saveCoverage({required bool enabled, required List<Json> areas}) async => asJson(
        await _api.put('/vendor/delivery-coverage', data: {
          'big_event_enabled': enabled,
          'areas': [
            for (final area in areas)
              {
                if (area['id'] != null) 'id': area['id'],
                'kind': area['kind'],
                if (area['district'] != null) 'district': area['district'],
                if (area['radius_km'] != null) 'radius_km': area['radius_km'],
                if (area['latitude'] != null) 'latitude': area['latitude'],
                if (area['longitude'] != null) 'longitude': area['longitude'],
                if (area['label'] != null) 'label': area['label'],
              },
          ],
        }),
      );

  /// Whether a point is inside the coverage, and what KitchenLink would charge.
  Future<Json> checkCoverage(double lat, double lng) async =>
      asJson(await _api.get('/vendor/delivery-coverage/check', query: {'lat': lat, 'lng': lng}));

  // ---- special delivery requests ----

  Future<List<Json>> requests({String? scope}) async =>
      unwrapList(await _api.get('/vendor/special-deliveries', query: {'limit': 50, 'scope': ?scope}), ['items']);

  Future<Json> request(String id) async => asJson(await _api.get(_path(id)));

  Future<Json> acceptNegotiation(String id, String message) async =>
      asJson(await _api.post(_path(id, '/accept-negotiation'), data: {'message': message}));

  Future<Json> requestInformation(String id, String message) async =>
      asJson(await _api.post(_path(id, '/request-information'), data: {'message': message}));

  Future<Json> decline(String id, String reason) async => asJson(await _api.post(_path(id, '/decline'), data: {'reason': reason}));

  /// A formal quotation (or a revised one, which replaces the open one).
  Future<Json> submitQuotation(String id, Json quotation) async => asJson(await _api.post(_path(id, '/quotations'), data: quotation));

  Future<Json> withdrawQuotation(String id, String quotationId) async =>
      asJson(await _api.post(_path(id, '/quotations/${Uri.encodeComponent(quotationId)}/withdraw'), data: const <String, dynamic>{}));

  Future<Json> dispute(String id, String reason) async => asJson(await _api.post(_path(id, '/dispute'), data: {'reason': reason}));

  Future<Json> messages(String id) async => asJson(await _api.get(_path(id, '/messages')));

  Future<void> sendMessage(String id, String body) => _api.post(_path(id, '/messages'), data: {'body': body});

  Future<void> markRead(String id) => _api.post(_path(id, '/read'), data: const <String, dynamic>{});
}
