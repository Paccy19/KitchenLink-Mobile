import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/wallet_providers.dart';
import '../models/wallet.dart';

/// Asks the backend for a payout. The app never decides how much may be
/// withdrawn: it shows the balance and lets the backend accept or refuse.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _bankName = TextEditingController();
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();
  PayoutMethod _method = PayoutMethod.mtn;
  bool _prefilled = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _phone, _bankName, _accountName, _accountNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(Wallet wallet) {
    if (_prefilled) return;
    _prefilled = true;
    if (wallet.payoutPhone != null) {
      _phone.text = wallet.payoutPhone!;
      _method = Validators.networkOfPhone(wallet.payoutPhone!) == 'airtel' ? PayoutMethod.airtel : PayoutMethod.mtn;
    }
    _accountName.text = wallet.payoutName;
  }

  WithdrawalRequest _request() => WithdrawalRequest(
        amountRwf: int.parse(_amount.text.trim()),
        method: _method,
        phone: _method.isMobileMoney ? _phone.text : null,
        bankName: _method.isMobileMoney ? null : _bankName.text,
        accountName: _method.isMobileMoney ? null : _accountName.text,
        accountNumber: _method.isMobileMoney ? null : _accountNumber.text,
      );

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final request = _request();
    final where = _method.isMobileMoney
        ? '${_method.apiLabel} ${Validators.toLocalPhone(_phone.text)}'
        : '${_bankName.text.trim()} account ${_accountNumber.text.trim()}';
    final yes = await confirm(
      context,
      title: 'Confirm withdrawal',
      message: 'Withdraw ${formatRwf(request.amountRwf)} to $where?',
      confirmLabel: 'Withdraw',
    );
    if (!yes || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final withdrawal = await ref.read(walletActionsProvider).withdraw(request);
      if (!mounted) return;
      showSuccess(context, 'Withdrawal requested (${withdrawal.reference}). It is being processed.');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorMessage(error));
      await reportFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = ref.watch(walletProvider);
    final banks = ref.watch(bankListProvider);
    wallet.whenData(_prefill);

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw money')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: FormPage(children: [
            AppCard(
              child: Row(children: [
                Icon(Icons.account_balance_wallet_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Available balance', style: theme.textTheme.bodyMedium)),
                Text(wallet.hasValue ? formatRwf(wallet.requireValue.availableBalanceRwf) : '…', style: theme.textTheme.titleMedium),
              ]),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Amount (RWF)',
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              prefix: const Icon(Icons.payments_rounded),
              validator: (value) => Validators.wholeNumber(value, 'Amount', min: 1),
            ),
            const SizedBox(height: 8),
            Text('Send it to', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PayoutMethod>(
              segments: const [
                ButtonSegment(value: PayoutMethod.mtn, label: Text('MTN'), icon: Icon(Icons.smartphone_rounded)),
                ButtonSegment(value: PayoutMethod.airtel, label: Text('Airtel'), icon: Icon(Icons.smartphone_rounded)),
                ButtonSegment(value: PayoutMethod.bank, label: Text('Bank'), icon: Icon(Icons.account_balance_rounded)),
              ],
              selected: {_method},
              onSelectionChanged: (value) => setState(() => _method = value.first),
            ),
            const SizedBox(height: 16),
            if (_method.isMobileMoney)
              PhoneField(
                controller: _phone,
                label: '${_method.apiLabel} number',
                validator: (value) {
                  final basic = Validators.phone(value);
                  if (basic != null) return basic;
                  final network = Validators.networkOfPhone(Validators.toLocalPhone(value!));
                  final wanted = _method == PayoutMethod.mtn ? 'mtn' : 'airtel';
                  return network == wanted
                      ? null
                      : 'This is not ${_method == PayoutMethod.mtn ? 'an MTN (078/079)' : 'an Airtel (072/073)'} number.';
                },
              )
            else ...[
              Autocomplete<String>(
                optionsBuilder: (value) => (banks.value?.banks ?? const <BankInfo>[])
                    .map((bank) => bank.name)
                    .where((name) => name.toLowerCase().contains(value.text.toLowerCase())),
                onSelected: (name) => setState(() => _bankName.text = name),
                fieldViewBuilder: (context, controller, focus, onSubmit) => AppTextField(
                  label: 'Bank name',
                  controller: controller,
                  onChanged: (value) => setState(() => _bankName.text = value),
                  validator: (value) => Validators.length(value, 'Bank name', min: 2, max: 60),
                ),
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Account holder name',
                controller: _accountName,
                textCapitalization: TextCapitalization.words,
                validator: (value) => Validators.length(value, 'Account name', min: 2, max: 80),
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Account number',
                helper: banks.hasValue && _bankName.text.trim().isNotEmpty
                    ? '${_bankName.text.trim()}: ${banks.requireValue.ruleFor(_bankName.text).lengthRule}'
                    : null,
                controller: _accountNumber,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]'))],
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
                  if (digits.isEmpty) return 'Enter the account number.';
                  final rules = banks.value;
                  return rules?.ruleFor(_bankName.text).validateAccountNumber(digits);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Request withdrawal'),
            ),
          ]),
        ),
      ),
    );
  }
}
