import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_config.dart';

/// Turns what a person types into an API address, or null when it is not a
/// web address. `192.168.1.20:4000` → `http://192.168.1.20:4000/api/v1`.
String? normalizeApiBaseUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty) path = '/api/v1';
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Remembers the server address chosen in the app, so a phone can be pointed
/// at a computer on the same Wi-Fi without rebuilding.
class ServerAddressStore {
  ServerAddressStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ofk_api_base_url';
  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String url) => _storage.write(key: _key, value: url);

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  /// Applies a saved address, if any. Call before the first request.
  Future<void> applySaved() async {
    final saved = await read();
    if (saved != null) AppConfig.overrideApiBaseUrl(saved);
  }
}
