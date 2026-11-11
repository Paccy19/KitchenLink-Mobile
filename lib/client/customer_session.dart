import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'market_models.dart';

/// The signed-in customer (phone + SMS code), like the website's AuthContext:
/// the profile from the server, plus delivery addresses kept on this device.
class CustomerSession extends ChangeNotifier {
  CustomerSession(this.client) {
    // The server no longer accepts the token (expired or signed out elsewhere).
    client.onUnauthorized = (_) {
      if (isSignedIn) {
        expired = true;
        logout();
      }
    };
  }

  // Same key as the website's localStorage entry.
  static const _tokenKey = 'ofk_access_token';
  static const _nameKey = 'ofk_customer_name';
  static const _phoneKey = 'ofk_customer_phone';
  static const _addressesKey = 'ofk_customer_addresses';
  static const _storage = FlutterSecureStorage();

  final ApiClient client;

  String? token;
  String name = '';
  String phone = '';
  String email = '';
  String avatarUrl = '';
  List<SavedAddress> addresses = [];

  /// True after the server signed this customer out (shown once on screen).
  bool expired = false;

  bool get isSignedIn => token?.isNotEmpty ?? false;

  /// "Jean Paul" → "Jean".
  String get firstName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  }

  SavedAddress? get defaultAddress => addresses.where((a) => a.isDefault).firstOrNull ?? addresses.firstOrNull;

  Future<void> restore() async {
    try {
      token = await _storage.read(key: _tokenKey);
      client.token = token;
      name = await _storage.read(key: _nameKey) ?? '';
      phone = await _storage.read(key: _phoneKey) ?? '';
      final saved = await _storage.read(key: _addressesKey);
      if (saved != null && saved.isNotEmpty) {
        final list = jsonDecode(saved);
        if (list is List) addresses = list.whereType<Map>().map((e) => SavedAddress.fromJson(e.cast<String, dynamic>())).toList();
      }
    } catch (error) {
      debugPrint('Could not restore the customer session: $error');
    }
    notifyListeners();
    if (isSignedIn) refreshProfile();
  }

  void _applyCustomer(Map customer) {
    name = (customer['name'] ?? name).toString();
    phone = (customer['phone_number'] ?? phone).toString();
    email = (customer['email'] ?? '').toString();
    avatarUrl = (customer['profile_image_url'] ?? '').toString();
  }

  /// GET /auth/me: the latest name, phone, email and photo.
  Future<void> refreshProfile() async {
    try {
      final data = await client.request('/auth/me');
      final customer = data is Map ? data['customer'] : null;
      if (customer is Map) {
        _applyCustomer(customer);
        await _persistProfile();
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Could not refresh the customer profile: $error');
    }
  }

  Future<void> _persistProfile() async {
    try {
      await Future.wait([
        _storage.write(key: _nameKey, value: name),
        _storage.write(key: _phoneKey, value: phone),
      ]);
    } catch (_) {}
  }

  /// PATCH /auth/me/profile. Throws the server's message (e.g. the phone is
  /// already used by another customer) and keeps the old details then.
  Future<void> updateProfile({String? newName, String? newPhone, String? newEmail, String? avatarBase64}) async {
    final payload = <String, dynamic>{
      'name': ?newName,
      'phone_number': ?newPhone,
      if (newEmail != null) 'email': newEmail.trim(),
      'profile_image_base64': ?avatarBase64,
    };
    if (payload.isEmpty) return;
    final data = await client.request('/auth/me/profile', method: 'PATCH', body: payload);
    final customer = data is Map ? data['customer'] : null;
    if (customer is Map) _applyCustomer(customer);
    await _persistProfile();
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
    expired = false;
    name = (customer['name'] ?? fullName).toString();
    phone = (customer['phone_number'] ?? phoneNumber).toString();
    email = (customer['email'] ?? '').toString();
    avatarUrl = (customer['profile_image_url'] ?? '').toString();
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
    final old = token;
    token = null;
    client.token = null;
    name = '';
    phone = '';
    email = '';
    avatarUrl = '';
    addresses = [];
    notifyListeners();
    // Sign the token out on the server too, so a copy of it stops working.
    if (old != null && old.isNotEmpty && !expired) {
      final signOut = ApiClient(baseUrl: client.baseUrl)..token = old;
      signOut.request('/auth/logout', method: 'POST').ignore();
    }
    try {
      await Future.wait([
        _storage.delete(key: _tokenKey),
        _storage.delete(key: _nameKey),
        _storage.delete(key: _phoneKey),
        _storage.delete(key: _addressesKey),
      ]);
    } catch (error) {
      debugPrint('Could not clear the stored customer session: $error');
    }
  }

  // ---- Delivery addresses (on this device, like the website) ----

  Future<void> _saveAddresses() async {
    try {
      await _storage.write(key: _addressesKey, value: jsonEncode([for (final a in addresses) a.toJson()]));
    } catch (_) {}
  }

  SavedAddress addAddress({required String title, required String street, required String district, String instructions = ''}) {
    final address = SavedAddress(
      id: 'addr-${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Home' : title.trim(),
      street: street.trim(),
      district: district.trim(),
      instructions: instructions.trim(),
      isDefault: addresses.isEmpty,
    );
    addresses = [...addresses, address];
    _saveAddresses();
    notifyListeners();
    return address;
  }

  void setDefaultAddress(String id) {
    for (final address in addresses) {
      address.isDefault = address.id == id;
    }
    addresses = [...addresses];
    _saveAddresses();
    notifyListeners();
  }

  void deleteAddress(String id) {
    final wasDefault = addresses.any((a) => a.id == id && a.isDefault);
    addresses = addresses.where((a) => a.id != id).toList();
    if (wasDefault && addresses.isNotEmpty) addresses.first.isDefault = true;
    _saveAddresses();
    notifyListeners();
  }
}
