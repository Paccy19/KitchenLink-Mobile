/// The device position: the phone's GPS (geolocator) or the browser's
/// geolocation on the web.
library;

export 'gps_io.dart' if (dart.library.js_interop) 'gps_web.dart';
