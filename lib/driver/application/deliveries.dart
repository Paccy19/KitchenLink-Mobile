import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/json.dart';
import '../../core/polled_notifier.dart';
import '../../core/providers.dart';
import '../../core/utils/uploads.dart';
import '../../features/wallet/application/wallet_providers.dart';
import '../data/driver_repository.dart';
import '../models/delivery.dart';
import '../models/driver_account.dart';
import '../models/driver_notification.dart';
import '../models/navigation.dart';
import 'location.dart';
import 'session.dart';

/* --------------------------------- numbers -------------------------------- */

class DriverStatsNotifier extends PolledNotifier<DriverStats> {
  @override
  Duration? get pollInterval => const Duration(seconds: 10);

  @override
  Future<DriverStats> fetch() async {
    final stats = await ref.read(driverRepositoryProvider).stats();
    // The server is the truth for on/offline (an admin or a timeout can change it).
    ref.read(driverSessionProvider.notifier).applyOnline(
          online: stats.isOnline,
          status: stats.status,
          activeDeliveries: stats.activeDeliveries,
        );
    return stats;
  }
}

final driverStatsProvider =
    AsyncNotifierProvider.autoDispose<DriverStatsNotifier, DriverStats>(DriverStatsNotifier.new);

/* ---------------------------------- offers -------------------------------- */

/// A new offer appeared on the board while the app is open.
class OfferAlert {
  const OfferAlert(this.offer, this.count);
  final Delivery offer;
  final int count;
}

class OfferAlertNotifier extends Notifier<OfferAlert?> {
  @override
  OfferAlert? build() => null;

  void raise(OfferAlert alert) => state = alert;
}

final offerAlertProvider = NotifierProvider<OfferAlertNotifier, OfferAlert?>(OfferAlertNotifier.new);

/// The offer board. Only loads while the worker is online; refreshes every
/// 10 seconds like the website, and raises [offerAlertProvider] for offers
/// that were not on the board before.
class OffersNotifier extends PolledNotifier<List<Delivery>> {
  final Set<String> _known = {};
  bool _primed = false;

  @override
  Duration? get pollInterval => const Duration(seconds: 10);

  @override
  Future<List<Delivery>> build() {
    // On or off duty changed (here, by an admin, or by the server): reload.
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous != next) unawaited(reload());
    });
    return super.build();
  }

  @override
  Future<List<Delivery>> fetch() async {
    if (!ref.read(isOnlineProvider)) {
      _known.clear();
      _primed = false;
      return const [];
    }
    final fix = ref.read(lastFixProvider);
    final offers = await ref
        .read(driverRepositoryProvider)
        .available(latitude: fix?.latitude, longitude: fix?.longitude);
    final fresh = offers.where((offer) => !_known.contains(offer.id)).toList();
    if (_primed && fresh.isNotEmpty) {
      ref.read(offerAlertProvider.notifier).raise(OfferAlert(fresh.first, offers.length));
    }
    _known
      ..clear()
      ..addAll(offers.map((offer) => offer.id));
    _primed = true;
    return offers;
  }

  /// Takes an offer off the board at once (accepted, declined, or gone).
  void remove(String id) {
    final current = state.value;
    if (current != null) put([for (final offer in current) if (offer.id != id) offer]);
  }
}

final offersProvider = AsyncNotifierProvider<OffersNotifier, List<Delivery>>(OffersNotifier.new);

/* ----------------------------------- trip --------------------------------- */

class ActiveTripNotifier extends PolledNotifier<Delivery?> {
  @override
  Duration? get pollInterval => const Duration(seconds: 10);

  @override
  Future<Delivery?> fetch() => ref.read(driverRepositoryProvider).active();
}

/// The delivery in progress (null when there is none).
final activeTripProvider = AsyncNotifierProvider<ActiveTripNotifier, Delivery?>(ActiveTripNotifier.new);

class TripNavigationNotifier extends PolledNotifier<TripNavigation> {
  TripNavigationNotifier(this.deliveryId);
  final String deliveryId;

  @override
  Duration? get pollInterval => const Duration(seconds: 6);

  @override
  Future<TripNavigation> fetch() => ref.read(driverRepositoryProvider).navigation(deliveryId);
}

/// Route, distance and ETA to the kitchen, then the customer.
final tripNavigationProvider = AsyncNotifierProvider.autoDispose
    .family<TripNavigationNotifier, TripNavigation, String>(TripNavigationNotifier.new);

/* --------------------------------- history -------------------------------- */

