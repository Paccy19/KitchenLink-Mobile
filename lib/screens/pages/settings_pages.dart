import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../nav/admin_nav.dart';
import '../../state/admin_session.dart';
import '../../ui/action_code_field.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/validation.dart';
import '../../ui/widgets.dart';
import '../admin_shell.dart';

// ---- Profile & account security ------------------------------------------

class ProfileSettingsPage extends StatelessWidget {
  const ProfileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final admin = session.admin ?? const {};
    return PageBody(children: [
      const PageHeader(title: 'Settings', description: 'Profile & account security'),
      if (session.usesDefaultPassword)
        const Note(
          'You are still using the default admin password. Anyone who knows it can sign in. '
          'Change it below: the rest of the admin panel stays locked until you do.',
          icon: Icons.warning_amber_rounded,
        ),
      SectionCard(
        title: 'Profile',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.verified_user_outlined, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(jstr(admin['name']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Hint(jstr(admin['email'])),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  ToneBadge(toTitle(admin['role']), tone: Tone.violet),
                  ToneBadge(admin['is_active'] == true ? 'Active' : 'Disabled', tone: admin['is_active'] == true ? Tone.green : Tone.red),
                ]),
              ]),
            ),
          ]),
          Hint('Last login: ${formatDate(admin['last_login_at'])}'),
          if (session.permissions.isNotEmpty) ...[
            const SectionLabel('Permissions'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final p in session.permissions) ToneBadge(p)]),
          ],
        ])),
      ),
      const _TwoFactorCard(),
      const _ChangePasswordCard(),
    ]);
  }
}

/// Turn SMS codes on (verify a phone) or off (confirmed with a code).
class _TwoFactorCard extends StatefulWidget {
  const _TwoFactorCard();

  @override
  State<_TwoFactorCard> createState() => _TwoFactorCardState();
}

class _TwoFactorCardState extends State<_TwoFactorCard> with BusyState {
  late final session = context.read<AdminSession>();
  late final phone = TextEditingController(text: jstr(session.admin?['phone']));
  String code = '';
  int codeKey = 0;
  String message = '';

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> change(Future<dynamic> Function() action, String success) async {
    setState(() => message = '');
    final ok = await run(() async {
      await action();
      await session.refreshProfile();
    });
    if (ok && mounted) {
      setState(() {
        code = '';
        codeKey++;
        message = success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSession>().admin ?? const {};
    final enabled = admin['two_factor_enabled'] == true;
    return SectionCard(
      title: 'SMS codes (two-step sign-in)',
      action: ToneBadge(enabled ? 'On' : 'Off', tone: enabled ? Tone.green : Tone.amber),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        Text(enabled
            ? 'Codes go to ${jstr(admin['phone'])}. You need one to sign in and to confirm every money action.'
            : 'Get a code on your phone when you sign in and before money actions. Required '
                '${admin['is_owner'] == true ? 'to withdraw platform commission and manage your team' : 'to send refunds or payouts of 50,000 RWF or more'}.'),
        if (!enabled) ...[
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizePhoneInput(next.text)))],
            decoration: InputDecoration(
              labelText: 'Your phone number',
              hintText: phonePlaceholder,
              errorText: phone.text.isNotEmpty && !isValidRwandaPhone(phone.text) ? phoneError : null,
              errorMaxLines: 2,
            ),
          ),
          ActionCodeField(
            key: ValueKey(codeKey),
            label: 'Code sent to that phone',
            onChanged: (value) => setState(() => code = value),
            send: () async {
              if (phone.text.trim().isEmpty) throw ApiException('Enter your phone number first.');
              if (!isValidRwandaPhone(phone.text)) throw ApiException(phoneError);
              return session.api.startTwoFactor(phone.text.trim());
            },
          ),
          BusyButton(
            label: 'Turn on SMS codes',
            busyLabel: 'Turning on…',
            busy: busy,
            onPressed: code.length != 6 ? null : () => change(() => session.api.enableTwoFactor(phone.text.trim(), code), 'SMS codes are on.'),
          ),
        ] else ...[
          ActionCodeField(key: ValueKey(codeKey), purpose: 'disable_2fa', onChanged: (value) => setState(() => code = value)),
          BusyButton(
            label: 'Turn off SMS codes',
            busyLabel: 'Turning off…',
            danger: true,
            busy: busy,
            onPressed: code.length != 6 ? null : () => change(() => session.api.disableTwoFactor(code), 'SMS codes are off.'),
          ),
        ],
        if (actionError != null) ErrorNote(error: actionError),
        if (message.isNotEmpty) Note(message, tone: Tone.green),
      ])),
    );
  }
}

