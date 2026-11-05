import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'gps.dart';

class Neighborhood {
  const Neighborhood(this.id, this.name, this.district, this.lat, this.lng);

  final String id;
  final String name;
  final String district;
  final double lat;
  final double lng;
}

/// The website's KIGALI_NEIGHBORHOODS (context/LocationContext.jsx).
const kigaliNeighborhoods = [
  Neighborhood('kimironko', 'Kimironko', 'Gasabo', -1.9597, 30.0587),
  Neighborhood('remera', 'Remera (Gisimenti)', 'Gasabo', -1.9547, 30.0667),
  Neighborhood('nyarutarama', 'Nyarutarama', 'Gasabo', -1.9553, 30.0547),
  Neighborhood('kiyovu', 'Kiyovu', 'Nyarugenge', -1.9477, 30.061),
  Neighborhood('kacyiru', 'Kacyiru', 'Gasabo', -1.9437, 30.0747),
  Neighborhood('gisozi', 'Gisozi', 'Gasabo', -1.9307, 30.0657),
  Neighborhood('gikondo', 'Gikondo', 'Kicukiro', -1.9687, 30.0717),
  Neighborhood('downtown', 'Downtown / CBD', 'Nyarugenge', -1.9517, 30.0627),
  Neighborhood('kanombe', 'Kanombe', 'Kicukiro', -1.9637, 30.0937),
  Neighborhood('kabeza', 'Kabeza', 'Kicukiro', -1.9607, 30.0827),
];

const kigaliDistricts = ['Gasabo', 'Kicukiro', 'Nyarugenge'];

const kigaliDefaultLabel = 'Kigali City Centre';

enum LocationSource { defaultCentre, gps, manual }

enum LocationStatus { idle, requesting, denied }

/// Where the customer is browsing from, like the website's LocationContext:
/// the Kigali-centre fallback, a picked neighbourhood, or the GPS position.
/// The choice and the "primer was shown" flag are saved on the device.
class ClientLocation extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _savedKey = 'ofk_saved_location';
  static const _primerKey = 'ofk_location_primer_v1';

  /// Device storage can be slow or unavailable: never hold up the home page for it.
  static const _readLimit = Duration(seconds: 2);

  double lat = kKigaliLat;
  double lng = kKigaliLng;
  String label = kigaliDefaultLabel;
  LocationSource source = LocationSource.defaultCentre;
  LocationStatus status = LocationStatus.idle;
  int? accuracyM;
  bool primerOpen = false;
  bool restored = false;

  /// The Kigali-centre fallback is not the customer's position.
  bool get isLocated => source != LocationSource.defaultCentre;
  bool get isGps => source == LocationSource.gps;
  bool get isUsingFallback => source == LocationSource.defaultCentre;

  Future<void> restore() async {
    try {
      final saved = await _storage.read(key: _savedKey).timeout(_readLimit);
      if (saved != null && saved.isNotEmpty) {
        final parts = saved.split('|');
        if (parts.length == 4) {
          lat = double.tryParse(parts[0]) ?? lat;
          lng = double.tryParse(parts[1]) ?? lng;
          source = parts[2] == 'gps' ? LocationSource.gps : LocationSource.manual;
          label = parts[3];
        }
      }
      primerOpen = (await _storage.read(key: _primerKey).timeout(_readLimit)) == null && !isLocated;
    } catch (_) {
      primerOpen = !isLocated;
    }
    restored = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _storage.write(key: _savedKey, value: '$lat|$lng|${source == LocationSource.gps ? 'gps' : 'manual'}|$label');
    } catch (_) {}
  }

  Future<void> _primerSeen() async {
    primerOpen = false;
    try {
      await _storage.write(key: _primerKey, value: '1');
    } catch (_) {}
  }

  /// "Continue with Kigali city centre".
  Future<void> dismissPrimer() async {
    await _primerSeen();
    notifyListeners();
  }

  /// "Use my location" on the primer.
  Future<bool> enableFromPrimer() async {
    final ok = await requestGps();
    await _primerSeen();
    notifyListeners();
    return ok;
  }

  void selectNeighborhood(Neighborhood area) {
    lat = area.lat;
    lng = area.lng;
    label = '${area.name}, Kigali';
    source = LocationSource.manual;
    accuracyM = null;
    status = LocationStatus.idle;
    _save();
    notifyListeners();
  }

  /// Measures the position once. Returns false when it isn't available
  /// (denied, or GPS isn't supported on this device yet).
  Future<bool> requestGps() async {
    status = LocationStatus.requesting;
    notifyListeners();
    final position = await currentPosition();
    if (position == null) {
      status = LocationStatus.denied;
      notifyListeners();
      return false;
    }
    lat = position.lat;
    lng = position.lng;
    accuracyM = position.accuracyM?.round();
    label = 'Your current location';
    source = LocationSource.gps;
    status = LocationStatus.idle;
    _save();
    notifyListeners();
    return true;
  }
}

/// True when this build can read the device position.
bool get gpsAvailable => kIsWeb && gpsSupported;