class HistoryState {
  const HistoryState({required this.items, required this.meta, this.loadingMore = false});

  final List<Delivery> items;
  final PageMeta meta;
  final bool loadingMore;

  bool get hasMore => meta.hasMore;
}

class HistoryNotifier extends AsyncNotifier<HistoryState> {
  static const int pageSize = 20;

  @override
  Future<HistoryState> build() async {
    final page = await ref.read(driverRepositoryProvider).history(limit: pageSize);
    return HistoryState(items: page.deliveries, meta: page.meta);
  }

  Future<void> reload() async {
    final page = await ref.read(driverRepositoryProvider).history(limit: pageSize);
    if (ref.mounted) state = AsyncData(HistoryState(items: page.deliveries, meta: page.meta));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(HistoryState(items: current.items, meta: current.meta, loadingMore: true));
    try {
      final page = await ref.read(driverRepositoryProvider).history(page: current.meta.page + 1, limit: pageSize);
      final seen = current.items.map((d) => d.id).toSet();
      if (!ref.mounted) return;
      state = AsyncData(HistoryState(
        items: [...current.items, ...page.deliveries.where((d) => !seen.contains(d.id))],
        meta: page.meta,
      ));
    } catch (_) {
      if (ref.mounted) state = AsyncData(HistoryState(items: current.items, meta: current.meta));
      rethrow;
    }
  }
}

final historyProvider = AsyncNotifierProvider.autoDispose<HistoryNotifier, HistoryState>(HistoryNotifier.new);

class EarningsNotifier extends PolledNotifier<DriverEarnings> {
  @override
  Duration? get pollInterval => const Duration(seconds: 30);

  @override
  Future<DriverEarnings> fetch() => ref.read(driverRepositoryProvider).earnings();
}

final earningsProvider = AsyncNotifierProvider.autoDispose<EarningsNotifier, DriverEarnings>(EarningsNotifier.new);

/* ------------------------------ notifications ----------------------------- */

class DriverNotificationsNotifier extends PolledNotifier<DriverNotificationList> {
  final Set<String> _known = {};
  bool _primed = false;

  @override
  Duration? get pollInterval => const Duration(seconds: 15);

  @override
  Future<DriverNotificationList> fetch() async {
    final list = await ref.read(driverRepositoryProvider).notifications();
    final fresh = list.items.where((n) => !n.read && !_known.contains(n.id)).toList();
    _known.addAll(list.items.map((n) => n.id));
    if (_primed) {
      // Food ready, reminders, a trip taken or cancelled: show it and refresh.
      final trip = fresh.where((n) => n.isTripUpdate || n.endsTrip).toList();
      if (trip.isNotEmpty) {
        unawaited(ref.read(activeTripProvider.notifier).reload());
        ref.read(tripAlertProvider.notifier).raise(trip.first);
      }
      if (fresh.any((n) => n.isMoney)) ref.invalidate(walletProvider);
    }
    _primed = true;
    return list;
  }

  Future<void> markRead(String id) async {
    await ref.read(driverRepositoryProvider).markNotificationRead(id);
    final current = state.value;
    if (current == null) return;
    final items = [for (final n in current.items) n.id == id ? n.markedRead() : n];
    put(DriverNotificationList(items: items, unreadCount: items.where((n) => !n.read).length));
  }

  Future<void> markAllRead() async {
    await ref.read(driverRepositoryProvider).markAllNotificationsRead();
    final current = state.value;
    if (current != null) {
      put(DriverNotificationList(items: [for (final n in current.items) n.markedRead()]));
    }
  }
}

final driverNotificationsProvider =
    AsyncNotifierProvider<DriverNotificationsNotifier, DriverNotificationList>(DriverNotificationsNotifier.new);

class TripAlertNotifier extends Notifier<DriverNotification?> {
  @override
  DriverNotification? build() => null;

  void raise(DriverNotification notification) => state = notification;
}

/// A trip update (food ready, late, taken, cancelled) that just arrived.
final tripAlertProvider = NotifierProvider<TripAlertNotifier, DriverNotification?>(TripAlertNotifier.new);

/* ---------------------------------- GPS ----------------------------------- */

class LastFixNotifier extends Notifier<GeoFix?> {
  @override
  GeoFix? build() => null;

  void set(GeoFix fix) => state = fix;
}

/// The newest position read on this phone (null until one arrives).
final lastFixProvider = NotifierProvider<LastFixNotifier, GeoFix?>(LastFixNotifier.new);

enum TrackingMode {
  /// Signed out, offline, or the app is in the background: no GPS at all.
  off,

