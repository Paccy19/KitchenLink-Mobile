import 'package:geolocator/geolocator.dart';

typedef Position = ({double lat, double lng, double? accuracyM});

const bool gpsSupported = true;

/// One reading from the phone's GPS (null when location is off, refused or
/// does not come in time), like the browser's geolocation on the website.
Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return (lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy);
    } catch (_) {
      // A fresh fix did not come in time: the last known one is still close.
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : (lat: last.latitude, lng: last.longitude, accuracyM: last.accuracy);
    }
  } catch (_) {
    return null;
  }
}
