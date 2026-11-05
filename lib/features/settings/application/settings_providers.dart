import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/json.dart';
import '../../../core/providers.dart';
import '../../../core/utils/uploads.dart';
import '../../auth/application/session.dart';
import '../../auth/models/vendor_account.dart';
import '../../auth/models/vendor_type.dart';
import '../data/settings_repository.dart';
import '../models/event_package.dart';
import '../models/place.dart';

final orderingProvider = FutureProvider.autoDispose<OrderingRules>(
  (ref) => ref.watch(settingsRepositoryProvider).ordering(),
);

final nationwideProvider = FutureProvider.autoDispose<NationwideInfo>(
  (ref) => ref.watch(settingsRepositoryProvider).nationwide(),
);

final eventPackageProvider = FutureProvider.autoDispose<EventPackageSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).eventPackage(),
);

final vendorTypesProvider = FutureProvider.autoDispose<List<VendorType>>(
  (ref) => ref.watch(authRepositoryProvider).vendorTypes(),
);

/// Every settings write. Responses that carry the account update the
/// signed-in vendor so every screen shows the new values.
class SettingsActions {
  SettingsActions(this._ref);
  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  /// Opens or closes the store.
  Future<VendorAccount> setStoreOpen(bool open) => _apply(_repo.setAvailability(isOpen: open));

  Future<VendorAccount> updateProfile(Json fields) => _apply(_repo.updateProfile(fields));

  Future<VendorAccount> updateImages({
    PickedUpload? banner,
    PickedUpload? profile,
    void Function(int sent, int total)? onProgress,
  }) =>
      _apply(_repo.updateImages(banner: banner, profile: profile, onProgress: onProgress));

  Future<VendorAccount> requestTypeChange(String vendorType, String reason) =>
      _apply(_repo.requestTypeChange(vendorType: vendorType, reason: reason));

  Future<VendorAccount> cancelTypeChange() => _apply(_repo.cancelTypeChange());

  Future<void> saveOrdering({int? dailyOrderLimit, int? minOrderRwf, required bool sendDailyLimit}) async {
    await _repo.saveOrdering(
      dailyOrderLimit: dailyOrderLimit,
      minOrderRwf: minOrderRwf,
      sendDailyLimit: sendDailyLimit,
    );
    _ref.invalidate(orderingProvider);
    await _ref.read(sessionProvider.notifier).refreshVendor();
  }

  Future<void> saveNationwide({int? travelBaseFeeRwf, int? travelPerKmRwf}) async {
    await _repo.saveNationwide(travelBaseFeeRwf: travelBaseFeeRwf, travelPerKmRwf: travelPerKmRwf);
    _ref.invalidate(nationwideProvider);
    await _ref.read(sessionProvider.notifier).refreshVendor();
  }

  Future<void> saveEventPackage(EventPackageSettings settings) async {
    await _repo.saveEventPackage(settings);
    _ref.invalidate(eventPackageProvider);
  }

  Future<List<PlaceSuggestion>> placeSuggestions(String query, {double? lat, double? lng}) =>
      _repo.placeSuggestions(query, lat: lat, lng: lng);

  Future<Place> placeDetails(String id) => _repo.placeDetails(id);

  Future<VendorAccount> _apply(Future<VendorAccount> request) async {
    final vendor = await request;
    _ref.read(sessionProvider.notifier).applyVendor(vendor);
    return vendor;
  }
}

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);
