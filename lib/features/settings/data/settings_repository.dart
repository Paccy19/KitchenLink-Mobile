import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../../../core/utils/uploads.dart';
import '../../auth/models/vendor_account.dart';
import '../models/event_package.dart';
import '../models/place.dart';

class SettingsRepository {
  const SettingsRepository(this._api);
  final ApiClient _api;

  VendorAccount _vendor(Object? payload) =>
      VendorAccount.fromJson(asJson(asJson(payload)['vendor']));

  /// Opens or closes the store. The backend uses the registered coordinates;
  /// the phone's own position is never sent.
  Future<VendorAccount> setAvailability({required bool isOpen}) async =>
      _vendor(await _api.patch('/vendor/availability', data: {'is_open': isOpen}));

  /// Text profile fields (JSON): any of `name`, `owner_name`, `description`,
  /// `phone`, `operating_hours`, `payment_information`, `location`.
  Future<VendorAccount> updateProfile(Json fields) async =>
      _vendor(await _api.patch('/vendor/profile', data: fields));

  /// Banner and/or profile photo (multipart; images up to 5 MB).
  Future<VendorAccount> updateImages({
    PickedUpload? banner,
    PickedUpload? profile,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData();
    if (banner != null) form.files.add(MapEntry('banner_image', await banner.toMultipart()));
    if (profile != null) form.files.add(MapEntry('profile_image', await profile.toMultipart()));
    return _vendor(await _api.multipart('PATCH', '/vendor/profile', form, onProgress: onProgress));
  }

  Future<VendorAccount> requestTypeChange({required String vendorType, String reason = ''}) async =>
      _vendor(await _api.post('/vendor/profile/type-request', data: {
        'vendor_type': vendorType,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      }));

  Future<VendorAccount> cancelTypeChange() async =>
      _vendor(await _api.delete('/vendor/profile/type-request'));

  Future<OrderingRules> ordering() async =>
      OrderingRules.fromJson(asJson(asJson(await _api.get('/vendor/ordering'))['ordering']));

  /// `null` for a field puts it back to the kitchen type's default.
  Future<OrderingRules> saveOrdering({int? dailyOrderLimit, int? minOrderRwf, bool sendDailyLimit = true}) async =>
      OrderingRules.fromJson(
        asJson(asJson(await _api.put('/vendor/ordering', data: {
          if (sendDailyLimit) 'daily_order_limit': dailyOrderLimit,
          'min_order_rwf': minOrderRwf,
        }))['ordering']),
      );

  Future<NationwideInfo> nationwide() async =>
      NationwideInfo.fromJson(asJson(asJson(await _api.get('/vendor/nationwide'))['nationwide']));

  Future<NationwideInfo> saveNationwide({int? travelBaseFeeRwf, int? travelPerKmRwf}) async =>
      NationwideInfo.fromJson(
        asJson(asJson(await _api.put('/vendor/nationwide', data: {
          'travel_base_fee_rwf': travelBaseFeeRwf,
          'travel_per_km_rwf': travelPerKmRwf,
        }))['nationwide']),
      );

  Future<EventPackageSettings> eventPackage() async =>
      EventPackageSettings.fromJson(await _api.get('/vendor/event-package'));

  Future<EventPackageSettings> saveEventPackage(EventPackageSettings settings) async =>
      EventPackageSettings.fromJson(await _api.put('/vendor/event-package', data: settings.toJson()));

  // ---- place search for the kitchen location (public, rate limited) ----

  Future<List<PlaceSuggestion>> placeSuggestions(String query, {double? lat, double? lng}) async => [
        for (final item in unwrapList(
          await _api.get('/geo/places/autocomplete', query: {
            'q': query,
            if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
          }, auth: false),
          ['suggestions'],
        ))
          PlaceSuggestion.fromJson(item),
      ];

  Future<Place> placeDetails(String id) async =>
      Place.fromJson(asJson(asJson(await _api.get('/geo/places/details', query: {'id': id}, auth: false))['place']));

  /// The area and street at a point (either may be empty).
  Future<({String area, String street})> reverse(double lat, double lng) async {
    final json = asJson(await _api.get('/geo/places/reverse', query: {'lat': lat, 'lng': lng}, auth: false));
    return (area: str(json['area']), street: str(json['street']));
  }
}
