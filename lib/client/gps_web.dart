import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

typedef Position = ({double lat, double lng, double? accuracyM});

const bool gpsSupported = true;

/// One reading from the browser's geolocation (null when refused or failed).
Future<Position?> currentPosition() {
  final done = Completer<Position?>();
  try {
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition p) {
        if (!done.isCompleted) {
          done.complete((lat: p.coords.latitude.toDouble(), lng: p.coords.longitude.toDouble(), accuracyM: p.coords.accuracy.toDouble()));
        }
      }).toJS,
      ((web.GeolocationPositionError _) {
        if (!done.isCompleted) done.complete(null);
      }).toJS,
      web.PositionOptions(enableHighAccuracy: true, timeout: 15000, maximumAge: 60000),
    );
  } catch (_) {
    if (!done.isCompleted) done.complete(null);
  }
  return done.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
}
