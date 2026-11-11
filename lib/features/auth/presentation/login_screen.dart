import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/server_address.dart';
import '../../../core/widgets/forms.dart';
import '../application/session.dart';
import '../../../root/role_switcher.dart';
import 'widgets/brand_header.dart';

enum _Step { phone, code }

/// Phone number, then the 6-digit SMS code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const int _defaultCooldown = 60;

  final _phoneForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  String? _devCode;
  int _cooldown = 0;
  Timer? _timer;

  String get _localPhone => Validators.toLocalPhone(_phone.text);

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown = _cooldown - 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    // The phone form only exists on the phone step. "Resend code" runs on the code step,
    // where it is not mounted: validating it there always failed, so Resend did nothing.
    if (_step == _Step.phone && !(_phoneForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await ref.read(sessionProvider.notifier).requestOtp(_localPhone);
      if (!mounted) return;
      setState(() {
        _step = _Step.code;
        _devCode = challenge.devOtp;
        _code.clear();
      });
      _startCooldown(_defaultCooldown);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == ApiCodes.otpResendTooSoon) {
        // A code was just sent: let them enter it, and wait before resending.
        setState(() {
          _step = _Step.code;
          _error = error.message;
        });
        _startCooldown(error.retryAfterSeconds ?? _defaultCooldown);
      } else {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (!(_codeForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).verifyOtp(_localPhone, _code.text.trim());
      // The router moves on as soon as the session is authenticated.
    } on ApiException catch (error) {
      if (mounted && !error.isBlockedAccount) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    setState(() {
      _step = _Step.phone;
      _error = null;
      _devCode = null;
      _cooldown = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notice = ref.watch(sessionProvider.select((state) => state.notice));
    final onCodeStep = _step == _Step.code;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const Align(alignment: Alignment.centerLeft, child: OtherSignInButton()),
                Row(children: [const Expanded(child: BrandHeader()), const ServerAddressButton()]),
                const SizedBox(height: 36),
                Text(
                  onCodeStep ? 'Enter your code' : 'Welcome back',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  onCodeStep
                      ? 'We sent a 6-digit code by SMS to $_localPhone.'
                      : 'Sign in to your kitchen with your phone number.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (notice != null && !onCodeStep) ...[
                  const SizedBox(height: 16),
                  NoteBox(message: notice, tone: Tone.warning, icon: Icons.lock_clock_rounded),
                ],
                const SizedBox(height: 24),
                if (!onCodeStep) _phoneStep() else _codeStep(theme),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
                ],
                const SizedBox(height: 28),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('New kitchen?', style: theme.textTheme.bodyMedium),
                  TextButton(onPressed: () => context.go('/register'), child: const Text('Register your kitchen')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep() => Form(
        key: _phoneForm,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PhoneField(
            controller: _phone,
            label: 'Kitchen phone number',
            autofocus: true,
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: 18),
          AsyncButton(label: 'Send code', icon: Icons.sms_rounded, onPressed: _busy ? null : _sendCode),
        ]),
      );

  Widget _codeStep(ThemeData theme) => Form(
        key: _codeForm,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(
            label: '6-digit code',
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            prefix: const Icon(Icons.pin_rounded),
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            validator: Validators.otp,
            onSubmitted: (_) => _verify(),
          ),
          // The server only returns `dev_otp` on a development server, and
          // this convenience is never shown in a release build.
          if (kDebugMode && _devCode != null) ...[
            const SizedBox(height: 10),
            ActionChip(
              avatar: const Icon(Icons.bug_report_rounded, size: 18),
              label: Text('Development code: $_devCode (tap to fill)'),
              onPressed: () => _code.text = _devCode!,
            ),
          ],
          const SizedBox(height: 18),
          AsyncButton(label: 'Sign in', icon: Icons.login_rounded, onPressed: _busy ? null : _verify),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: _changeNumber, child: const Text('Change number')),
            TextButton(
              onPressed: _cooldown > 0 || _busy ? null : _sendCode,
              child: Text(_cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code'),
            ),
          ]),
        ]),
      );
}
