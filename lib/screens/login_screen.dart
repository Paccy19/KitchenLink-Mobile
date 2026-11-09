import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../state/admin_session.dart';
import '../ui/validation.dart';
import '../root/role_switcher.dart';

// The website's admin sign-in colours (Tailwind stone / gray / red).
const _page = Color(0xFFF5F6F8);
const _gray900 = Color(0xFF111827);
const _slate = Color(0xFF1F2937);
const _stone100 = Color(0xFFF5F5F4);
const _stone200 = Color(0xFFE7E5E4);
const _stone400 = Color(0xFFA8A29E);
const _stone500 = Color(0xFF78716C);
const _stone600 = Color(0xFF57534E);
const _red50 = Color(0xFFFEF2F2);
const _red200 = Color(0xFFFECACA);
const _red700 = Color(0xFFB91C1C);
const _gradient = LinearGradient(colors: [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF0B1220)]);
const _diagonal = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF0B1220)],
);
const _shadowMd = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
  BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
];

/// Admin sign-in, laid out like the website's /admin-login page: email +
/// password, then the SMS code when two-step sign-in is on.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  // Set when the password was right and an SMS code is now required.
  TwoFactorChallenge? challenge;
  String error = '';

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final session = context.read<AdminSession>();
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    if (!isValidEmail(email.text)) {
      setState(() => error = emailError);
      return;
    }
    setState(() => error = '');
    try {
      final result = await session.login(email.text.trim(), password.text);
      if (result != null && mounted) {
        setState(() {
          challenge = result;
          code.clear();
        });
      }
    } on ApiException catch (err) {
      if (mounted) setState(() => error = err.message.isEmpty ? 'Could not sign in.' : err.message);
    }
  }

  Future<void> submitCode() async {
    final session = context.read<AdminSession>();
    if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      setState(() => error = 'Enter the 6-digit code sent to your phone.');
      return;
    }
    setState(() => error = '');
    try {
      await session.verifyTwoFactor(challenge!.challengeToken, code.text.trim());
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        error = err.message.isEmpty ? 'Could not verify the code.' : err.message;
        if (err.code == 'CHALLENGE_EXPIRED') challenge = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final shownError = error.isNotEmpty ? error : session.error;
    final wide = MediaQuery.of(context).size.width >= 640;

    return Theme(
      // The page keeps the website's light look.
      data: Theme.of(context).copyWith(brightness: Brightness.light, textSelectionTheme: const TextSelectionThemeData(cursorColor: _slate)),
      child: Scaffold(
        backgroundColor: _page,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: OtherSignInButton()),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(gradient: _diagonal, borderRadius: BorderRadius.circular(16), boxShadow: _shadowMd),
                      child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Admin Sign In',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, height: 1.33, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: _gray900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Secure access to the KitchenLink admin panel.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.43, color: _stone500),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: EdgeInsets.all(wide ? 32 : 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _stone200.withValues(alpha: 0.8)),
                      boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
                    ),
                    child: AutofillGroup(child: challenge == null ? _passwordForm(session, shownError) : _codeForm(session, shownError)),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: InkWell(
                      onTap: () => launchUrl(Uri.parse(kMarketplaceUrl), mode: LaunchMode.externalApplication),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.storefront_outlined, size: 14, color: _stone500),
                        SizedBox(width: 6),
                        Text('Back to marketplace', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stone500)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordForm(AdminSession session, String shownError) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _Label('Email address'),
      _Input(
        controller: email,
        icon: Icons.mail_outline,
        hint: 'admin@foodkitchen.rw',
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.username, AutofillHints.email],
        textInputAction: TextInputAction.next,
        inputFormatters: [
          LengthLimitingTextInputFormatter(emailMaxLength),
          TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizeEmailInput(next.text))),
        ],
      ),
      const SizedBox(height: 16),
      const _Label('Password'),
      _Input(
        controller: password,
        icon: Icons.lock_outline,
        hint: '••••••••',
        obscure: true,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => submit(),
      ),
      if (shownError.isNotEmpty) ...[const SizedBox(height: 16), _Error(shownError)],
      const SizedBox(height: 16),
      _PrimaryButton(label: session.authBusy ? 'Signing in…' : 'Sign in', busy: session.authBusy, onPressed: submit),
    ]);
  }

  Widget _codeForm(AdminSession session, String shownError) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _stone100, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.smartphone, size: 20, color: _slate),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(style: const TextStyle(fontSize: 14, height: 1.43, color: _stone600), children: [
              const TextSpan(text: 'We sent a 6-digit code to '),
              TextSpan(text: challenge!.sentTo, style: const TextStyle(fontWeight: FontWeight.w700, color: _gray900)),
              const TextSpan(text: '. Enter it to finish signing in.'),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      const _Label('Sign-in code'),
      _Input(
        controller: code,
        hint: '123456',
        center: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        onSubmitted: (_) => submitCode(),
      ),
      if (challenge!.devOtp.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Development code: ${challenge!.devOtp}', style: const TextStyle(fontSize: 11, color: _stone400)),
        ),
      if (shownError.isNotEmpty) ...[const SizedBox(height: 16), _Error(shownError)],
      const SizedBox(height: 16),
      _PrimaryButton(label: session.authBusy ? 'Verifying…' : 'Verify & sign in', busy: session.authBusy, onPressed: submitCode),
      const SizedBox(height: 16),
      Center(
        child: InkWell(
          onTap: () => setState(() {
            challenge = null;
            error = '';
          }),
          child: const Text('Use a different account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stone500)),
        ),
      ),
    ]);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stone500)),
      );
}

/// The website's input: white, 12px corners, stone border, dark focus ring,
/// with a small grey icon inside on the left.
class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.center = false,
    this.autofocus = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final bool center;
  final bool autofocus;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: width));
    final codeStyle = center ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 7.2, color: _gray900) : null;
    return TextField(
      controller: controller,
      obscureText: obscure,
      obscuringCharacter: '•',
      autofocus: autofocus,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: codeStyle ?? const TextStyle(fontSize: 14, color: _gray900),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: (codeStyle ?? const TextStyle(fontSize: 14)).copyWith(color: _stone400),
        contentPadding: EdgeInsets.fromLTRB(icon == null ? 12 : 0, 14, 12, 14),
        prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _stone400),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        enabledBorder: border(_stone200),
        border: border(_stone200),
        focusedBorder: border(_slate, 1.5),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _red50, border: Border.all(color: _red200), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 12, height: 1.33, color: _red700)),
      );
}

/// Full-width dark gradient button with the label then an arrow.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(12), boxShadow: _shadowMd),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
