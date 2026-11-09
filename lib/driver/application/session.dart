import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../data/driver_repository.dart';
import '../models/driver_account.dart';

final driverRepositoryProvider = Provider((ref) => DriverRepository(ref.watch(apiClientProvider)));

enum DriverSessionStatus {
  /// Reading the stored token and checking it with the server.
  restoring,
  unauthenticated,
  authenticated,

  /// The account is suspended or rejected: the app shows why.
  blocked,

  /// A token is stored but the server could not be reached to check it.
  unreachable,
}

class DriverSessionState {
  const DriverSessionState({required this.status, this.driver, this.blockMessage, this.notice});

  const DriverSessionState.restoring() : this(status: DriverSessionStatus.restoring);

  final DriverSessionStatus status;
  final DriverAccount? driver;
  final String? blockMessage;

  /// A message for the sign-in screen (e.g. the session ended).
  final String? notice;

  bool get isAuthenticated => status == DriverSessionStatus.authenticated && driver != null;
}

/// Owns the delivery worker's sign-in: the stored token (`ofk_driver_token`),
/// restoring it at launch, and reacting to the server ending the session.
class DriverSessionController extends Notifier<DriverSessionState> {
  DriverRepository get _repo => ref.read(driverRepositoryProvider);

  @override
  DriverSessionState build() {
    final api = ref.read(apiClientProvider);
    api.onSessionInvalid = () => unawaited(_end('Your session ended. Please sign in again.'));
    api.onAccountBlocked = (error) => unawaited(_block(error));
    scheduleMicrotask(restore);
    return const DriverSessionState.restoring();
  }

  Future<void> restore() async {
    state = const DriverSessionState.restoring();
    final token = await ref.read(tokenStoreProvider).read();
    if (token == null) {
      state = const DriverSessionState(status: DriverSessionStatus.unauthenticated);
      return;
    }
    ref.read(apiClientProvider).setToken(token);
    try {
      state = DriverSessionState(status: DriverSessionStatus.authenticated, driver: await _repo.me());
    } on ApiException catch (error) {
      // 401 and blocked accounts are handled by the client hooks.
      if (!error.isUnauthorized && !error.isBlockedAccount) {
        state = const DriverSessionState(status: DriverSessionStatus.unreachable);
      }
    }
  }

  Future<DriverOtpChallenge> requestOtp(String phone) => _repo.sendOtp(phone);

  Future<void> verifyOtp(String phone, String code) async {
    try {
      final result = await _repo.verifyOtp(phone, code);
      await ref.read(tokenStoreProvider).write(result.token);
      ref.read(apiClientProvider).setToken(result.token);
      state = DriverSessionState(status: DriverSessionStatus.authenticated, driver: result.driver);
    } on ApiException catch (error) {
      if (error.isBlockedAccount) {
        state = DriverSessionState(status: DriverSessionStatus.blocked, blockMessage: error.message);
      }
      rethrow;
    }
  }

  /// Reloads the account. Failures keep what is on screen.
  Future<void> refresh() async {
    if (!state.isAuthenticated) return;
    try {
      apply(await _repo.me());
    } on ApiException {
      // 401 / blocked are handled by the client hooks; others retry later.
    }
  }

  /// Uses an account returned by a write (profile, availability…).
  void apply(DriverAccount driver) {
    if (state.status == DriverSessionStatus.authenticated) {
      state = DriverSessionState(status: DriverSessionStatus.authenticated, driver: driver);
    }
  }

  /// Keeps the online flag in step with `GET /driver/stats`.
  void applyOnline({required bool online, required String status, required int activeDeliveries}) {
    final driver = state.driver;
    if (driver == null || !state.isAuthenticated) return;
    if (driver.isOnline == online && driver.status == status && driver.activeDeliveries == activeDeliveries) return;
    apply(driver.copyWith(isOnline: online, status: status, activeDeliveries: activeDeliveries));
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      everywhere ? await _repo.logoutAll() : await _repo.logout();
    } on ApiException {
      // The token is dropped on this phone either way.
    }
    await _end(null);
  }

  void backToLogin() => state = const DriverSessionState(status: DriverSessionStatus.unauthenticated);

  Future<void> _end(String? notice) async {
    await ref.read(tokenStoreProvider).clear();
    ref.read(apiClientProvider).setToken(null);
    state = DriverSessionState(status: DriverSessionStatus.unauthenticated, notice: notice);
  }

  Future<void> _block(ApiException error) async {
    await ref.read(tokenStoreProvider).clear();
    ref.read(apiClientProvider).setToken(null);
    state = DriverSessionState(status: DriverSessionStatus.blocked, blockMessage: error.message);
  }
}

final driverSessionProvider =
    NotifierProvider<DriverSessionController, DriverSessionState>(DriverSessionController.new);

/// The signed-in worker. Only read it under the signed-in shell.
final driverProvider = Provider<DriverAccount>((ref) {
  final driver = ref.watch(driverSessionProvider).driver;
  if (driver == null) throw StateError('No signed-in delivery worker.');
  return driver;
});

/// Whether the worker is on duty (receiving offers).
final isOnlineProvider = Provider<bool>((ref) => ref.watch(driverSessionProvider).driver?.isOnline ?? false);
