import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../config.dart';
import '../../ui/validation.dart';
import '../client_theme.dart';
import 'driver_register_screen.dart';
import 'vendor_register_screen.dart';

/// Who signed in on a [StaffLoginScreen].
class StaffSignIn {
  const StaffSignIn({required this.token, required this.name});

  final String token;
  final String name;
}

/// The vendor that signed in on [VendorLoginScreen].
typedef VendorSignIn = StaffSignIn;

/// What differs between the website's /vendor-login and /driver-login pages.
class StaffLoginRole {
  const StaffLoginRole({
    required this.title,
    required this.subtitle,
    required this.phoneLabel,
    required this.createLabel,
    required this.apiPrefix,
    required this.accountKey,
    required this.tokenKey,
    required this.logo,
    required this.logoGradient,
    required this.buttonGradient,
    required this.accent,
    required this.noRegistrationYet,
    this.dashboardName = '',
    this.blockedCodes = const {},
    this.register,
    this.registeredMessage,
  });

  /// Shown on the login page when the registration page pops with `true`.
  final String? registeredMessage;

  final String title;
  final String subtitle;
  final String phoneLabel;
  final String createLabel;

  /// `/vendor/auth` → `/vendor/auth/send-otp` and `/vendor/auth/verify-otp`.
  final String apiPrefix;

  /// Where the account is in the verify-otp reply (`vendor` / `driver`).
  final String accountKey;

  /// Same key as the website's localStorage entry.
  final String tokenKey;

  /// The logo tile's icon.
  final Widget logo;
  final Gradient logoGradient;
  final Gradient buttonGradient;

  /// Focus border, "Change phone number" and other links.
  final Color accent;

  /// Error codes that mean the account is suspended / rejected (blocked card).
  final Set<String> blockedCodes;

  /// "You can't sign in to the … Dashboard" on the blocked card.
  final String dashboardName;

  /// The "Create … account" page; null when the app doesn't have it yet.
  final Widget Function(ApiClient? client)? register;

  /// Shown instead when [register] is null.
  final String noRegistrationYet;

  static final vendor = StaffLoginRole(
    title: 'Vendor Login',
    subtitle: 'Sign in securely using a one-time code sent to your vendor phone.',
    phoneLabel: 'Vendor phone number',
    createLabel: 'Create a vendor account',
    apiPrefix: '/vendor/auth',
    accountKey: 'vendor',
    tokenKey: 'ofk_vendor_token',
    logo: const ChefHatIcon(size: 28, color: K.brown100),
    logoGradient: K.logoGradient,
    buttonGradient: K.buttonGradient,
    accent: K.brown700,
    blockedCodes: const {'VENDOR_SUSPENDED', 'VENDOR_REJECTED'},
    dashboardName: 'Vendor Dashboard',
    register: (client) => VendorRegisterScreen(client: client),
    noRegistrationYet: "Vendor registration isn't in the mobile app yet.",
  );

  static const _driverGreens = [Color(0xFF1C2B12), Color(0xFF3B5327), Color(0xFF12200B)];

  static final driver = StaffLoginRole(
    title: 'Delivery Worker Login',
    subtitle: 'Sign in securely using a one-time code sent to your phone.',
    phoneLabel: 'Phone number',
    createLabel: 'Create a driver account',
    apiPrefix: '/driver/auth',
    accountKey: 'driver',
    tokenKey: 'ofk_driver_token',
    logo: const Icon(Icons.directions_bike, size: 28, color: Color(0xFFEEF5E5)),
    logoGradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _driverGreens),
    buttonGradient: const LinearGradient(colors: _driverGreens),
    accent: const Color(0xFF3B5327),
    register: (client) => DriverRegisterScreen(client: client),
    registeredMessage: driverRegisteredMessage,
    noRegistrationYet: "Driver registration isn't in the mobile app yet.",
  );
}