class _ChangePasswordCard extends StatefulWidget {
  const _ChangePasswordCard();

  @override
  State<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<_ChangePasswordCard> with BusyState {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  String error = '';
  bool done = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => done = false);
    if (next.text.length < 8) return setState(() => error = 'New password must be at least 8 characters.');
    if (next.text != confirm.text) return setState(() => error = 'New passwords do not match.');
    setState(() => error = '');
    final session = context.read<AdminSession>();
    final ok = await run(() => session.api.changePassword({'current_password': current.text, 'new_password': next.text}));
    if (ok && mounted) {
      setState(() => done = true);
      current.clear();
      next.clear();
      confirm.clear();
      session.refreshProfile().catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Change password',
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
          TextField(controller: current, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(labelText: 'Current password')),
          TextField(
            controller: next,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters.'),
          ),
          TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
          if (error.isNotEmpty) Note(error),
          if (actionError != null) ErrorNote(error: actionError),
          if (done) const Note('Password updated.', tone: Tone.green),
          BusyButton(label: 'Update password', busyLabel: 'Updating…', busy: busy, onPressed: submit),
        ])),
      ),
    );
  }
}

// ---- Delivery & pickup rules ---------------------------------------------

class _Rule {
  const _Rule(this.field, this.group, this.from, this.label, this.unit, {this.decimal = false});

  final String field;
  final String group;
  final String from;
  final String label;
  final String unit;
  final bool decimal;
}

// Each editable rule: where it lives in the rules response and how it reads.
const _rules = [
  _Rule('radius_km', 'dispatch', 'radius_km', 'Notify delivery workers within', 'km of the kitchen', decimal: true),
  _Rule('max_offer_recipients', 'dispatch', 'max_drivers_per_broadcast', 'Most workers notified per order', 'workers'),
  _Rule('location_max_age_minutes', 'dispatch', 'driver_location_max_age_minutes', 'Their location must be newer than', 'minutes'),
  _Rule('rebroadcast_every_seconds', 'dispatch', 'rebroadcast_every_seconds', 'Re-offer open orders every', 'seconds'),
  _Rule('max_active_deliveries', 'dispatch', 'max_active_deliveries_per_driver', 'Max deliveries at once per worker', 'deliveries'),
  _Rule('platform_delivery_max_km', 'dispatch', 'platform_delivery_max_km', 'Delivery workers deliver up to', 'km from the kitchen', decimal: true),
  _Rule('pickup_code_max_attempts', 'customer_pickup', 'max_wrong_codes', 'Wrong pickup codes before the order locks', 'tries'),
];

/// The dispatch and customer-pickup rules the system runs with. Saved values
/// take effect right away.
class DeliveryRulesPage extends StatefulWidget {
  const DeliveryRulesPage({super.key});

  @override
  State<DeliveryRulesPage> createState() => _DeliveryRulesPageState();
}

class _DeliveryRulesPageState extends State<DeliveryRulesPage> with BusyState {
  late final session = context.read<AdminSession>();
  late final canEdit = session.can('deliveries:write');
  late final query = Query<Json>(() async => jmap(await session.api.operationsRules()))..addListener(_initForm);
  Map<String, TextEditingController>? form;
  bool saved = false;

