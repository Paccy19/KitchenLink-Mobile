import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../config.dart';
import '../../ui/validation.dart';
import '../client_theme.dart';
import '../widgets/form_fields.dart';

/// Vehicles a delivery worker can register with (the website's DRIVER_VEHICLES).
const driverVehicles = ['motorcycle', 'scooter', 'bicycle', 'car', 'foot'];

const _green = Color(0xFF3B5327);
const _greens = [Color(0xFF1C2B12), _green, Color(0xFF12200B)];

/// The message shown on the login page after registering, as on the website.
const driverRegisteredMessage = 'Delivery worker account created — log in with a verification code';

/// The website's /driver-register page ("Become a Delivery Worker"). Pops with
/// `true` once the account is created, so the login page can confirm it.
class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key, this.client});

  /// Defaults to the app's API address.
  final ApiClient? client;

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  late final ApiClient _client = widget.client ?? ApiClient(baseUrl: kDefaultApiBaseUrl);
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _email = TextEditingController();
  String _vehicle = 'motorcycle';
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _plate, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    String problem = '';
    if (_name.text.trim().length < 2) {
      problem = 'Enter your full name.';
    } else if (!isValidRwandaPhone(_phone.text)) {
      problem = phoneError;
    } else if (_email.text.trim().isNotEmpty && !isValidEmail(_email.text)) {
      problem = emailError;
    }
    if (problem.isNotEmpty) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await _client.request('/driver/auth/register', method: 'POST', body: {
        'name': _name.text.trim(),
        'phone': _phone.text,
        'vehicle_type': _vehicle,
        'plate_number': _plate.text,
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Could not create your account.' : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create your account.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _greens),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: K.shadowMd,
                      ),
                      child: const Icon(Icons.directions_bike, size: 28, color: Color(0xFFEEF5E5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Become a Delivery Worker',
                    textAlign: TextAlign.center,
                    style: kText(24, weight: w900, color: K.gray900, spacing: -0.6, height: 1.33),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Deliver orders and earn on every trip. Sign in with a code when you’re done.',
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
                    child: AutofillGroup(child: _form()),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _link('Already a driver? Log in', Icons.verified_user_outlined, () => Navigator.of(context).maybePop()),
                      _link('Back to marketplace', Icons.person_outline, () => Navigator.of(context).popUntil((r) => r.isFirst)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const FieldLabel('Full name'),
      MarketInput(
        controller: _name,
        hint: 'e.g. Eric Uwimana',
        autofill: const [AutofillHints.name],
        capitalization: TextCapitalization.words,
        formatters: [formatWith(formatNameInput)],
        focusColor: _green,
      ),
      const SizedBox(height: 16),
      const FieldLabel('Phone number'),
      MarketInput(
        controller: _phone,
        icon: Icons.phone_outlined,
        hint: phonePlaceholder,
        keyboard: TextInputType.phone,
        autofill: const [AutofillHints.telephoneNumber],
        formatters: [formatWith(sanitizePhoneInput)],
        focusColor: _green,
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const FieldLabel('Vehicle'), _vehicleDropdown()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Plate number'),
                MarketInput(
                  controller: _plate,
                  icon: Icons.local_shipping_outlined,
                  hint: 'RAD 101 A',
                  capitalization: TextCapitalization.characters,
                  focusColor: _green,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Email '),
            TextSpan(text: '(optional)', style: kText(12, weight: FontWeight.w500, color: K.stone400)),
          ]),
          style: kText(12, weight: FontWeight.w700, color: K.stone500),
        ),
      ),
      MarketInput(
        controller: _email,
        hint: 'you@example.com',
        keyboard: TextInputType.emailAddress,
        autofill: const [AutofillHints.email],
        maxLength: emailMaxLength,
        formatters: [formatWith(sanitizeEmailInput)],
        focusColor: _green,
      ),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: K.red50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Text(_error, style: kText(12, color: const Color(0xFFB91C1C))),
        ),
      ],
      const SizedBox(height: 16),
      _submitButton(),
    ],
  );

  Widget _vehicleDropdown() => DropdownButtonFormField<String>(
    initialValue: _vehicle,
    isExpanded: true,
    icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: K.gray900),
    style: kText(14, color: K.gray900, height: 1.43),
    dropdownColor: Colors.white,
    borderRadius: BorderRadius.circular(12),
    decoration: InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: K.stone200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _green, width: 1.5)),
    ),
    items: [
      for (final v in driverVehicles) DropdownMenuItem(value: v, child: Text('${v[0].toUpperCase()}${v.substring(1)}')),
    ],
    onChanged: (v) => setState(() => _vehicle = v ?? _vehicle),
  );

  Widget _submitButton() => Opacity(
    opacity: _busy ? 0.6 : 1,
    child: Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: _greens),
        borderRadius: BorderRadius.circular(12),
        boxShadow: K.shadowMd,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _busy ? 'Creating account…' : 'Create delivery worker account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kText(14, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _link(String label, IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: K.stone500),
          const SizedBox(width: 6),
          Text(label, style: kText(12, weight: FontWeight.w700, color: K.stone500)),
        ],
      ),
    ),
  );
}
