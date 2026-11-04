/// Build-time configuration.
///
/// The API address is chosen when the app is started/built, never by editing
/// source files:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1
///   flutter run --dart-define-from-file=env/phone.json
///
/// Defaults to the Android emulator's address for the host computer. A phone
/// or emulator can never reach the computer through `localhost`.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  /// Android emulator → host computer.
  static const String emulatorApiBaseUrl = 'http://10.0.2.2:4000/api/v1';

  static const String _fromEnvironment = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: emulatorApiBaseUrl,
  );

  /// Configuration used by the running app.
  static const AppConfig current = AppConfig(apiBaseUrl: _fromEnvironment);

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