  void _initForm() {
    final rules = query.data;
    if (rules == null || form != null) return;
    setState(() => form = _formFrom(rules));
  }

  Map<String, TextEditingController> _formFrom(Json rules) => {
        for (final rule in _rules) rule.field: TextEditingController(text: jstr(jmap(rules[rule.group])[rule.from])),
      };

  @override
  void dispose() {
    query.dispose();
    form?.values.forEach((c) => c.dispose());
    super.dispose();
  }

  _Rule? problem(Json rules) {
    final limits = jmap(rules['limits']);
    for (final rule in _rules) {
      final limit = (limits[rule.field] as List?) ?? const [];
      final text = form![rule.field]!.text;
      final n = num.tryParse(text);
      final min = limit.isNotEmpty ? jnum(limit[0]) : double.negativeInfinity;
      final max = limit.length > 1 ? jnum(limit[1]) : double.infinity;
      final decimals = limit.length > 2 && limit[2] != null && limit[2] != 0 && limit[2] != false;
      if (text.isEmpty || n == null || (!decimals && n != n.roundToDouble()) || n < min || n > max) return rule;
    }
    return null;
  }

  Future<void> save() async {
    final ok = await run(() async {
      final next = jmap(await session.api.saveOperationsRules({for (final rule in _rules) rule.field: num.parse(form![rule.field]!.text)}));
      for (final rule in _rules) {
        form![rule.field]!.text = jstr(jmap(next[rule.group])[rule.from]);
      }
      query.data = next;
    });
    if (ok && mounted) setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final go = context.read<ShellNavigator>().go;
    return QueryView<Json>(
      query: query,
      builder: (context, rules) {
        if (form == null) return const LoadingBlock();
        final limits = jmap(rules['limits']);
        final dispatch = jmap(rules['dispatch']);
        final pickupClock = jmap(rules['pickup_clock']);
        final fees = jmap(rules['fees']);
        final tracking = jmap(rules['tracking']);
        final sms = jmap(rules['sms']);
        final bad = problem(rules);
        String v(String field) => form![field]!.text.isEmpty ? '…' : form![field]!.text;

        Widget input(_Rule rule) {
          final limit = (limits[rule.field] as List?) ?? const [];
          return TextField(
            controller: form![rule.field],
            enabled: canEdit,
            keyboardType: TextInputType.numberWithOptions(decimal: rule.decimal),
            onChanged: (_) => setState(() => saved = false),
            decoration: InputDecoration(
              labelText: rule.label,
              helperText: '${rule.unit}${limit.length > 1 ? ' (${jstr(limit[0])}–${jstr(limit[1])})' : ''}',
            ),
          );
        }

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery & pickup rules'),
          const Hint('How orders are dispatched, collected and tracked. Changes apply as soon as you save.'),
          SectionCard(
            title: 'Dispatch',
            description: jstr(dispatch['offered_when']),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              for (final rule in _rules.where((r) => r.group == 'dispatch')) input(rule),
              Note(
                'A new order is sent to up to ${v('max_offer_recipients')} online delivery workers within ${v('radius_km')} km of the kitchen '
                'whose location is less than ${v('location_max_age_minutes')} min old and who carry fewer than ${v('max_active_deliveries')} '
                "deliveries. Workers further away can't take it. If nobody accepts, it is offered again every "
                '${v('rebroadcast_every_seconds')} s to anyone who has come into range.',
                tone: Tone.slate,
              ),
              Note(
                "Customers more than ${v('platform_delivery_max_km')} km from a kitchen can't get delivery workers. Nationwide kitchens "
                '(Caterers, and any kitchen you switch on in Vendors) bring those orders themselves for their own travel fee; other kitchens offer pickup only.',
                tone: Tone.slate,
              ),
            ])),
          ),
          SectionCard(
            title: 'Customer pickup',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              for (final rule in _rules.where((r) => r.group == 'customer_pickup')) input(rule),
              _ruleRow('Delivery fee', 'None'),
              _ruleRow('Pickup code', '${jstr(jmap(rules['customer_pickup'])['code_digits'])} digits, given when the order is placed'),
            ], 8)),
          ),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canEdit)
              BusyButton(label: 'Save rules', busy: busy, onPressed: bad != null ? null : save)
            else
              const ToneBadge('View only — ask an operations manager or the owner to change it'),
            if (saved) Hint('Saved. The system uses these rules now.', color: Tone.green.foreground(context)),
            if (bad != null) Hint('Check “${bad.label}”.', color: Tone.red.foreground(context)),
            if (dispatch['updated_at'] != null) Hint('Last changed ${formatDate(dispatch['updated_at'])}'),
          ]),
          if (actionError != null) ErrorNote(error: actionError),
          SectionCard(
            title: 'Pickup clock (delivery workers)',
            action: TextButton(onPressed: () => go(const AdminRoute(Pages.settingsTiming)), child: const Text('Edit')),
            child: Column(children: [
              _ruleRow('Reminder after', '${jstr(pickupClock['warning_after_minutes'])} min'),
              _ruleRow('Counts as late after', '${jstr(pickupClock['grace_minutes'])} min'),
              _ruleRow('Given to another worker after', pickupClock['reassign_after_minutes'] != null ? '${jstr(pickupClock['reassign_after_minutes'])} min' : 'Off'),
              _ruleRow('Late-pickup charge', 'None'),
            ]),
          ),
          SectionCard(
            title: 'Delivery fee',
            action: TextButton(onPressed: () => go(const AdminRoute(Pages.settingsFees)), child: const Text('Edit')),
            child: Column(children: [
              if (jlist(fees['ranges']).isNotEmpty)
                for (final range in jlist(fees['ranges']))
                  _ruleRow(
                    range['to_km'] == null ? '${jstr(range['from_km'])} km and more' : '${jstr(range['from_km'])}–${jstr(range['to_km'])} km',
                    formatRwf(range['fee_rwf']),
                  )
              else
                _ruleRow('Price', '${jstr(fees['base_rwf'])} RWF + ${jstr(fees['per_km_rwf'])} RWF/km (min ${jstr(fees['minimum_rwf'])} RWF)'),
              _ruleRow('Share paid to the delivery worker', '${jstr(fees['driver_share_percent'])}%'),
            ]),
          ),
          SectionCard(
            title: 'Maps & messages',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ruleRow('Routes & live tracking', jstr(tracking['routes_provider']), warn: tracking['google_key_configured'] != true),
              _ruleRow('Place search', jstr(tracking['place_search_provider'])),
              _ruleRow('SMS', jstr(sms['note']), warn: sms['configured'] != true),
              const SizedBox(height: 6),
              const Hint("These depend on the map and SMS service keys in the server configuration, so they can't be changed here."),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _ruleRow(String label, String value, {bool warn = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: warn ? Tone.amber.foreground(context) : null)),
          ),
        ]),
      );
}

