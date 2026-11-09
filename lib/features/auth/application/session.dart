import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../models/vendor_account.dart';

enum SessionStatus {
  /// Reading the stored token and checking it with the server.
  restoring,
  unauthenticated,
  authenticated,

  /// The account is suspended or rejected: the app shows the reason.
  blocked,

  /// A token is stored but the server could not be reached to check it.
  unreachable,
}

class SessionState {
  const SessionState({required this.status, this.vendor, this.block, this.notice});

  const SessionState.restoring() : this(status: SessionStatus.restoring);

  final SessionStatus status;
  final VendorAccount? vendor;
  final AccountBlock? block;

  /// A message for the sign-in screen (e.g. the session ended).
  final String? notice;

  bool get isAuthenticated => status == SessionStatus.authenticated && vendor != null;
}

/// Owns the vendor's sign-in: token storage, restoring it at launch, and
/// reacting to the server rejecting the session.
class SessionController extends Notifier<SessionState> {
  late final AuthRepository _auth = ref.read(authRepositoryProvider);

  @override
  SessionState build() {
    final api = ref.read(apiClientProvider);
    api.onSessionInvalid = () => _endSession('Your session ended. Please sign in again.');
    api.onAccountBlocked = (error) => unawaited(_block(error));
    // A write was refused while pending: the status may have changed, re-check.
    api.onPendingReview = (_) => unawaited(refreshVendor());
    scheduleMicrotask(restore);
    return const SessionState.restoring();
  }

  /// Signs in again from a stored token, if there is one.
  Future<void> restore() async {
    final token = await ref.read(tokenStoreProvider).read();
    if (token == null) {
      state = const SessionState(status: SessionStatus.unauthenticated);
      return;
    }
    ref.read(apiClientProvider).setToken(token);
    try {
      final vendor = await _auth.me();
      state = SessionState(status: SessionStatus.authenticated, vendor: vendor);
    } on ApiException catch (error) {
      // 401 / blocked are handled by the client hooks; only a network failure
      // reaches here with the token still valid.
      if (error.isNetwork) {
        state = const SessionState(status: SessionStatus.unreachable);
      } else if (!error.isUnauthorized && !error.isBlockedAccount) {
        state = const SessionState(status: SessionStatus.unreachable);
      }
    }
  }

  /// Sends a sign-in code to [phone].
  Future<OtpChallenge> requestOtp(String phone) => _auth.sendOtp(phone);

  /// Checks the code; on success stores the token and opens the session.
  Future<void> verifyOtp(String phone, String code) async {
    try {
      final result = await _auth.verifyOtp(phone, code);
      await ref.read(tokenStoreProvider).write(result.token);
      ref.read(apiClientProvider).setToken(result.token);
      state = SessionState(status: SessionStatus.authenticated, vendor: result.vendor);
    } on ApiException catch (error) {
      if (error.isBlockedAccount) {
        state = SessionState(status: SessionStatus.blocked, block: _blockOf(error));
      }
      rethrow;
    }
  }

  /// Reloads the account (status, open/closed…). Failures keep the old data.
  Future<void> refreshVendor() async {
    if (state.status != SessionStatus.authenticated) return;
    try {
      applyVendor(await _auth.me());
    } on ApiException {
      // 401 / blocked are handled by the client hooks; others are retried later.
    }
  }

  /// Uses an account returned by a write (profile, availability…).
  void applyVendor(VendorAccount vendor) {
    if (state.status == SessionStatus.authenticated) {
      state = SessionState(status: SessionStatus.authenticated, vendor: vendor);
    }
  }

  /// Signs out of this device, or every device.
  Future<void> logout({bool everywhere = false}) async {
    try {
      if (everywhere) {
        await _auth.logoutAll();
      } else {
        await _auth.logout();
      }
    } on ApiException {
      // The token is dropped locally either way; it expires on its own.
    }
    await _endSession(null);
  }

  /// Leaves the account-blocked screen for the sign-in form.
  void backToLogin() => state = const SessionState(status: SessionStatus.unauthenticated);

  Future<void> _endSession(String? notice) async {
    await ref.read(tokenStoreProvider).clear();
    ref.read(apiClientProvider).setToken(null);
    state = SessionState(status: SessionStatus.unauthenticated, notice: notice);
  }

  Future<void> _block(ApiException error) async {
    await ref.read(tokenStoreProvider).clear();
    ref.read(apiClientProvider).setToken(null);
    state = SessionState(status: SessionStatus.blocked, block: _blockOf(error));
  }

  AccountBlock _blockOf(ApiException error) =>
      AccountBlock.fromError(code: error.code, message: error.message, details: error.details);
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The signed-in vendor. Only read it under the authenticated shell.
final vendorProvider = Provider<VendorAccount>((ref) {
  final vendor = ref.watch(sessionProvider).vendor;
  if (vendor == null) throw StateError('No signed-in vendor.');
  return vendor;
});

/// Whether restricted actions are allowed (the kitchen is approved).
final canActProvider = Provider<bool>((ref) => ref.watch(sessionProvider).vendor?.isApproved ?? false);