/// The website's vendor / delivery-worker login page: phone → 6-digit SMS
/// code. A suspended or rejected vendor sees why, and how to reach support,
/// instead of the form. Pops with a [StaffSignIn] once signed in.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key, required this.role, this.client, this.onCreateAccount});

  final StaffLoginRole role;

  /// Defaults to the app's API address.
  final ApiClient? client;

  /// "Create … account". Defaults to the role's registration page.
  final VoidCallback? onCreateAccount;

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

/// The website's /vendor-login page.
class VendorLoginScreen extends StaffLoginScreen {
  VendorLoginScreen({super.key, super.client, super.onCreateAccount}) : super(role: StaffLoginRole.vendor);

  static const tokenKey = 'ofk_vendor_token';
}

/// The website's /driver-login page ("Delivery Worker Login").
class DriverLoginScreen extends StaffLoginScreen {
  DriverLoginScreen({super.key, super.client, super.onCreateAccount}) : super(role: StaffLoginRole.driver);

  static const tokenKey = 'ofk_driver_token';
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  late final ApiClient _client = widget.client ?? ApiClient(baseUrl: kDefaultApiBaseUrl);
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _otpStep = false;
  bool _busy = false;
  String _error = '';
  String _pendingPhone = '';
  String _devOtp = '';
  Map<String, dynamic>? _block;

  StaffLoginRole get _role => widget.role;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _resetToPhone() => setState(() {
    _otpStep = false;
    _code.clear();
    _error = '';
  });

  Future<void> _submit() => _otpStep ? _verify() : _sendCode();