// ---- Bank account numbers -------------------------------------------------

class _BankRow {
  _BankRow(String name, String min, String max)
      : name = TextEditingController(text: name),
        min = TextEditingController(text: min),
        max = TextEditingController(text: max);

  final TextEditingController name;
  final TextEditingController min;
  final TextEditingController max;

  void dispose() {
    name.dispose();
    min.dispose();
    max.dispose();
  }
}

/// The banks kitchens and delivery workers can withdraw to, and how many
/// digits each bank's account numbers have.
class BankFormatsPage extends StatefulWidget {
  const BankFormatsPage({super.key});

  @override
  State<BankFormatsPage> createState() => _BankFormatsPageState();
}

class _BankFormatsPageState extends State<BankFormatsPage> with BusyState {
  late final session = context.read<AdminSession>();
  late final canEdit = session.can('payouts:write');
  late final query = Query<Json>(() async => jmap(await session.api.bankFormats()))..addListener(_init);
  List<_BankRow>? rows;
  bool saved = false;

  void _init() {
    final data = query.data;
    if (data == null || rows != null) return;
    setState(() => rows = [
          for (final bank in jlist(data['banks']))
            _BankRow(jstr(bank['name']), bank['digits_min'] == null ? '' : jstr(bank['digits_min']), bank['digits_max'] == null ? '' : jstr(bank['digits_max'])),
        ]);
  }

