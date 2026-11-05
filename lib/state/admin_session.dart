import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/admin_api.dart';
import '../api/api_client.dart';
import '../config.dart';

/// The SMS step of sign-in: the password was right and a code is now needed.
class TwoFactorChallenge {
  TwoFactorChallenge({required this.challengeToken, required this.sentTo, this.devOtp = ''});

  final String challengeToken;
  final String sentTo;
  final String devOtp;
}

/// Holds the signed-in admin (email + password session) and what they may do,
/// like the website's AdminContext.
class AdminSession extends ChangeNotifier {
  AdminSession() : client = ApiClient(baseUrl: kDefaultApiBaseUrl) {
    api = AdminApi(client);
    client.onUnauthorized = _onUnauthorized;
  }

  static const _tokenKey = 'ofk_admin_token';
  static const _baseUrlKey = 'ofk_api_base_url';
  static const _storage = FlutterSecureStorage();

  final ApiClient client;
  late final AdminApi api;

  Json? admin;
  Json limits = {'large_money_action_rwf': 50000};
  String? _token;
  bool restoring = true;
  bool loading = false;
  bool authBusy = false;
  String error = '';

  /// Minutes without activity before the app signs itself out (from the server).
  int idleMinutes = 30;
  DateTime _lastActivity = DateTime.now();
  Timer? _idleTimer;

  bool get hasToken => _token != null && _token!.isNotEmpty;
  bool get isAuthenticated => hasToken && admin != null;
  String? get role => admin?['role']?.toString();
  bool get isOwner => role == 'super_admin';
  List<String> get permissions => ((admin?['permissions'] as List?) ?? const []).map((e) => e.toString()).toList();
  bool get usesDefaultPassword => admin?['uses_default_password'] == true;
  int get largeMoneyActionRwf => (limits['large_money_action_rwf'] as num?)?.toInt() ?? 50000;
  String get baseUrl => client.baseUrl;

  /// What the signed-in admin may do (decided by their role on the server).
  bool can(String permission) => isOwner || permissions.contains(permission);

  /// Restores the saved server address and token when the app starts.
  Future<void> restore() async {
    try {
      final savedUrl = await _storage.read(key: _baseUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) client.baseUrl = savedUrl;
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
    client.token = _token;
    restoring = false;
    notifyListeners();
    if (hasToken) await _loadProfile();
  }

  Future<void> setBaseUrl(String url) async {
    client.baseUrl = url.trim();
    try {
      await _storage.write(key: _baseUrlKey, value: client.baseUrl);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    loading = true;
    error = '';
    notifyListeners();
    try {
      await refreshProfile();
    } on ApiException catch (err) {
      error = err.message.isEmpty ? 'Could not load your admin profile.' : err.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Json?> refreshProfile() async {
    final result = await api.me() as Json;
    admin = (result['admin'] as Map?)?.cast<String, dynamic>();
    final rawLimits = result['limits'];
    if (rawLimits is Map) limits = rawLimits.cast<String, dynamic>();
    final idle = result['idle_timeout_minutes'];
    if (idle is num) idleMinutes = idle.toInt();
    _startIdleTimer();
    notifyListeners();
    return admin;
  }

  /// Returns a [TwoFactorChallenge] when an SMS code is needed; finish with [verifyTwoFactor].
  Future<TwoFactorChallenge?> login(String email, String password) async {
    authBusy = true;
    error = '';
    notifyListeners();
    try {
      final result = await api.login(email, password) as Json;
      if (result['two_factor_required'] == true) {
        return TwoFactorChallenge(
          challengeToken: result['challenge_token'].toString(),
          sentTo: (result['sent_to'] ?? '').toString(),
          devOtp: (result['dev_otp'] ?? '').toString(),
        );
      }
      await _signedIn(result);
      return null;
    } on ApiException catch (err) {
      error = err.message.isEmpty ? 'Could not sign in.' : err.message;
      rethrow;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<void> verifyTwoFactor(String challengeToken, String code) async {
    authBusy = true;
    error = '';
    notifyListeners();
    try {
      final result = await api.verifyTwoFactor(challengeToken, code) as Json;
      await _signedIn(result);
    } on ApiException catch (err) {
      error = err.message.isEmpty ? 'Could not verify the code.' : err.message;
      rethrow;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<void> _signedIn(Json result) async {
    // Only one session at a time: sign out any old token on the server first.
    final old = _token;
    if (old != null && old.isNotEmpty) unawaited(client.logout(old));
    _token = result['token']?.toString();
    client.token = _token;
    admin = (result['admin'] as Map?)?.cast<String, dynamic>();
    try {
      await _storage.write(key: _tokenKey, value: _token);
    } catch (_) {}
    _lastActivity = DateTime.now();
    // The sign-in response may not carry the limits and idle timeout.
    try {
      await refreshProfile();
    } catch (_) {
      _startIdleTimer();
    }
  }

  void logout({String message = ''}) {
    final old = _token;
    if (old != null && old.isNotEmpty) unawaited(client.logout(old));
    _clear();
    error = message;
    notifyListeners();
  }

  void _clear() {
    _token = null;
    client.token = null;
    admin = null;
    _idleTimer?.cancel();
    _storage.delete(key: _tokenKey).catchError((_) {});
  }

  void _onUnauthorized(String? message) {
    if (!hasToken) return;
    _clear();
    error = (message == null || message.isEmpty) ? 'Your admin session has expired. Please log in again.' : message;
    notifyListeners();
  }

  // Idle timeout: no touches for `idleMinutes` signs the admin out (the token
  // is cancelled on the server), so a phone left unlocked doesn't stay usable.
  // The server enforces the same limit for copied tokens.
  void touch() => _lastActivity = DateTime.now();

  void _startIdleTimer() {
    _idleTimer?.cancel();
    if (!isAuthenticated || idleMinutes <= 0) return;
    _idleTimer = Timer.periodic(const Duration(seconds: 30), (_) => checkIdle());
  }

  /// Also called when the app comes back to the foreground.
  void checkIdle() {
    if (!isAuthenticated || idleMinutes <= 0) return;
    if (DateTime.now().difference(_lastActivity) > Duration(minutes: idleMinutes)) {
      logout(message: 'You were signed out after $idleMinutes minutes without activity. Please log in again.');
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