  /// Online and waiting for offers: the position is sent once a minute.
  waiting,

  /// On a delivery: live tracking so the customer can follow the rider.
  live,
}

final trackingModeProvider = Provider<TrackingMode>((ref) {
  if (!ref.watch(driverSessionProvider).isAuthenticated) return TrackingMode.off;
  if (!ref.watch(appActiveProvider)) return TrackingMode.off;
  final onTrip = ref.watch(activeTripProvider).value != null;
  if (onTrip) return TrackingMode.live;
  return ref.watch(isOnlineProvider) ? TrackingMode.waiting : TrackingMode.off;
});

class TrackingState {
  const TrackingState({this.access, this.message});

  /// Null until the app has checked.
  final LocationAccess? access;

  /// Why positions are not being sent right now, for a banner.
  final String? message;
}

/// Sends the worker's position while on duty, so offers come from kitchens
/// really near them and the customer can follow the delivery. Foreground only.
class LocationTracker extends Notifier<TrackingState> {
  Timer? _timer;
  StreamSubscription<GeoFix>? _stream;
  GeoFix? _lastSent;
  GeoFix? _previous;
  int _generation = 0;

  LocationService get _gps => ref.read(locationServiceProvider);
  DriverRepository get _repo => ref.read(driverRepositoryProvider);

  @override
  TrackingState build() {
    ref.onDispose(_stop);
    ref.listen<TrackingMode>(trackingModeProvider, (_, mode) => unawaited(_apply(mode)), fireImmediately: true);
    return const TrackingState();
  }

  /// Checks permission again (after the worker changed it in Settings).
  Future<LocationAccess> recheck({bool request = true}) async {
    final access = await _gps.ensureAccess(request: request);
    if (!ref.mounted) return access;
    state = TrackingState(access: access, message: _messageFor(access));
    if (access == LocationAccess.granted) unawaited(_apply(ref.read(trackingModeProvider)));
    return access;
  }

  /// Sends one position now (going online, the "share location" button).
  Future<GeoFix?> shareNow() async {
    final access = await recheck();
    if (access != LocationAccess.granted) return null;
    final fix = await _gps.current();
    if (fix == null || !ref.mounted) {
      if (ref.mounted) state = TrackingState(access: access, message: 'Waiting for GPS. Move to an open area if this takes long.');
      return null;
    }
    await _send(fix);
    return fix;
  }

  Future<void> _apply(TrackingMode mode) async {
    // The mode can change while the permission check below is pending (the
    // app goes inactive → resumed when the notification shade is pulled
    // down). Only the newest call may start GPS; an older one that started a
    // timer or stream after a newer one would leave it running untracked,
    // sending positions forever, even after going offline.
    _stop(); // also invalidates every older call still waiting
    final generation = _generation;
    if (mode == TrackingMode.off) return;
    final access = await _gps.ensureAccess(request: false);
    if (!ref.mounted || generation != _generation) return;
    state = TrackingState(access: access, message: _messageFor(access));
    if (access != LocationAccess.granted || ref.read(trackingModeProvider) != mode) return;

    if (mode == TrackingMode.waiting) {
      Future<void> tick() async {
        final fix = await _gps.current();
        if (fix != null && ref.mounted && generation == _generation) await _send(fix);
      }

      unawaited(tick());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(tick()));
    } else {
      _stream = _gps.watch().listen(
        (raw) {
          // Phones only report a heading while moving; derive it otherwise.
          var fix = raw;
          final previous = _previous;
          if (fix.heading == null && previous != null && fix.metresTo(previous) >= 4) {
            fix = GeoFix(
              latitude: fix.latitude,
              longitude: fix.longitude,
              heading: previous.bearingTo(fix),
              speedMps: fix.speedMps,
              accuracyM: fix.accuracyM,
              at: fix.at,
            );
          }
          _previous = fix;
          ref.read(lastFixProvider.notifier).set(fix);
          if (state.message != null) state = TrackingState(access: state.access);
          if (shouldSendLiveFix(fix: fix, lastSent: _lastSent)) unawaited(_send(fix));
        },
        onError: (_) {
          if (ref.mounted) {
            state = TrackingState(access: state.access, message: 'Waiting for GPS. Move to an open area if this takes long.');
          }
        },
      );
    }
  }

  Future<void> _send(GeoFix fix) async {
    _lastSent = fix;
    ref.read(lastFixProvider.notifier).set(fix);
    try {
      await _repo.updateLocation(
        latitude: fix.latitude,
        longitude: fix.longitude,
        heading: fix.heading,
        speedMps: fix.speedMps,
        accuracyM: fix.accuracyM,
      );
    } on ApiException {
      // The next fix tries again.
    }
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    unawaited(_stream?.cancel());
    _stream = null;
  }

  String? _messageFor(LocationAccess access) {
    switch (access) {
      case LocationAccess.granted:
        return null;
      case LocationAccess.serviceOff:
        return 'Location is switched off on this phone. Offers near you and live tracking need it.';
      case LocationAccess.denied:
      case LocationAccess.deniedForever:
        return 'KitchenLink cannot see your location. Allow it so you get offers near you.';
    }
  }
}