  @override
  void dispose() {
    query.dispose();
    rows?.forEach((r) => r.dispose());
    super.dispose();
  }

  Future<void> save() async {
    final ok = await run(() async {
      query.data = jmap(await session.api.saveBankFormats({
        'banks': [
          for (final row in rows!.where((r) => r.name.text.trim().isNotEmpty))
            {
              'name': row.name.text.trim(),
              'digits_min': row.min.text.isEmpty ? null : int.parse(row.min.text),
              // Only one number typed means an exact length.
              'digits_max': row.max.text.isEmpty ? (row.min.text.isEmpty ? null : int.parse(row.min.text)) : int.parse(row.max.text),
            },
        ],
      }));
    });
    if (ok && mounted) setState(() => saved = true);
  }

  Widget _rule(_BankRow row) {
    final min = int.tryParse(row.min.text);
    final max = row.max.text.isEmpty ? min : int.tryParse(row.max.text);
    if (min == null) return const ToneBadge('Not set · 6–30 digits', tone: Tone.amber);
    if (max != null && max < min) return const ToneBadge('Check the numbers', tone: Tone.red);
    return ToneBadge(max == min ? 'Exactly $min digits' : '$min–$max digits', tone: Tone.green);
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)];
    return QueryView<Json>(
      query: query,
      builder: (context, data) {
        if (rows == null) return const LoadingBlock();
        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Bank account numbers'),
          const Hint("Banks people can withdraw to and how many digits each bank's account numbers have. The withdraw popup only accepts that many digits."),
          for (var i = 0; i < rows!.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: rows![i].name,
                        enabled: canEdit,
                        inputFormatters: [LengthLimitingTextInputFormatter(60)],
                        onChanged: (_) => setState(() => saved = false),
                        decoration: const InputDecoration(labelText: 'Bank'),
                      ),
                    ),
                    if (canEdit)
                      IconButton(
                        onPressed: () => setState(() {
                          rows!.removeAt(i).dispose();
                          saved = false;
                        }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ]),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: rows![i].min,
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        onChanged: (_) => setState(() => saved = false),
                        decoration: const InputDecoration(labelText: 'Digits', hintText: '?'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: rows![i].max,
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        onChanged: (_) => setState(() => saved = false),
                        decoration: const InputDecoration(labelText: 'Up to', hintText: 'same'),
                      ),
                    ),
                  ]),
                  Align(alignment: Alignment.centerLeft, child: _rule(rows![i])),
                ], 10)),
              ),
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => rows!.add(_BankRow('', '', ''))),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add a bank'),
              ),
            ),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canEdit) BusyButton(label: 'Save banks', busy: busy, onPressed: save) else const ToneBadge('View only'),
            if (saved) Hint('Saved. The withdraw popup uses these now.', color: Tone.green.foreground(context)),
            if (data['updated_at'] != null) Hint('Last changed ${formatDate(data['updated_at'])}'),
          ]),
          if (actionError != null) ErrorNote(error: actionError),
          const Hint('Bank of Kigali (14 digits) and I&M (16 digits) come from real account numbers; confirm the others with each bank before setting them. '
              'Type one number for an exact length, or both for a range. Banks not in the list (“Other bank”) accept 6–30 digits.'),
        ]);
      },
    );
  }
}

// ---- Delivery fee by distance ---------------------------------------------

const _minFee = 500;

class _FeeRow {
  _FeeRow(String to, String fee)
      : to = TextEditingController(text: to),
        fee = TextEditingController(text: fee);

