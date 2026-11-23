import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'market_models.dart';

/// Where a sign-in (or verification) code went. [devOtp] is only ever an SMS
/// code from a development server; email codes are never returned.
class OtpSent {
  const OtpSent({required this.identifier, required this.sentTo, required this.isEmail, required this.devOtp});

  final String identifier;
  final String sentTo;
  final bool isEmail;
  final String devOtp;
}

/// The verified phone belongs to an admin: their email + password come next.
class AdminChallenge {
  const AdminChallenge({required this.token, required this.expiresInSeconds});

  final String token;
  final int expiresInSeconds;
}

/// The signed-in customer (phone or email + code), like the website's AuthContext:
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

  /// Only a verified email signs in and receives delivery codes.
  bool emailVerified = false;

  /// A phone given at email sign-up, not verified yet (never used to sign in).
  String pendingPhone = '';
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
    // Null for a customer who signed up with an email and has no verified phone yet.
    phone = (customer['phone_number'] ?? '').toString();
    email = (customer['email'] ?? '').toString();
    avatarUrl = (customer['profile_image_url'] ?? '').toString();
    emailVerified = customer['email_verified'] == true;
    pendingPhone = (customer['pending_phone_number'] ?? '').toString();
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

  /// POST /auth/send-otp with one sign-in field: a phone number or an email
  /// address (the server decides which). [registrationPhone] is the optional
  /// phone of a new customer signing up with an email. Returns where the code
  /// went and, for an SMS code on a development server only, the code itself
  /// (email codes are never returned).
  Future<OtpSent> sendOtp(
    String identifier,
    String fullName, {
    String registrationPhone = '',
  }) async {
    final data = await client.request(
      '/auth/send-otp',
      method: 'POST',
      body: {
        'identifier': identifier.trim(),
        if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
        if (registrationPhone.trim().isNotEmpty) 'phone_number': registrationPhone.trim(),
      },
    );
    final json = data is Map ? data : const {};
    final isEmail = json['identifier_type'] == 'email';
    return OtpSent(
      identifier: (json['identifier'] ?? json['phone_number'] ?? identifier).toString(),
      sentTo: (json['sent_to'] ?? json['phone_number'] ?? identifier).toString(),
      isEmail: isEmail,
      devOtp: isEmail ? '' : (json['dev_otp'] ?? '').toString(),
    );
  }

  /// POST /auth/verify-otp: signs in (creating the account the first time).
  ///
  /// Returns null once signed in, or an [AdminChallenge] when the server says
  /// this verified phone is an admin's: no session exists then, and the admin
  /// must give their email and password next (or continue as a customer).
  Future<AdminChallenge?> verifyOtp(
    String identifier,
    String code,
    String fullName,
  ) async {
    final data = await client.request(
      '/auth/verify-otp',
      method: 'POST',
      body: {
        'identifier': identifier.trim(),
        'code': code,
        if (fullName.trim().isNotEmpty) 'name': fullName.trim(),
      },
    );
    final json = data is Map ? data : const {};
    if (json['admin_verification_required'] == true) {
      return AdminChallenge(
        token: (json['challenge_token'] ?? '').toString(),
        expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 300,
      );
    }
    await _startSession(json, fallbackName: fullName);
    return null;
  }

  /// From the admin step: sign in to this phone's customer account instead
  /// (POST /auth/continue-as-customer uses the one-time challenge up).
  Future<void> continueAsCustomer(String challengeToken) async {
    final data = await client.request('/auth/continue-as-customer', method: 'POST', body: {'challenge_token': challengeToken});
    await _startSession(data is Map ? data : const {});
  }

  /// Stage 2 of the admin sign-in (POST /admin/auth/phone-login): the
  /// admin's own email and password for the admin the verified phone belongs
  /// to. The admin session is saved where the admin screens read it.
  Future<void> completeAdminSignIn(String challengeToken, String adminEmail, String password) async {
    final data = await client.request(
      '/admin/auth/phone-login',
      method: 'POST',
      body: {'challenge_token': challengeToken, 'email': adminEmail.trim(), 'password': password},
    );
    final adminToken = data is Map ? (data['token'] ?? '').toString() : '';
    if (adminToken.isEmpty) throw ApiException('Sign-in failed. Please try again.');
    await _storage.write(key: adminTokenKey, value: adminToken);
  }

  /// Where the admin screens keep their session (AdminSession).
  static const adminTokenKey = 'ofk_admin_token';

  Future<void> _startSession(Map json, {String fallbackName = ''}) async {
    final newToken = (json['token'] ?? '').toString();
    if (newToken.isEmpty) {
      throw ApiException('Sign-in failed. Please try again.');
    }
    final customer = json['customer'] is Map ? json['customer'] as Map : const {};
    token = newToken;
    client.token = newToken;
    expired = false;
    name = (customer['name'] ?? fallbackName).toString();
    _applyCustomer(customer);
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

  // ---- A new phone or email: only saved once its code is verified ----

  /// POST /auth/me/phone/send-code. Refused if the number is another
  /// customer's. Returns where the code went (and the development SMS code).
  Future<OtpSent> startPhoneChange(String phoneNumber) async {
    final data = await client.request('/auth/me/phone/send-code', method: 'POST', body: {'phone_number': phoneNumber.trim()});
    final json = data is Map ? data : const {};
    return OtpSent(
      identifier: (json['pending_phone_number'] ?? phoneNumber).toString(),
      sentTo: (json['sent_to'] ?? phoneNumber).toString(),
      isEmail: false,
      devOtp: (json['dev_otp'] ?? '').toString(),
    );
  }

  /// POST /auth/me/phone/verify: the new phone replaces the old one.
  Future<void> confirmPhoneChange(String code) => _confirm('/auth/me/phone/verify', code);

  /// POST /auth/me/email/send-code (a new email, or the current unverified one).
  Future<OtpSent> startEmailVerification(String address) async {
    final data = await client.request('/auth/me/email/send-code', method: 'POST', body: {'email': address.trim()});
    final json = data is Map ? data : const {};
    return OtpSent(identifier: address.trim(), sentTo: (json['sent_to'] ?? address).toString(), isEmail: true, devOtp: '');
  }

  /// POST /auth/me/email/verify: the email becomes the account's verified email.
  Future<void> confirmEmailVerification(String code) => _confirm('/auth/me/email/verify', code);

  Future<void> _confirm(String path, String code) async {
    final data = await client.request(path, method: 'POST', body: {'code': code.trim()});
    final customer = data is Map ? data['customer'] : null;
    if (customer is Map) _applyCustomer(customer);
    await _persistProfile();
    notifyListeners();
  }

  /// Signs this account out on every device (POST /auth/logout-all, as the
  /// kitchen and delivery worker apps offer), then on this one. Throws the
  /// server's message if it can't, leaving this device signed in.
  Future<void> logoutEverywhere() async {
    await client.request('/auth/logout-all', method: 'POST', body: <String, dynamic>{});
    // This token stays valid on the server ("keep this device"); end it too.
    await logout();
  }

  Future<void> logout() async {
    final old = token;
    token = null;
    client.token = null;
    name = '';
    phone = '';
    email = '';
    avatarUrl = '';
    emailVerified = false;
    pendingPhone = '';
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
