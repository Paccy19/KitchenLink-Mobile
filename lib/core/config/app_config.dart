import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration.
///
/// The API address is chosen when the app is started/built, never by editing
/// source files:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1
///   flutter run --dart-define-from-file=env/phone.json
///
/// Defaults to the Android emulator's address for the host computer (a phone
/// or emulator can never reach the computer through `localhost`), or to
/// `localhost` in the browser.
///
/// This is the one place every role (marketplace, admin, kitchen, delivery)
/// reads the API address from, so an address saved on the sign-in screen is
/// used by all of them.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  /// Android emulator → host computer.
  static const String emulatorApiBaseUrl = 'http://10.0.2.2:4000/api/v1';

  /// The browser runs on the development computer itself.
  static const String webApiBaseUrl = 'http://localhost:4000/api/v1';

  // No defaultValue: `--dart-define=API_BASE_URL=` (an empty value, as in a
  // defines file with `"API_BASE_URL": ""`) must fall back to the default
  // too, instead of becoming an empty base URL that breaks every request.
  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String? _override;

  /// An address typed in the app (saved on the phone). It wins over the
  /// build-time default until it is reset.
  static void overrideApiBaseUrl(String? url) => _override = url;

  static String get defaultApiBaseUrl => _fromEnvironment.isNotEmpty
      ? _fromEnvironment
      : kIsWeb
          ? webApiBaseUrl
          : emulatorApiBaseUrl;

  /// CARTO basemap key (the website's `VITE_CARTO_API_KEY`), from
  /// `--dart-define=CARTO_API_KEY=…` or `--dart-define-from-file=dart_defines.json`.
  static const String cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

  /// CARTO Voyager raster tiles, the basemap the website draws, used by every
  /// map in the app (delivery worker trip, admin pages). CARTO reads the key
  /// from `?key=` (like the website's style URL); any other name, or no key,
  /// gets its grey "API KEY REQUIRED" placeholder tiles.
  static String get cartoTileUrl =>
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
      '${cartoApiKey.isEmpty ? '' : '?key=${Uri.encodeQueryComponent(cartoApiKey)}'}';

  /// Configuration used by the running app.
  static AppConfig get current => AppConfig(apiBaseUrl: _override ?? defaultApiBaseUrl);

  /// Full API address including `/api/v1`, without a trailing slash.
  final String apiBaseUrl;

  /// Scheme + host (+ port) of the server, used for relative upload paths.
  Uri get origin {
    final uri = Uri.parse(apiBaseUrl);
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  /// Seconds the app waits before giving up on a request.
  static const int connectTimeoutSeconds = 15;
  static const int receiveTimeoutSeconds = 30;
}