  final TextEditingController to;
  final TextEditingController fee;

  void dispose() {
    to.dispose();
    fee.dispose();
  }
}

/// Delivery fee by distance, e.g. 0–3 km: 500 RWF, 3–6 km: 1,000 RWF, 6 km and
/// more: 1,500 RWF. Each range starts where the previous one ends, the last
/// one has no end, and no fee can be below 500 RWF.
class DeliveryFeesPage extends StatefulWidget {
  const DeliveryFeesPage({super.key});

  @override
  State<DeliveryFeesPage> createState() => _DeliveryFeesPageState();
}

class _DeliveryFeesPageState extends State<DeliveryFeesPage> with BusyState {
  late final session = context.read<AdminSession>();
  late final canEdit = session.can('deliveries:write');
  late final query = Query<Json>(() async => jmap(await session.api.deliveryFees()))..addListener(_init);
  List<_FeeRow>? rows;
  bool saved = false;

  void _init() {
    final data = query.data;
    if (data == null || rows != null) return;
    final ranges = jlist(data['ranges']);
    setState(() => rows = ranges.isNotEmpty
        ? [for (final r in ranges) _FeeRow(r['to_km'] == null ? '' : jstr(r['to_km']), jstr(r['fee_rwf']))]
        // Suggested start: same feel as the standard formula.
        : [_FeeRow('3', '800'), _FeeRow('6', '1500'), _FeeRow('', '2500')]);
  }

  @override
  void dispose() {
    query.dispose();
    rows?.forEach((r) => r.dispose());
    super.dispose();
  }

  /// Rows → ranges with numbers (to = null on the last, open-ended range).
  List<({num from, num? to, num fee})> get ranges => [
        for (var i = 0; i < rows!.length; i++)
          (
            from: i == 0 ? 0 : num.tryParse(rows![i - 1].to.text) ?? 0,
            to: i == rows!.length - 1 ? null : (num.tryParse(rows![i].to.text) ?? double.nan),
            fee: num.tryParse(rows![i].fee.text) ?? double.nan,
          ),
      ];

  List<String> problems(List<({num from, num? to, num fee})> ranges) => [
        for (var i = 0; i < ranges.length; i++) ...[
          if (ranges[i].to != null && !(ranges[i].to! > ranges[i].from)) 'Range ${i + 1}: the end must be more than ${_km(ranges[i].from)} km.',
          if (ranges[i].fee.isNaN || ranges[i].fee != ranges[i].fee.roundToDouble() || ranges[i].fee < _minFee)
            'Range ${i + 1}: the fee must be at least $_minFee RWF.',
        ],
      ];

  String _km(num value) => value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  String _label(num from, num? to) => to == null ? '${_km(from)} km and more' : '${_km(from)} km up to ${_km(to)} km';

  void addRange() {
    setState(() {
      saved = false;
      final last = rows!.last;
      final lastFrom = rows!.length > 1 ? num.tryParse(rows![rows!.length - 2].to.text) ?? 0 : 0;
      last.to.text = _km(lastFrom + 3);
      rows!.add(_FeeRow('', last.fee.text));
    });
  }

  void removeRange(int index) {
    setState(() {
      saved = false;
      rows!.removeAt(index).dispose();
      if (rows!.isNotEmpty) rows!.last.to.text = '';
    });
  }