final locationTrackerProvider = NotifierProvider<LocationTracker, TrackingState>(LocationTracker.new);

/* --------------------------------- actions -------------------------------- */

/// What happened when the worker switched duty on or off.
class DutyChange {
  const DutyChange({required this.online, this.reassigned = 0, this.locationShared = true});
  final bool online;
  final int reassigned;
  final bool locationShared;
}

/// Every write the worker makes. Each one refreshes what it changed, and the
/// app only reports success once the server has accepted it.
class DriverActions {
  DriverActions(this._ref);
  final Ref _ref;

  DriverRepository get _repo => _ref.read(driverRepositoryProvider);

  Future<DutyChange> setOnline(bool online) async {
    var shared = true;
    if (online) {
      // Share the position first, so the very first offers are near the rider.
      shared = await _ref.read(locationTrackerProvider.notifier).shareNow() != null;
    }
    final result = await _repo.setAvailability(online: online);
    _ref.read(driverSessionProvider.notifier).apply(result.driver);
    _ref.invalidate(driverStatsProvider);
    unawaited(_ref.read(offersProvider.notifier).reload());
    if (!online) unawaited(_ref.read(activeTripProvider.notifier).reload());
    return DutyChange(online: online, reassigned: result.reassigned, locationShared: shared);
  }

  /// First to accept wins. A lost race takes the offer off the board.
  Future<Delivery> accept(String deliveryId) async {
    try {
      final delivery = await _repo.accept(deliveryId);
      _ref.read(activeTripProvider.notifier).put(delivery);
      _ref.read(offersProvider.notifier).remove(deliveryId);
      _ref.invalidate(driverStatsProvider);
      return delivery;
    } on ApiException {
      _ref.read(offersProvider.notifier).remove(deliveryId);
      unawaited(_ref.read(offersProvider.notifier).reload());
      rethrow;
    }
  }

  Future<void> decline(String deliveryId) async {
    await _repo.decline(deliveryId);
    _ref.read(offersProvider.notifier).remove(deliveryId);
  }

  /// Picked up, or out for delivery.
  Future<Delivery> advance(Delivery delivery, String toStatus) async {
    try {
      final updated = await _repo.updateStatus(delivery.id, toStatus);
      _ref.read(activeTripProvider.notifier).put(updated);
      _ref.invalidate(tripNavigationProvider(delivery.id));
      return updated;
    } on ApiException {
      // The trip may have changed on the server (cancelled, reassigned).
      unawaited(_ref.read(activeTripProvider.notifier).reload());
      rethrow;
    }
  }

  Future<DeliveryCompletion> confirmDelivery(Delivery delivery, {required String code, PickedUpload? photo}) async {
    final photoUri = photo == null ? null : await photoAsDataUri(photo);
    final completion = await _repo.confirmDelivery(delivery.id, code: code, photoDataUri: photoUri);
    _ref.read(activeTripProvider.notifier).put(null);
    _ref.invalidate(driverStatsProvider);
    _ref.invalidate(earningsProvider);
    _ref.invalidate(historyProvider);
    _ref.invalidate(walletProvider);
    unawaited(_ref.read(driverSessionProvider.notifier).refresh());
    return completion;
  }

  Future<DriverAccount> updateProfile({String? name, String? email, VehicleType? vehicleType, String? plateNumber}) async {
    final driver = await _repo.updateProfile(name: name, email: email, vehicleType: vehicleType, plateNumber: plateNumber);
    _ref.read(driverSessionProvider.notifier).apply(driver);
    return driver;
  }

  Future<DriverAccount> uploadPhoto(PickedUpload photo) async {
    final driver = await _repo.uploadProfilePhoto(photo);
    _ref.read(driverSessionProvider.notifier).apply(driver);
    return driver;
  }
}

final driverActionsProvider = Provider<DriverActions>(DriverActions.new);
