import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/validation.dart';
import '../client_theme.dart';
import '../customer_session.dart';
import 'market_dialog.dart';

/// The website's customer sign-in popup (AuthModal): name + phone, then the
/// 6-digit SMS code. Returns true once signed in.
Future<bool> showCustomerSignIn(BuildContext context) async {
  final session = context.read<CustomerSession>();
  final signedIn = await showMarketDialog<bool>(
    context,
    (_) => ChangeNotifierProvider.value(
      value: session,
      child: const _CustomerAuthDialog(),
    ),
  );
  return signedIn ?? false;
}

class _CustomerAuthDialog extends StatefulWidget {
  const _CustomerAuthDialog();

  @override
  State<_CustomerAuthDialog> createState() => _CustomerAuthDialogState();
}

class _CustomerAuthDialogState extends State<_CustomerAuthDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _otpStep = false;
  bool _busy = false;
  String _error = '';
  String _pendingPhone = '';
  String _devOtp = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    if (!isValidRwandaPhone(_phone.text)) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      final sent = await context.read<CustomerSession>().sendOtp(
        _phone.text,
        _name.text,
      );
      if (!mounted) return;
      setState(() {
        _pendingPhone = sent.phone;
        _devOtp = sent.devOtp;
        _otpStep = true;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Please enter the 6-digit OTP code');
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await context.read<CustomerSession>().verifyOtp(
        _pendingPhone,
        _code.text,
        _name.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      MarketDialogCard(children: _otpStep ? _otpForm() : _phoneForm());

  List<Widget> _phoneForm() => [
    Align(
      alignment: Alignment.centerLeft,
      child: _badge(
        Icons.phone_outlined,
        background: K.brown50,
        border: K.brown200,
        color: K.brown600,
      ),
    ),
    const SizedBox(height: 20),
    _title('Welcome to KitchenLink'),
    const SizedBox(height: 4),
    Text(
      'Enter your phone number to sign in or create your customer account',
      style: kText(12, color: K.stone500, height: 1.33),
    ),
    const SizedBox(height: 24),
    if (_error.isNotEmpty) _errorBox(),
    _label('Full Name'),
    _field(
      controller: _name,
      hint: 'Your Full Name',
      keyboard: TextInputType.name,
      autofill: const [AutofillHints.name],
      capitalization: TextCapitalization.words,
      formatter: formatNameInput,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 4),
    Text(
      'Also a kitchen or delivery worker on KitchenLink? Use the same name you registered with.',
      style: kText(11, color: K.stone400, height: 1.4),
    ),
    const SizedBox(height: 16),
    _label('Phone Number (MTN / Airtel)'),
    _field(
      controller: _phone,
      hint: phonePlaceholder,
      keyboard: TextInputType.phone,
      autofill: const [AutofillHints.telephoneNumber],
      formatter: sanitizePhoneInput,
      action: TextInputAction.done,
      onSubmit: _sendOtp,
    ),
    const SizedBox(height: 16),
    _submit(
      'Continue & Send OTP',
      onTap: _sendOtp,
      trailing: Icons.arrow_forward,
    ),
  ];

  List<Widget> _otpForm() {
    // The website's `tracking-[1em]`; tighter on narrow phones so 6 digits fit.
    final spacing = MediaQuery.sizeOf(context).width < 400 ? 16.0 : 24.0;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: _badge(
          Icons.verified_user_outlined,
          background: K.tone(const Color(0xFFD1FAE5)),
          color: K.tone(const Color(0xFF059669)),
        ),
      ),
      const SizedBox(height: 20),
      _title('Verify OTP Code'),
      const SizedBox(height: 4),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'We sent a verification code to '),
            TextSpan(
              text: _pendingPhone,
              style: kText(
                12,
                weight: FontWeight.w700,
                color: K.tone(const Color(0xFF1F2937)),
              ),
            ),
          ],
        ),
        style: kText(12, color: K.stone500, height: 1.33),
      ),
      const SizedBox(height: 16),
      if (_devOtp.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.brown50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: K.brown200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Development OTP: $_devOtp',
                  style: kText(12, color: K.brown850),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _code.text = _devOtp),
                child: Text(
                  'Insert code',
                  style: kText(
                    12,
                    weight: w900,
                    color: K.brown700,
                  ).copyWith(decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      if (_error.isNotEmpty) _errorBox(),
      _label('Enter 6-Digit Code', color: K.tone(const Color(0xFF6B7280))),
      TextField(
        controller: _code,
        autofocus: true,
        maxLength: 6,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _verify(),
        style: kText(24, weight: w900, color: K.gray900, spacing: spacing),
        decoration:
            _decoration(
              '••••',
              hintStyle: kText(
                24,
                weight: w900,
                color: K.stone400,
                spacing: spacing,
              ),
            ).copyWith(
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
      ),
      const SizedBox(height: 16),
      _submit(
        'Verify & Sign In',
        onTap: _verify,
        leading: Icons.how_to_reg_outlined,
      ),
    ];
  }

  Widget _badge(
    IconData icon, {
    required Color background,
    required Color color,
    Color? border,
  }) => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
      border: border == null ? null : Border.all(color: border),
      boxShadow: K.shadowSm,
    ),
    child: Icon(icon, size: 28, color: color),
  );

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(right: 32),
    child: Text(
      text,
      style: kText(
        24,
        weight: w900,
        color: K.gray900,
        spacing: -0.6,
        height: 1.33,
      ),
    ),
  );

  Widget _errorBox() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: K.red50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _error,
      style: kText(12, weight: FontWeight.w600, color: K.tone(const Color(0xFFDC2626))),
    ),
  );

  Widget _label(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: kText(12, weight: FontWeight.w700, color: color ?? K.stone500),
    ),
  );

  InputDecoration _decoration(String hint, {TextStyle? hintStyle}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle:
          hintStyle ?? kText(14, weight: FontWeight.w600, color: K.stone400),
      isDense: true,
      filled: true,
      fillColor: K.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: border(K.stone200),
      focusedBorder: border(K.brown700, 1.5),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboard,
    required Iterable<String> autofill,
    required String Function(String) formatter,
    required TextInputAction action,
    TextCapitalization capitalization = TextCapitalization.none,
    VoidCallback? onSubmit,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    autofillHints: autofill,
    textCapitalization: capitalization,
    textInputAction: action,
    onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
    inputFormatters: [
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = formatter(newValue.text);
        if (text == newValue.text) return newValue;
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }),
    ],
    style: kText(14, weight: FontWeight.w600, color: K.gray900),
    decoration: _decoration(hint),
  );

  Widget _submit(
    String label, {
    required VoidCallback onTap,
    IconData? leading,
    IconData? trailing,
  }) => Container(
    height: 50,
    decoration: BoxDecoration(
      gradient: K.buttonGradient,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x402B1206),
          blurRadius: 25,
          offset: Offset(0, 20),
          spreadRadius: -5,
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : onTap,
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      Icon(leading, size: 16, color: K.light(() => K.brown300)),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(
                          14,
                          weight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      Icon(trailing, size: 16, color: K.light(() => K.brown300)),
                    ],
                  ],
                ),
        ),
      ),
    ),
  );
}