  Future<void> save(List<({num from, num? to, num fee})> ranges) async {
    final ok = await run(() async {
      query.data = jmap(await session.api.saveDeliveryFees({
        'ranges': [for (final r in ranges) {'from_km': r.from, 'to_km': r.to, 'fee_rwf': r.fee.toInt()}],
      }));
    });
    if (ok && mounted) setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return QueryView<Json>(
      query: query,
      builder: (context, data) {
        if (rows == null) return const LoadingBlock();
        final current = ranges;
        final issues = problems(current);
        final usingRanges = jlist(data['ranges']).isNotEmpty;
        final kmFormatter = TextInputFormatter.withFunction((old, next) {
          final cleaned = next.text.replaceAll(RegExp(r'[^\d.]'), '').replaceAllMapped(RegExp(r'(\..*)\.'), (m) => m.group(1)!);
          return next.copyWith(text: cleaned.length > 5 ? cleaned.substring(0, 5) : cleaned);
        });
        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery fee by distance'),
          const Hint('Set the delivery fee for each distance range, from the kitchen to the customer by road. '
              'The delivery worker keeps the whole fee. No fee can be below 500 RWF.'),
          if (!usingRanges)
            const Note(
              'Not set yet — fees use the standard formula (500 RWF + 200 RWF per km, at least 800 RWF). Save ranges below to use your own prices.',
              tone: Tone.amber,
            ),
          for (var i = 0; i < rows!.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(width: 76, child: Text('From ${_km(current[i].from)} km', style: const TextStyle(fontWeight: FontWeight.w800))),
                  Expanded(
                    child: i == rows!.length - 1
                        ? const Text('and more', style: TextStyle(fontWeight: FontWeight.w700))
                        : TextField(
                            controller: rows![i].to,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [kmFormatter],
                            onChanged: (_) => setState(() => saved = false),
                            decoration: const InputDecoration(labelText: 'to (km)'),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: rows![i].fee,
                      enabled: canEdit,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      onChanged: (_) => setState(() => saved = false),
                      decoration: InputDecoration(
                        labelText: 'Fee (RWF)',
                        errorText: (num.tryParse(rows![i].fee.text) ?? 0) > 0 && (num.tryParse(rows![i].fee.text) ?? 0) < _minFee ? 'Below 500 RWF' : null,
                      ),
                    ),
                  ),
                  if (canEdit && rows!.length > 1) IconButton(onPressed: () => removeRange(i), icon: const Icon(Icons.delete_outline)),
                ]),
              ),
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: addRange, icon: const Icon(Icons.add, size: 16), label: const Text('Add a range')),
            ),
          if (issues.isNotEmpty)
            Note(issues.join('\n'))
          else
            SectionCard(
              title: 'Customers will pay',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in current)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${_label(r.from, r.to)}: '),
                      TextSpan(text: formatRwf(r.fee), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ])),
                  ),
              ]),
            ),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canEdit)
              BusyButton(label: 'Save delivery fees', busy: busy, onPressed: issues.isNotEmpty ? null : () => save(current))
            else
              const ToneBadge('View only'),
            if (saved) Hint('Saved. New orders use these fees.', color: Tone.green.foreground(context)),
            if (data['updated_at'] != null) Hint('Last changed ${formatDate(data['updated_at'])}'),
          ]),
          const Hint('A distance exactly on the edge (e.g. 3 km) uses the next range. Orders already placed keep the fee they were charged.'),
          if (actionError != null) ErrorNote(error: actionError),
        ]);
      },
    );
  }
}

// ---- Delivery timing ------------------------------------------------------

/// How long a delivery worker has to collect a ready order — when they're
/// reminded, when the pickup counts as late (support is alerted), and when
/// the order is given to another nearby worker. Late pickups are never charged.
class DeliveryTimingPage extends StatefulWidget {
  const DeliveryTimingPage({super.key});

  @override
  State<DeliveryTimingPage> createState() => _DeliveryTimingPageState();
}

class _DeliveryTimingPageState extends State<DeliveryTimingPage> with BusyState {
  late final session = context.read<AdminSession>();
  late final canEdit = session.can('deliveries:write');
  late final query = Query<Json>(() async => jmap(await session.api.deliveryTiming()), client: session.client)..addListener(_init);
  TextEditingController? warning;
  TextEditingController? charge;
  TextEditingController? reassign;
  bool reassignOn = false;
  bool saved = false;

