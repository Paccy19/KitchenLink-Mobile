import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the signed-in user's bearer token lives between app launches.
///
/// Each app stores only its own role's token under its own key (the vendor
/// app `ofk_vendor_token`, the delivery worker app `ofk_driver_token`), the
/// same keys the website uses, so the two apps never share a session.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain backed storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage, this._key = vendorKey])
      : _storage = storage ?? const FlutterSecureStorage();

  static const vendorKey = 'ofk_vendor_token';
  static const driverKey = 'ofk_driver_token';

  final String _key;
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
