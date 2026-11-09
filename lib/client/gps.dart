/// The device position: the browser's geolocation on the web. On a phone it
/// is not available yet (that needs a location package and permissions), so
/// customers pick a neighbourhood instead.
library;

export 'gps_io.dart' if (dart.library.js_interop) 'gps_web.dart';