  void _init() {
    final timing = jmap(query.data?['timing']);
    if (timing.isEmpty || warning != null) return;
    setState(() {
      warning = TextEditingController(text: jstr(timing['warning_minutes']));
      charge = TextEditingController(text: jstr(timing['charge_after_minutes']));
      reassignOn = timing['reassign_after_minutes'] != null;
      reassign = TextEditingController(text: jstr(timing['reassign_after_minutes'], '${jint(timing['charge_after_minutes']) * 2}'));
    });
  }

  @override
  void dispose() {
    query.dispose();
    warning?.dispose();
    charge?.dispose();
    reassign?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QueryView<Json>(
      query: query,
      builder: (context, data) {
        if (warning == null) return const LoadingBlock();
        final timing = jmap(data['timing']);
        final w = num.tryParse(warning!.text) ?? 0;
        final c = num.tryParse(charge!.text) ?? 0;
        final r = num.tryParse(reassign!.text) ?? 0;
        final valid = w > 0 && c > w && (!reassignOn || r > c);
        // A worked example so the effect of the numbers is obvious.
        final now = DateTime.now();
        final noon = DateTime(now.year, now.month, now.day, 12);
        String at(num minutes) => formatTime(noon.add(Duration(minutes: minutes.toInt())));
        final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery timing'),
          const Hint('For delivery workers who delay collecting an order that is ready. Times count from when the kitchen marks the food ready. '
              'Workers see these rules before they accept.'),
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              TextField(
                controller: warning,
                enabled: canEdit,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() => saved = false),
                decoration: const InputDecoration(labelText: 'Remind the worker after', helperText: 'minutes'),
              ),
              TextField(
                controller: charge,
                enabled: canEdit,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() => saved = false),
                decoration: const InputDecoration(labelText: 'Counts as late after', helperText: 'minutes'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Give to another worker automatically'),
                value: reassignOn,
                onChanged: canEdit
                    ? (value) => setState(() {
                          reassignOn = value;
                          saved = false;
                        })
                    : null,
              ),
              TextField(
                controller: reassign,
                enabled: canEdit && reassignOn,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() => saved = false),
                decoration: InputDecoration(labelText: 'Give to another worker after', helperText: reassignOn ? 'minutes' : 'switched off'),
              ),
            ])),
          ),
          SectionCard(
            title: 'Example: food ready at ${at(0)}',
            child: valid
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
                    Text('${at(w)} — the worker is reminded to collect it.'),
                    Text('${at(c)} — not collected: late pickup recorded and support is alerted. No charge is taken.'),
                    reassignOn
                        ? Text('${at(r)} — still not collected: the order is taken away and offered to other nearby workers '
                            '(never back to the late one). The kitchen and customer are told.')
                        : const Hint('The order is never taken away automatically — support can still reassign it by phone.'),
                  ], 6))
                : Note('The reminder must come before the pickup counts as late${reassignOn ? ', and giving it to another worker must come after that' : ''}.'),
          ),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canEdit)
              BusyButton(
                label: 'Save timing',
                busy: busy,
                onPressed: !valid
                    ? null
                    : () async {
                        final ok = await run(() => session.api.saveDeliveryTiming({
                              'warning_minutes': w,
                              'charge_after_minutes': c,
                              'reassign_after_minutes': reassignOn ? r : null,
                            }));
                        if (ok && mounted) setState(() => saved = true);
                      },
              )
            else
              const ToneBadge('View only — ask an operations manager or the owner to change it'),
            if (saved) Hint('Saved. New pickups use these times.', color: Tone.green.foreground(context)),
            if (timing['updated_at'] != null) Hint('Last changed ${formatDate(timing['updated_at'])}'),
          ]),
          if (actionError != null) ErrorNote(error: actionError),
          const Hint('Changes apply to orders that become ready after you save. A worker who takes over a late order '
              '(assigned by support or re-offered) gets this time again from when they take it.'),
          const Hint('Late pickups are never charged: a worker who delivers is always paid the full delivery fee. '
              'A worker who is too late only loses the order to another worker.'),
        ]);
      },
    );
  }
}
