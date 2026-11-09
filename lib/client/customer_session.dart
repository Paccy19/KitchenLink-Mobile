import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';

/// The signed-in customer (phone + SMS code), like the website's AuthContext.
class CustomerSession extends ChangeNotifier {
  CustomerSession(this.client);

  // Same key as the website's localStorage entry.
  static const _tokenKey = 'ofk_access_token';
  static const _nameKey = 'ofk_customer_name';
  static const _phoneKey = 'ofk_customer_phone';
  static const _storage = FlutterSecureStorage();

  final ApiClient client;

  String? token;
  String name = '';
  String phone = '';

  bool get isSignedIn => token?.isNotEmpty ?? false;

  /// "Jean Paul" → "Jean".
  String get firstName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  }

  Future<void> restore() async {
    try {
      token = await _storage.read(key: _tokenKey);
      client.token = token;
      name = await _storage.read(key: _nameKey) ?? '';
      phone = await _storage.read(key: _phoneKey) ?? '';
    } catch (error) {
      debugPrint('Could not restore the customer session: $error');
    }
    notifyListeners();
  }

  /// POST /auth/send-otp. Returns the number the code went to and, on a
  /// development server, the code itself.
  Future<({String phone, String devOtp})> sendOtp(
    String phoneNumber,
    String fullName,
  ) async {
    final data = await client.request(
      '/auth/send-otp',
      method: 'POST',
      body: {
        'phone_number': phoneNumber,
        if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
      },
    );
    final json = data is Map ? data : const {};
    return (
      phone: (json['phone_number'] ?? phoneNumber).toString(),
      devOtp: (json['dev_otp'] ?? '').toString(),
    );
  }

  /// POST /auth/verify-otp: signs in (creating the account the first time).
  Future<void> verifyOtp(
    String phoneNumber,
    String code,
    String fullName,
  ) async {
    final data = await client.request(
      '/auth/verify-otp',
      method: 'POST',
      body: {
        'phone_number': phoneNumber,
        'code': code,
        if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
      },
    );
    final json = data is Map ? data : const {};
    final newToken = (json['token'] ?? '').toString();
    if (newToken.isEmpty) {
      throw ApiException('Sign-in failed. Please try again.');
    }
    final customer = json['customer'] is Map
        ? json['customer'] as Map
        : const {};
    token = newToken;
    client.token = newToken;
    name = (customer['name'] ?? fullName).toString();
    phone = (customer['phone_number'] ?? phoneNumber).toString();
    try {
      await Future.wait([
        _storage.write(key: _tokenKey, value: token),
        _storage.write(key: _nameKey, value: name),
        _storage.write(key: _phoneKey, value: phone),
      ]);
    } catch (error) {
      debugPrint('Could not persist the customer session: $error');
    }
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    client.token = null;
    name = '';
    phone = '';
    try {
      await Future.wait([
        _storage.delete(key: _tokenKey),
        _storage.delete(key: _nameKey),
        _storage.delete(key: _phoneKey),
      ]);
    } catch (error) {
      debugPrint('Could not clear the stored customer session: $error');
    }
    notifyListeners();
  }
}
