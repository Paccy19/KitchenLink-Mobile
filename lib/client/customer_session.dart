import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';

/// The signed-in customer (phone + SMS code), like the website's AuthContext.
class CustomerSession extends ChangeNotifier {
  CustomerSession(this.client);

  // Same key as the website's localStorage entry.
  static const _tokenKey = 'ofk_access_token';
  static const _nameKey = 'ofk_customer_name';
  static const _storage = FlutterSecureStorage();

  final ApiClient client;

  String? token;
  String name = '';
  String phone = '';

  bool get isSignedIn => token != null && token!.isNotEmpty;

  /// "Jean Paul" → "Jean".
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  Future<void> restore() async {
    try {
      token = await _storage.read(key: _tokenKey);
      name = await _storage.read(key: _nameKey) ?? '';
    } catch (_) {
      // Storage unavailable: stay signed out.
    }
    notifyListeners();
  }

  /// POST /auth/send-otp. Returns the number the code went to and, on a
  /// development server, the code itself.
  Future<({String phone, String devOtp})> sendOtp(String phoneNumber, String fullName) async {
    final data = await client.request('/auth/send-otp', method: 'POST', body: {
      'phone_number': phoneNumber,
      if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
    });
    final json = data is Map ? data : const {};
    return (
      phone: (json['phone_number'] ?? phoneNumber).toString(),
      devOtp: (json['dev_otp'] ?? '').toString(),
    );
  }

  /// POST /auth/verify-otp: signs in (creating the account the first time).
  Future<void> verifyOtp(String phoneNumber, String code, String fullName) async {
    final data = await client.request('/auth/verify-otp', method: 'POST', body: {
      'phone_number': phoneNumber,
      'code': code,
      if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
    });
    final json = data is Map ? data : const {};
    final newToken = (json['token'] ?? '').toString();
    if (newToken.isEmpty) throw ApiException('Sign-in failed. Please try again.');
    final customer = json['customer'] is Map ? json['customer'] as Map : const {};
    token = newToken;
    name = (customer['name'] ?? fullName).toString();
    phone = (customer['phone_number'] ?? phoneNumber).toString();
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _nameKey, value: name);
    } catch (_) {
      // Signed in for this session only.
    }
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    name = '';
    phone = '';
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _nameKey);
    } catch (_) {}
    notifyListeners();
  }
}
