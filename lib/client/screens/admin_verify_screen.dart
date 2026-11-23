import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../root/role_switcher.dart';
import '../../ui/validation.dart';
import '../client_theme.dart';
import '../customer_session.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';

/// Opens the admin step after the customer sign-in code verified an admin's
/// phone. Returns true when the person chose to continue as a customer (and is
/// now signed in as one); an admin who signs in is taken to the admin screens.
Future<bool> openAdminVerification(BuildContext context, AdminChallenge challenge) async {
  final session = context.read<CustomerSession>();
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: session, child: AdminVerifyScreen(challenge: challenge)),
    ),
  );
  return result == true;
}

/// Stage 2 of the admin sign-in that starts at the customer phone sign-in
/// (the website's /admin-verify): the admin's own email and password. The
/// server checks both belong to the admin whose phone was verified; this
/// screen never decides who is an admin. The one-time challenge only lives in
/// memory and expires after a few minutes.
class AdminVerifyScreen extends StatefulWidget {
  const AdminVerifyScreen({super.key, required this.challenge});

  final AdminChallenge challenge;

  @override
  State<AdminVerifyScreen> createState() => _AdminVerifyScreenState();
}

class _AdminVerifyScreenState extends State<AdminVerifyScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  bool _switching = false;
  bool _expired = false;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _expired = widget.challenge.token.isEmpty;
    _timer = Timer(Duration(seconds: widget.challenge.expiresInSeconds), () {
      if (mounted) setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _failed(ApiException error) => setState(() {
        if (error.code == 'CHALLENGE_EXPIRED') _expired = true;
        _password.clear();
        _error = error.message;
      });

  Future<void> _submit() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      return setState(() => _error = 'Enter your administrator email and password.');
    }
    if (!isValidEmail(_email.text)) return setState(() => _error = emailError);
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await context.read<CustomerSession>().completeAdminSignIn(widget.challenge.token, _email.text, _password.text);
      if (!mounted) return;
      final switcher = RoleSwitcher.maybeOf(context);
      Navigator.of(context).pop(false);
      switcher?.open(AppRole.admin);
    } on ApiException catch (error) {
      if (mounted) _failed(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _asCustomer() async {
    setState(() {
      _error = '';
      _switching = true;
    });
    try {
      await context.read<CustomerSession>().continueAsCustomer(widget.challenge.token);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _failed(error);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MarketPage(
      title: 'Administrator Verification',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: K.strong, borderRadius: BorderRadius.circular(16), boxShadow: K.shadowSm),
              child: Icon(Icons.verified_user_outlined, color: K.onStrong, size: 28),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Verify your administrator credentials to open the KitchenLink management screens.',
            textAlign: TextAlign.center,
            style: kText(13, color: K.stone500, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_expired)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your phone verification has expired or was already used. Sign in again with your phone number.',
                    style: kText(13, color: K.stone600, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  GradientButton(label: 'Back to sign in', onTap: () => Navigator.of(context).pop(false)),
                ],
              ),
            )
          else
            Panel(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('Administrator email address'),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: marketInput('name@example.com', prefix: const Icon(Icons.mail_outline, size: 18)),
                    ),
                    const SizedBox(height: 12),
                    const FieldLabel('Administrator password'),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: marketInput('Your password', prefix: const Icon(Icons.lock_outline, size: 18)).copyWith(
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Notice(_error),
                    ],
                    const SizedBox(height: 16),
                    GradientButton(
                      label: _busy ? 'Verifying…' : 'Verify & open dashboard',
                      onTap: _busy || _switching ? null : _submit,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy || _switching ? null : _asCustomer,
                      icon: const Icon(Icons.person_outline, size: 16),
                      label: Text(_switching ? 'Signing you in…' : 'Continue as a customer instead'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
