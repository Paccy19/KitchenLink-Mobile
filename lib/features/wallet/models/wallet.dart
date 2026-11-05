import '../../../core/network/json.dart';
import '../../../core/utils/validators.dart';

class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.amountRwf,
    required this.status,
    this.method = '',
    this.methodLabel = '',
    this.accountNumber = '',
    this.accountName = '',
    this.bankName = '',
    this.reference = '',
    this.failureReason,
    this.processedAt,
    this.createdAt,
  });

  factory Withdrawal.fromJson(Json json) => Withdrawal(
        id: str(json['id']),
        amountRwf: intOf(json['amount_rwf']),
        status: str(json['status']),
        method: str(json['method']),
        methodLabel: str(json['method_label'], str(json['method'])),
        accountNumber: str(json['account_number']),
        accountName: str(json['account_name']),
        bankName: str(json['bank_name']),
        reference: str(json['reference']),
        failureReason: strOrNull(json['failure_reason']),
        processedAt: dateOrNull(json['processed_at']),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;
  final int amountRwf;

  /// `processing`, `completed` or `failed`.
  final String status;
  final String method;
  final String methodLabel;
  final String accountNumber;
  final String accountName;
  final String bankName;
  final String reference;
  final String? failureReason;
  final DateTime? processedAt;
  final DateTime? createdAt;

  bool get isFailed => status == 'failed';
  bool get isCompleted => status == 'completed';

  /// Where it was sent: the mobile-money number, or `<bank> · <account>`.
  String get destination =>
      bankName.isNotEmpty ? '$bankName · $accountNumber' : accountNumber;
}

class Wallet {
  const Wallet({
    this.availableBalanceRwf = 0,
    this.totalSalesRwf = 0,
    this.withdrawnRwf = 0,
    this.pendingBalanceRwf = 0,
    this.commissionPercent = 0,
    this.payoutPhone,
    this.payoutName = '',
    this.withdrawals = const [],
  });

  factory Wallet.fromJson(Json json) => Wallet(
        availableBalanceRwf: intOf(json['available_balance_rwf']),
        totalSalesRwf: intOf(json['total_sales_rwf']),
        withdrawnRwf: intOf(json['withdrawn_rwf']),
        pendingBalanceRwf: intOf(json['pending_balance_rwf']),
        commissionPercent: doubleOrNull(json['commission_percent']) ?? 0,
        payoutPhone: strOrNull(json['payout_phone']),
        payoutName: str(json['payout_name']),
        withdrawals: [for (final entry in asJsonList(json['withdrawals'])) Withdrawal.fromJson(entry)],
      );

  final int availableBalanceRwf;
  final int totalSalesRwf;
  final int withdrawnRwf;
  final int pendingBalanceRwf;
  final double commissionPercent;

  /// The registered phone, suggested for mobile-money payouts.
  final String? payoutPhone;
  final String payoutName;
  final List<Withdrawal> withdrawals;
}

/// One bank with its account-number length rule (`GET /banks`).
class BankInfo {
  const BankInfo({required this.name, required this.min, required this.max, required this.exact});

  factory BankInfo.fromJson(Json json) => BankInfo(
        name: str(json['name']),
        min: intOf(json['min'], 6),
        max: intOf(json['max'], 30),
        exact: boolOf(json['exact']),
      );

  final String name;
  final int min;
  final int max;
  final bool exact;

  String get lengthRule => exact ? '$min digits' : '$min–$max digits';

  /// Null when [digits] has this bank's length, else a message.
  String? validateAccountNumber(String digits) {
    if (digits.length >= min && digits.length <= max) return null;
    return '$name account numbers have $lengthRule. You entered ${digits.length}.';
  }
}

class BankList {
  const BankList({this.banks = const [], this.generalMin = 6, this.generalMax = 30});

  factory BankList.fromJson(Object? payload) {
    final map = asJson(payload);
    final general = asJson(map['general']);
    return BankList(
      banks: [for (final bank in asJsonList(map['banks'])) BankInfo.fromJson(bank)],
      generalMin: intOf(general['min'], 6),
      generalMax: intOf(general['max'], 30),
    );
  }

  final List<BankInfo> banks;
  final int generalMin;
  final int generalMax;

  BankInfo? byName(String name) {
    final lower = name.trim().toLowerCase();
    for (final bank in banks) {
      if (bank.name.toLowerCase() == lower) return bank;
    }
    return null;
  }

  /// The rule for [name], or the general rule for banks without their own.
  BankInfo ruleFor(String name) =>
      byName(name) ?? BankInfo(name: name, min: generalMin, max: generalMax, exact: false);
}

/// Where a withdrawal is paid (`POST /vendor/wallet/withdrawals`).
enum PayoutMethod {
  mtn('MTN Mobile Money'),
  airtel('Airtel Money'),
  bank('Bank Transfer');

  const PayoutMethod(this.apiLabel);

  /// Sent as `method`; the backend derives the method code from it.
  final String apiLabel;

  bool get isMobileMoney => this != bank;
}

class WithdrawalRequest {
  const WithdrawalRequest({
    required this.amountRwf,
    required this.method,
    this.phone,
    this.bankName,
    this.accountName,
    this.accountNumber,
  });

  final int amountRwf;
  final PayoutMethod method;
  final String? phone;
  final String? bankName;
  final String? accountName;
  final String? accountNumber;

  Json toJson() => {
        'amount_rwf': amountRwf,
        'method': method.apiLabel,
        if (method.isMobileMoney && phone != null) 'phone': Validators.toLocalPhone(phone!),
        if (!method.isMobileMoney) ...{
          'bank_name': bankName?.trim(),
          'account_name': accountName?.trim(),
          'account_number': accountNumber?.replaceAll(RegExp(r'[\s-]'), ''),
        },
      };
}
