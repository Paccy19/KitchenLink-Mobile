import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/wallet.dart';

/// The wallet and payouts. The vendor app uses `/vendor/wallet`; the delivery
/// worker app passes `/driver/wallet` (same withdrawal request and response).
class WalletRepository {
  const WalletRepository(this._api, {this.basePath = '/vendor/wallet'});
  final ApiClient _api;
  final String basePath;

  Future<Wallet> wallet() async => Wallet.fromJson(asJson(await _api.get(basePath)));

  /// Banks and the account-number length each one uses (public).
  Future<BankList> banks() async => BankList.fromJson(await _api.get('/banks', auth: false));

  /// Requests a payout. The backend decides whether the amount is allowed.
  Future<Withdrawal> requestWithdrawal(WithdrawalRequest request) async {
    final json = asJson(await _api.post('$basePath/withdrawals', data: request.toJson()));
    return Withdrawal.fromJson(asJson(json['withdrawal']));
  }
}
