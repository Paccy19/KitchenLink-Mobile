import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/server_address.dart';
import '../application/session.dart';
import '../models/driver_account.dart';
import '../../root/role_switcher.dart';
import 'widgets/motion.dart';

/// The KitchenLink mark with the "Delivery" app name.
class DriverBrandHeader extends StatelessWidget {
  const DriverBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DriverColors.brand, DriverColors.moss900],
          ),
          boxShadow: [
            BoxShadow(color: DriverColors.moss900.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: const Icon(Icons.delivery_dining_rounded, color: DriverColors.mistDeep, size: 30),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('KitchenLink', style: theme.textTheme.titleLarge?.copyWith(height: 1.1, letterSpacing: -0.4)),
        Text('Delivery app', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.secondary)),
      ]),
    ]);
  }
}

class DriverSplashScreen extends StatelessWidget {
  const DriverSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delivery_dining_rounded, size: 56, color: DriverColors.brand),
            SizedBox(height: 20),
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
          ]),
        ),
      );
}

/// A token is stored but the server did not answer. The token is kept.
class DriverOfflineScreen extends ConsumerWidget {
  const DriverOfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.read(driverSessionProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.wifi_off_rounded, size: 52, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 18),
                Text('Can’t reach KitchenLink', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Check your internet connection. You are still signed in, so nothing is lost.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                AsyncButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: session.restore),
                const SizedBox(height: 8),
                ServerAddressButton(onChanged: session.restore),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverBlockedScreen extends ConsumerWidget {
  const DriverBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final message = ref.watch(driverSessionProvider.select((s) => s.blockMessage));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.block_rounded, size: 52, color: theme.colorScheme.error),
                const SizedBox(height: 18),
                Text('Account unavailable', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  message ?? 'This delivery worker account cannot be used. Contact KitchenLink support.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: ref.read(driverSessionProvider.notifier).backToLogin,
                  child: const Text('Back to sign in'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { phone, code }

/// Phone number, then the 6-digit SMS code.
class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen> {
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
    if (_busy || !(_phoneForm.currentState?.validate() ?? _step == _Step.code)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await ref.read(driverSessionProvider.notifier).requestOtp(_localPhone);
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
        // A code was just sent: let them type it, and wait before resending.
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
    if (_busy || !(_codeForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(driverSessionProvider.notifier).verifyOtp(_localPhone, _code.text.trim());
      HapticFeedback.lightImpact();
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
    final notice = ref.watch(driverSessionProvider.select((s) => s.notice));
    final onCode = _step == _Step.code;
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
                const Row(children: [Expanded(child: DriverBrandHeader()), ServerAddressButton()]),
                const SizedBox(height: 40),
                SoftSwitcher(
                  child: Column(
                    key: ValueKey(_step),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        onCode ? 'Enter your code' : 'Ready to ride?',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        onCode
                            ? 'We sent a 6-digit code by SMS to $_localPhone.'
                            : 'Sign in with the phone number you registered as a delivery worker.',
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (notice != null && !onCode) ...[
                  const SizedBox(height: 16),
                  NoteBox(message: notice, tone: Tone.warning, icon: Icons.lock_clock_rounded),
                ],
                const SizedBox(height: 28),
                if (!onCode) _phoneStep() else _codeStep(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
                ],
                const SizedBox(height: 32),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('New to KitchenLink?', style: theme.textTheme.bodyMedium),
                  TextButton(onPressed: () => context.go('/register'), child: const Text('Become a delivery worker')),
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
          PhoneField(controller: _phone, label: 'Phone number', autofocus: true, onSubmitted: (_) => _sendCode()),
          const SizedBox(height: 18),
          AsyncButton(label: 'Send code', icon: Icons.sms_rounded, onPressed: _busy ? null : _sendCode),
        ]),
      );

  Widget _codeStep() => Form(
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
            onChanged: (value) {
              if (value.length == 6) _verify();
            },
            onSubmitted: (_) => _verify(),
          ),
          // `dev_otp` only comes from a development server; never shown in release.
          if (kDebugMode && _devCode != null) ...[
            const SizedBox(height: 10),
            ActionChip(
              avatar: const Icon(Icons.bug_report_rounded, size: 18),
              label: Text('Development code: $_devCode (tap to fill)'),
              onPressed: () {
                _code.text = _devCode!;
                _verify();
              },
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

/// Name, phone, vehicle and plate (`POST /driver/auth/register`). Accounts are
/// approved straight away; the worker then signs in with an SMS code.
class DriverRegisterScreen extends ConsumerStatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  ConsumerState<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends ConsumerState<DriverRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _email = TextEditingController();
  VehicleType _vehicle = VehicleType.motorcycle;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    try {
      await ref.read(driverRepositoryProvider).register(DriverRegistration(
            name: _name.text,
            phone: Validators.toLocalPhone(_phone.text),
            vehicleType: _vehicle,
            plateNumber: _plate.text,
            email: _email.text,
          ));
      if (!mounted) return;
      HapticFeedback.lightImpact();
      context.go('/register/done');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to sign in',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Become a delivery worker'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Text(
                    'Deliver food from kitchens near you and get paid for every trip.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    label: 'Full name',
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: Validators.nameMaxLength,
                    autofillHints: const [AutofillHints.name],
                    validator: (value) => Validators.name(value, 'Your name'),
                  ),
                  const SizedBox(height: 14),
                  PhoneField(controller: _phone, label: 'Phone number'),
                  const SizedBox(height: 24),
                  Text('How do you travel?', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final type in VehicleType.values)
                      ChoiceChip(
                        label: Text(type.label),
                        avatar: Icon(_vehicleIcon(type), size: 18),
                        selected: _vehicle == type,
                        showCheckmark: false,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _vehicle = type);
                        },
                      ),
                  ]),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _vehicle.hasPlate
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: AppTextField(
                              label: 'Plate number',
                              hint: 'e.g. RC 123 A',
                              controller: _plate,
                              maxLength: 20,
                              textCapitalization: TextCapitalization.characters,
                              validator: (value) => Validators.required(value, 'The plate number'),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Email (optional)',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.optionalEmail,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
                  ],
                  const SizedBox(height: 24),
                  AsyncButton(label: 'Create my account', icon: Icons.check_rounded, onPressed: _submit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _vehicleIcon(VehicleType type) {
  switch (type) {
    case VehicleType.motorcycle:
      return Icons.two_wheeler_rounded;
    case VehicleType.scooter:
      return Icons.electric_moped_rounded;
    case VehicleType.bicycle:
      return Icons.pedal_bike_rounded;
    case VehicleType.car:
      return Icons.directions_car_rounded;
    case VehicleType.foot:
      return Icons.directions_walk_rounded;
  }
}

IconData vehicleIcon(VehicleType? type) => type == null ? Icons.delivery_dining_rounded : _vehicleIcon(type);

class DriverRegisteredScreen extends StatelessWidget {
  const DriverRegisteredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = toneColors(context, Tone.success);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: colors.foreground, size: 44),
                ),
                const SizedBox(height: 22),
                Text('You’re all set', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Your delivery worker account is ready. Sign in with your phone number to go online.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
