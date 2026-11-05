import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../models/wallet.dart';

class WalletNotifier extends PolledNotifier<Wallet> {
  @override
  Duration? get pollInterval => const Duration(seconds: 20);

  @override
  Future<Wallet> fetch() => ref.read(walletRepositoryProvider).wallet();
}

final walletProvider = AsyncNotifierProvider.autoDispose<WalletNotifier, Wallet>(WalletNotifier.new);

/// Banks and their account-number lengths (public, rarely changes).
final bankListProvider = FutureProvider.autoDispose<BankList>(
  (ref) => ref.watch(walletRepositoryProvider).banks(),
);

class WalletActions {
  WalletActions(this._ref);
  final Ref _ref;

  /// Asks the backend for a payout. The amount is not checked against any
  /// balance here: the backend answers "Insufficient available balance" itself.
  Future<Withdrawal> withdraw(WithdrawalRequest request) async {
    final withdrawal = await _ref.read(walletRepositoryProvider).requestWithdrawal(request);
    _ref.invalidate(walletProvider);
    _ref.invalidate(dashboardProvider);
    return withdrawal;
  }
}

final walletActionsProvider = Provider<WalletActions>(WalletActions.new);
