import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Whether the app may read the phone's position.
enum LocationAccess {
  granted,

  /// Asked and refused; can be asked again.
  denied,

  /// Refused for good: only the phone's settings can change it.
  deniedForever,

  /// Location services are switched off on the phone.
  serviceOff,
}

/// One GPS reading.
class GeoFix {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speedMps,
    this.accuracyM,
    required this.at,
  });

  final double latitude;
  final double longitude;
  final double? heading;
  final double? speedMps;
  final double? accuracyM;
  final DateTime at;

  /// Straight-line metres to [other].
  double metresTo(GeoFix other) {
    double rad(double deg) => deg * math.pi / 180;
    final x = rad(other.longitude - longitude) * math.cos(rad((latitude + other.latitude) / 2));
    final y = rad(other.latitude - latitude);
    return math.sqrt(x * x + y * y) * 6371000;
  }

  /// Compass bearing to [other], for phones that report no heading.
  double bearingTo(GeoFix other) {
    double rad(double deg) => deg * math.pi / 180;
    final y = math.sin(rad(other.longitude - longitude)) * math.cos(rad(other.latitude));
    final x = math.cos(rad(latitude)) * math.sin(rad(other.latitude)) -
        math.sin(rad(latitude)) * math.cos(rad(other.latitude)) * math.cos(rad(other.longitude - longitude));
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

/// The phone's GPS, behind an interface so the duty logic can be tested.
abstract interface class LocationService {
  /// Checks (and, with [request], asks for) permission to read the position.
  Future<LocationAccess> ensureAccess({bool request = true});

  /// One fresh reading, or null when none arrives in time.
  Future<GeoFix?> current();

  /// Continuous readings while a delivery is in progress.
  Stream<GeoFix> watch();

  /// Opens the phone settings that fix [access].
  Future<void> openSettings(LocationAccess access);
}

class DeviceLocationService implements LocationService {
  @override
  Future<LocationAccess> ensureAccess({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAccess.granted;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  }

  @override
  Future<GeoFix?> current() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      return _fix(position);
    } catch (_) {
      // Fall back to the last known fix when a fresh one does not come in time.
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last == null ? null : _fix(last);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Stream<GeoFix> watch() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).map(_fix);

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  GeoFix _fix(Position position) => GeoFix(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading.isFinite && position.heading >= 0 && position.speed > 0.5 ? position.heading : null,
        speedMps: position.speed.isFinite && position.speed >= 0 ? position.speed : null,
        accuracyM: position.accuracy.isFinite ? position.accuracy : null,
        at: position.timestamp,
      );
}

final locationServiceProvider = Provider<LocationService>((ref) => DeviceLocationService());

/// When a live fix is worth sending during a delivery: at most every 4 s when
/// the rider moved 8 m or more, and at least every 15 s while standing still
/// (the website's `LIVE_SEND_*` rules). Pure, so it can be tested.
bool shouldSendLiveFix({required GeoFix fix, GeoFix? lastSent}) {
  if (lastSent == null) return true;
  final since = fix.at.difference(lastSent.at);
  if (since < const Duration(seconds: 4)) return false;
  return fix.metresTo(lastSent) >= 8 || since >= const Duration(seconds: 15);
}