  Future<void> _sendCode() async {
    if (_busy) return;
    if (!isValidRwandaPhone(_phone.text)) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
      _block = null;
    });
    try {
      final data = await _client.request('${_role.apiPrefix}/send-otp', method: 'POST', body: {'phone': _phone.text.trim()});
      final json = data is Map ? data : const {};
      if (!mounted) return;
      setState(() {
        _pendingPhone = (json['phone_number'] ?? _phone.text.trim()).toString();
        _devOtp = (json['dev_otp'] ?? '').toString();
        _otpStep = true;
      });
    } on ApiException catch (e) {
      if (mounted) _fail(e, 'Could not send a verification code.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send a verification code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Enter the 6-digit verification code.');
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      final data = await _client.request(
        '${_role.apiPrefix}/verify-otp',
        method: 'POST',
        body: {'phone': _pendingPhone, 'code': _code.text},
      );
      final json = data is Map ? data : const {};
      final token = (json['token'] ?? '').toString();
      if (token.isEmpty) throw ApiException('Could not verify the code.');
      final account = json[_role.accountKey] is Map ? json[_role.accountKey] as Map : const {};
      try {
        await const FlutterSecureStorage().write(key: _role.tokenKey, value: token);
      } catch (_) {
        // Signed in for this session only.
      }
      if (mounted) Navigator.of(context).pop(StaffSignIn(token: token, name: (account['name'] ?? '').toString()));
    } on ApiException catch (e) {
      if (!mounted) return;
      _fail(e, 'Could not verify the code.');
      if (_role.blockedCodes.contains(e.code)) {
        _otpStep = false;
        _code.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify the code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(ApiException e, String fallback) => setState(() {
    if (_role.blockedCodes.contains(e.code)) {
      _block = {'status': e.code.endsWith('_SUSPENDED') ? 'suspended' : 'rejected', ...e.details};
    } else {
      _error = e.message.isEmpty ? fallback : e.message;
    }
  });

  void _createAccount() {
    if (widget.onCreateAccount != null) return widget.onCreateAccount!();
    final register = _role.register;
    if (register != null) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).push(MaterialPageRoute<Object?>(builder: (_) => register(widget.client))).then((result) {
        final message = _role.registeredMessage;
        if (result == true && message != null && mounted) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      });
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_role.noRegistrationYet)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF7F4),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: _block != null ? _blockedNotice(_block!) : _loginForm(),
          ),
        ),
      ),
    ),
  );

  // ---------------------------------------------------------------- login form

  Widget _loginForm() {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(gradient: _role.logoGradient, borderRadius: BorderRadius.circular(16), boxShadow: K.shadowMd),
            child: Center(child: _role.logo),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _role.title,
          textAlign: TextAlign.center,
          style: kText(24, weight: w900, color: K.gray900, spacing: -0.6, height: 1.33),
        ),
        const SizedBox(height: 4),
        Text(
          _role.subtitle,
          textAlign: TextAlign.center,
          style: kText(14, color: K.stone500, height: 1.43),
        ),
        const SizedBox(height: 24),
        Container(
          padding: EdgeInsets.all(wide ? 32 : 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: K.stone200.withValues(alpha: 0.8)),
            boxShadow: K.shadowSm,
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_otpStep) ..._codeFields() else ..._phoneFields(),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _note(_error, background: K.red50, border: const Color(0xFFFECACA), color: const Color(0xFFB91C1C)),
                ],
                const SizedBox(height: 16),
                _primaryButton(
                  _busy ? 'Please wait…' : (_otpStep ? 'Verify & sign in' : 'Send verification code'),
                  icon: _otpStep ? Icons.check : Icons.arrow_forward,
                  onTap: _busy ? null : _submit,
                ),
                if (_otpStep) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: _textLink('Change phone number', onTap: _resetToPhone, color: _role.accent),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 4,
          children: [
            _textLink(_role.createLabel, icon: Icons.verified_user_outlined, onTap: _createAccount),
            _textLink('Back to marketplace', icon: Icons.person_outline, onTap: () => Navigator.of(context).maybePop()),
          ],
        ),
      ],
    );
  }

  List<Widget> _phoneFields() => [
    _label(_role.phoneLabel),
    TextField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      inputFormatters: [_formatter(sanitizePhoneInput)],
      style: kText(14, color: K.gray900),
      decoration: _decoration(phonePlaceholder, prefix: const Icon(Icons.phone_outlined, size: 16, color: K.stone400)),
    ),
  ];

  List<Widget> _codeFields() => [
    _label('6-digit verification code'),
    TextField(
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      style: kText(18, color: K.gray900, spacing: 9),
      decoration: _decoration('Enter code', hintSpacing: 9),
    ),
    const SizedBox(height: 8),
    Text('Code sent to $_pendingPhone', style: kText(12, color: K.stone500)),
    if (_devOtp.isNotEmpty) ...[
      const SizedBox(height: 16),
      _note(
        'Development code: ',
        bold: _devOtp,
        background: const Color(0xFFFFFBEB),
        border: K.amber200,
        color: const Color(0xFFB45309),
        onTap: () => _code.text = _devOtp,
      ),
    ],
  ];

  // ------------------------------------------------------- blocked account card

  Widget _blockedNotice(Map<String, dynamic> block) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final suspended = block['status'] == 'suspended';
    final since = DateTime.tryParse((block['suspended_at'] ?? '').toString());
    final sinceText = suspended && since != null ? ' (suspended on ${DateFormat.yMMMMd().format(since.toLocal())})' : '';
    final reason = (block['reason'] ?? '').toString();
    final phone = (block['support_phone'] ?? '').toString();
    final email = (block['support_email'] ?? '').toString();
    const red200 = Color(0xFFFECACA);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.all(wide ? 32 : 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: red200),
            boxShadow: K.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: K.red50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: red200),
                  ),
                  child: const Icon(Icons.block, size: 28, color: Color(0xFFDC2626)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                suspended ? 'Your account is suspended' : 'Your application was rejected',
                textAlign: TextAlign.center,
                style: kText(20, weight: w900, color: K.gray900, spacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                suspended
                    ? "You can't sign in to the ${_role.dashboardName}$sinceText."
                    : "You can't sign in to the ${_role.dashboardName} until this is resolved.",
                textAlign: TextAlign.center,
                style: kText(14, color: K.stone500),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: K.red50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: red200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REASON',
                      style: kText(12, weight: FontWeight.w700, color: const Color(0xFFB91C1C), spacing: 0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason.isEmpty ? 'No reason was given. Contact the support team for details.' : reason,
                      style: kText(14, color: const Color(0xFF7F1D1D)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('To solve this, contact our support team. They will review your account with you.', style: kText(14, color: K.stone600)),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                _primaryButton(
                  'Call support: $phone',
                  leadingIcon: Icons.phone_outlined,
                  onTap: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'\s'), '')}')),
                ),
              ],
              if (email.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('mailto:$email')),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: Text(
                    email,
                    style: kText(14, weight: FontWeight.w700, color: _role.accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _role.accent,
                    side: const BorderSide(color: K.stone200),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: _textLink(
                  'Back to login',
                  color: _role.accent,
                  onTap: () => setState(() {
                    _block = null;
                    _otpStep = false;
                    _code.clear();
                    _error = '';
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _textLink('Back to marketplace', icon: Icons.person_outline, onTap: () => Navigator.of(context).maybePop()),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- pieces

  static TextInputFormatter _formatter(String Function(String) format) => TextInputFormatter.withFunction((_, next) {
    final text = format(next.text);
    return text == next.text
        ? next
        : TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
  });

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: kText(12, weight: FontWeight.w700, color: K.stone500),
    ),
  );

  InputDecoration _decoration(String hint, {Widget? prefix, double hintSpacing = 0}) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: kText(prefix == null ? 18 : 14, color: K.stone400, spacing: hintSpacing),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefix,
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: prefix == null ? 12 : 14),
      enabledBorder: border(K.stone200),
      focusedBorder: border(_role.accent, 1.5),
    );
  }

  Widget _note(String text, {String? bold, required Color background, required Color border, required Color color, VoidCallback? onTap}) {
    final note = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            if (bold != null)
              TextSpan(
                text: bold,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
          ],
        ),
        style: kText(12, color: color),
      ),
    );
    return onTap == null ? note : GestureDetector(onTap: onTap, child: note);
  }

  Widget _primaryButton(String label, {IconData? icon, IconData? leadingIcon, VoidCallback? onTap}) => Opacity(
    opacity: _busy ? 0.6 : 1,
    child: Container(
      height: 46,
      decoration: BoxDecoration(gradient: _role.buttonGradient, borderRadius: BorderRadius.circular(12), boxShadow: K.shadowMd),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leadingIcon != null) ...[Icon(leadingIcon, size: 16, color: Colors.white), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kText(14, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 16, color: Colors.white)],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _textLink(String label, {IconData? icon, required VoidCallback onTap, Color color = K.stone500}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
          Text(
            label,
            style: kText(12, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    ),
  );
}

/// Lucide's "chef-hat" icon (the website's vendor logo), drawn as a 2px outline.
class ChefHatIcon extends StatelessWidget {
  const ChefHatIcon({super.key, this.size = 24, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ChefHatPainter(color)),
  );
}

class _ChefHatPainter extends CustomPainter {
  _ChefHatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // M17 21a1 1 0 0 0 1-1v-5.35c0-.457.316-.844.727-1.041a4 4 0 0 0-2.134-7.589
    // 5 5 0 0 0-9.186 0 4 4 0 0 0-2.134 7.588c.411.198.727.585.727 1.041V20a1 1 0 0 0 1 1Z
    final hat = Path()
      ..moveTo(17, 21)
      ..arcToPoint(const Offset(18, 20), radius: const Radius.circular(1), clockwise: false)
      ..lineTo(18, 14.65)
      ..cubicTo(18, 14.193, 18.316, 13.806, 18.727, 13.609)
      ..arcToPoint(const Offset(16.593, 6.02), radius: const Radius.circular(4), clockwise: false)
      ..arcToPoint(const Offset(7.407, 6.02), radius: const Radius.circular(5), clockwise: false)
      ..arcToPoint(const Offset(5.273, 13.608), radius: const Radius.circular(4), clockwise: false)
      ..cubicTo(5.684, 13.806, 6, 14.193, 6, 14.649)
      ..lineTo(6, 20)
      ..arcToPoint(const Offset(7, 21), radius: const Radius.circular(1), clockwise: false)
      ..close()
      ..moveTo(6, 17)
      ..lineTo(18, 17);
    canvas.drawPath(hat, paint);
  }

  @override
  bool shouldRepaint(_ChefHatPainter old) => old.color != color;
}
