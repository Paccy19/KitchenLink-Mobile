import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/promotions.dart';

class PromotionsRepository {
  const PromotionsRepository(this._api);
  final ApiClient _api;

  Future<Special?> special() async =>
      Special.tryFromJson(asJson(await _api.get('/vendor/special'))['special']);

  /// Publishes or replaces "Tomorrow's Special". Times are sent as UTC ISO.
  Future<Special?> saveSpecial({
    required String text,
    required DateTime cutoffAt,
    required DateTime deliveryAt,
  }) async =>
      Special.tryFromJson(
        asJson(await _api.put('/vendor/special', data: {
          'text': text.trim(),
          'cutoff_at': cutoffAt.toUtc().toIso8601String(),
          'delivery_at': deliveryAt.toUtc().toIso8601String(),
        }))['special'],
      );

  Future<void> clearSpecial() => _api.delete('/vendor/special');

  Future<List<Offer>> offers() async =>
      [for (final item in unwrapList(await _api.get('/vendor/offers'), ['offers'])) Offer.fromJson(item)];

  /// [offerDate] is a `YYYY-MM-DD` day, tomorrow or later.
  Future<Offer> createOffer({required String title, String details = '', required String offerDate}) async {
    final json = asJson(await _api.post('/vendor/offers', data: {
      'title': title.trim(),
      'details': details.trim(),
      'offer_date': offerDate,
    }));
    return Offer.fromJson(asJson(json['offer']));
  }

  Future<void> cancelOffer(String id) => _api.delete('/vendor/offers/$id');
}
