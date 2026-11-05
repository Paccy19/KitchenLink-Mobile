import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the vendor's bearer token lives between app launches.
///
/// Only the vendor token is ever stored: the customer, delivery and admin
/// tokens of the web app have no place in this app.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain backed storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ofk_vendor_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      // A corrupted keystore entry must not trap the vendor on a blank screen.
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing more to clear.
    }
  }
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
