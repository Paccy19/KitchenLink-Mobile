import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/wallet.dart';

class WalletRepository {
  const WalletRepository(this._api);
  final ApiClient _api;

  Future<Wallet> wallet() async => Wallet.fromJson(asJson(await _api.get('/vendor/wallet')));

  /// Banks and the account-number length each one uses (public).
  Future<BankList> banks() async => BankList.fromJson(await _api.get('/banks', auth: false));

  /// Requests a payout. The backend decides whether the amount is allowed.
  Future<Withdrawal> requestWithdrawal(WithdrawalRequest request) async {
    final json = asJson(await _api.post('/vendor/wallet/withdrawals', data: request.toJson()));
    return Withdrawal.fromJson(asJson(json['withdrawal']));
  }
}
