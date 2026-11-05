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
    final p = Palette.of(context);
    final active = admin['is_active'] == true;
    // The website's ProfileSection: `space-y-5` of the warning and three cards.
    return PageBody(children: [
      const PageHeader(title: 'Settings', description: 'Profile & account security'),
      if (session.usesDefaultPassword) const _DefaultPasswordAlert(),
      SectionCard(
        title: 'Profile',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // `flex items-center gap-4`.
          Row(children: [
            // `w-14 h-14 rounded-2xl bg-gradient-to-br from-[#111827] via-[#1f2937] to-[#0b1220]`, ShieldCheck `w-7 h-7`.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(gradient: AppColors.brandDiagonal, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // `text-lg font-black text-gray-900`.
                Text(jstr(admin['name']), style: TextStyle(fontSize: 18, height: 1.55, fontWeight: FontWeight.w900, color: p.text)),
                // `text-sm text-stone-500`.
                Text(jstr(admin['email']), style: TextStyle(fontSize: 14, height: 1.43, color: p.muted)),
                // `mt-1.5 flex items-center gap-2`.
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  ToneBadge(toTitle(admin['role']), tone: Tone.violet),
                  ToneBadge(active ? 'Active' : 'Disabled', tone: active ? Tone.green : Tone.red),
                ]),
              ]),
            ),
          ]),
          // `mt-4 text-xs text-stone-400`.
          const SizedBox(height: 16),
          Text('Last login: ${formatDate(admin['last_login_at'])}', style: TextStyle(fontSize: 12, height: 1.33, color: p.faint)),
          if (session.permissions.isNotEmpty) ...[
            // `mt-4`; label `text-xs font-black uppercase tracking-wider text-stone-400 mb-2`; badges `gap-1.5`.
            const SizedBox(height: 16),
            const SectionLabel('Permissions'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final permission in session.permissions) ToneBadge(permission)]),
          ],
        ]),
      ),
      const _TwoFactorCard(),
      const _ChangePasswordCard(),
    ]);
  }
}

/// `role="alert" flex items-start gap-3 rounded-2xl bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800`.
class _DefaultPasswordAlert extends StatelessWidget {
  const _DefaultPasswordAlert();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Tone.red.foreground(context) : const Color(0xFF991B1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Tone.red.background(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tone.red.border(context)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.warning_amber_rounded, size: 20, color: fg)),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'You are still using the '),
              const TextSpan(text: 'default admin password', style: TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(
                text: '. Anyone who knows it can sign in. Change it below: the rest of the admin panel stays locked until you do.',
              ),
            ]),
            style: TextStyle(fontSize: 14, height: 1.43, color: fg),
          ),
        ),
      ]),
    );
  }
}

/// The website's form column: `max-w-md space-y-4`, controls left-aligned.
class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(children, 16)),
      ),
    );
  }
}

/// A left-aligned (not stretched) website button, like an inline `<Button>`.
Widget _inlineButton(Widget button) => Align(alignment: Alignment.centerLeft, child: button);

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
    final p = Palette.of(context);
    final admin = context.watch<AdminSession>().admin ?? const {};
    final enabled = admin['two_factor_enabled'] == true;
    final phoneInvalid = phone.text.isNotEmpty && !isValidRwandaPhone(phone.text);
    return SectionCard(
      title: 'SMS codes (two-step sign-in)',
      child: _FormColumn(children: [
        // `flex items-start gap-3`: phone tile, explanation, On/Off badge.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // `w-10 h-10 rounded-xl bg-stone-100`, Smartphone `w-5 h-5 text-stone-700`.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.stone100, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.smartphone, size: 20, color: p.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            // `text-sm text-stone-600`.
            child: Text.rich(
              TextSpan(
                children: enabled
                    ? [
                        const TextSpan(text: 'Codes go to '),
                        TextSpan(text: jstr(admin['phone']), style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                        const TextSpan(text: '. You need one to sign in and to confirm every money action.'),
                      ]
                    : [
                        const TextSpan(text: 'Get a code on your phone when you sign in and before money actions. '),
                        const TextSpan(text: 'Required', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                          text: admin['is_owner'] == true
                              ? ' to withdraw platform commission and manage your team.'
                              : ' to send refunds or payouts of 50,000 RWF or more.',
                        ),
                      ],
              ),
              style: TextStyle(fontSize: 14, height: 1.43, color: p.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          ToneBadge(enabled ? 'On' : 'Off', tone: enabled ? Tone.green : Tone.amber),
        ]),
        if (!enabled) ...[
          WebField(
            label: 'Your phone number',
            hint: phoneInvalid ? Text(phoneError, style: const TextStyle(color: AppColors.red500, fontWeight: FontWeight.w600)) : null,
            child: WebInput(
              controller: phone,
              keyboardType: TextInputType.phone,
              hint: phonePlaceholder,
              onChanged: (_) => setState(() {}),
              inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizePhoneInput(next.text)))],
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
          _inlineButton(WebButton(
            label: busy ? 'Turning on…' : 'Turn on SMS codes',
            onPressed: busy || code.length != 6 ? null : () => change(() => session.api.enableTwoFactor(phone.text.trim(), code), 'SMS codes are on.'),
          )),
        ] else ...[
          ActionCodeField(key: ValueKey(codeKey), purpose: 'disable_2fa', onChanged: (value) => setState(() => code = value)),
          _inlineButton(WebButton(
            label: busy ? 'Turning off…' : 'Turn off SMS codes',
            danger: true,
            onPressed: busy || code.length != 6 ? null : () => change(() => session.api.disableTwoFactor(code), 'SMS codes are off.'),
          )),
        ],
        if (actionError != null) ErrorNote(error: actionError),
        if (message.isNotEmpty) Note(message, tone: Tone.green),
      ]),
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
        child: _FormColumn(children: [
          WebField(
            label: 'Current password',
            child: WebInput(controller: current, obscure: true, autofillHints: const [AutofillHints.password]),
          ),
          WebField(
            label: 'New password',
            hint: const Text('At least 8 characters.'),
            child: WebInput(controller: next, obscure: true, autofillHints: const [AutofillHints.newPassword]),
          ),
          WebField(
            label: 'Confirm new password',
            child: WebInput(controller: confirm, obscure: true, autofillHints: const [AutofillHints.newPassword]),
          ),
          if (error.isNotEmpty) ErrorNote(error: error),
          if (actionError != null) ErrorNote(error: actionError),
          if (done) const Note('Password updated.', tone: Tone.green),
          _inlineButton(WebButton(label: busy ? 'Updating…' : 'Update password', onPressed: busy ? null : submit)),
        ]),
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
    final p = Palette.of(context);
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
        final lg = MediaQuery.sizeOf(context).width >= 1024;

        // The website's Field + `type="number"` Input; hint `unit (min–max)`.
        Widget input(_Rule rule) {
          final limit = (limits[rule.field] as List?) ?? const [];
          return WebField(
            label: rule.label,
            hint: Text('${rule.unit}${limit.length > 1 ? ' (${jstr(limit[0])}–${jstr(limit[1])})' : ''}'),
            child: WebInput(
              controller: form![rule.field],
              readOnly: !canEdit,
              keyboardType: TextInputType.numberWithOptions(decimal: rule.decimal),
              onChanged: (_) => setState(() => saved = false),
            ),
          );
        }

        // `grid gap-4 sm:grid-cols-2 lg:grid-cols-3`.
        Widget fields(String group) => _webGrid(context, [for (final rule in _rules.where((r) => r.group == group)) input(rule)]);

        // `mt-3 rounded-2xl bg-stone-50 border border-stone-100 p-3 text-sm text-stone-700`, values in `<strong>`.
        Widget explainer(List<InlineSpan> spans) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.divider)),
              child: Text.rich(TextSpan(children: spans), style: TextStyle(fontSize: 14, height: 1.43, color: p.textSecondary)),
            );
        InlineSpan b(String text) => TextSpan(text: text, style: TextStyle(fontWeight: FontWeight.w700, color: p.text));

        // `flex items-center justify-between`: section label and an "Edit in …" link.
        Widget headingWithLink(String label, String link, AdminPage page, {required double top}) => Padding(
              padding: EdgeInsets.only(top: top, bottom: 4),
              child: Row(children: [
                Expanded(child: _sectionHeading(context, label)),
                InkWell(
                  onTap: () => go(AdminRoute(page)),
                  child: Text(link, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.accent)),
                ),
              ]),
            );

        final clockAndFees = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          headingWithLink('Pickup clock (delivery workers)', 'Edit in Delivery timing', Pages.settingsTiming, top: 12),
          ..._ruleRows([
            ('Reminder after', '${jstr(pickupClock['warning_after_minutes'])} min', false),
            ('Counts as late after', '${jstr(pickupClock['grace_minutes'])} min', false),
            (
              'Given to another worker after',
              pickupClock['reassign_after_minutes'] != null ? '${jstr(pickupClock['reassign_after_minutes'])} min' : 'Off',
              false,
            ),
            ('Late-pickup charge', 'None', false),
          ]),
          headingWithLink('Delivery fee', 'Edit in Delivery fee by distance', Pages.settingsFees, top: 16),
          ..._ruleRows([
            if (jlist(fees['ranges']).isNotEmpty)
              for (final range in jlist(fees['ranges']))
                (
                  range['to_km'] == null ? '${jstr(range['from_km'])} km and more' : '${jstr(range['from_km'])}–${jstr(range['to_km'])} km',
                  formatRwf(range['fee_rwf']),
                  false,
                )
            else
              ('Price', '${jstr(fees['base_rwf'])} RWF + ${jstr(fees['per_km_rwf'])} RWF/km (min ${jstr(fees['minimum_rwf'])} RWF)', false),
            ('Share paid to the delivery worker', '${jstr(fees['driver_share_percent'])}%', false),
          ]),
        ]);

        final mapsAndMessages = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: _sectionHeading(context, 'Maps & messages')),
          ..._ruleRows([
            ('Routes & live tracking', jstr(tracking['routes_provider']), tracking['google_key_configured'] != true),
            ('Place search', jstr(tracking['place_search_provider']), false),
            ('SMS', jstr(sms['note']), sms['configured'] != true),
          ]),
          const SizedBox(height: 8),
          Text(
            "These depend on the map and SMS service keys in the server configuration, so they can't be changed here.",
            style: TextStyle(fontSize: 11, height: 1.45, color: p.faint),
          ),
        ]);

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery & pickup rules'),
          SectionCard(
            title: 'Delivery & pickup rules',
            description: 'How orders are dispatched, collected and tracked. Changes apply as soon as you save.',
            action: Icon(Icons.radar_outlined, size: 20, color: p.faint),
            // `space-y-6`.
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              // Dispatch.
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(bottom: 4), child: _sectionHeading(context, 'Dispatch')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(jstr(dispatch['offered_when']), style: TextStyle(fontSize: 12, height: 1.33, color: p.muted)),
                ),
                fields('dispatch'),
                const SizedBox(height: 12),
                explainer([
                  const TextSpan(text: 'A new order is sent to up to '),
                  b(v('max_offer_recipients')),
                  const TextSpan(text: ' online delivery workers within '),
                  b('${v('radius_km')} km'),
                  const TextSpan(text: ' of the kitchen whose location is less than '),
                  b('${v('location_max_age_minutes')} min'),
                  const TextSpan(text: ' old and who carry fewer than '),
                  b(v('max_active_deliveries')),
                  const TextSpan(text: " deliveries. Workers further away can't take it. If nobody accepts, it is offered again every "),
                  b('${v('rebroadcast_every_seconds')} s'),
                  const TextSpan(text: ' to anyone who has come into range.'),
                ]),
                const SizedBox(height: 8),
                explainer([
                  const TextSpan(text: 'Customers more than '),
                  b('${v('platform_delivery_max_km')} km'),
                  const TextSpan(
                    text: " from a kitchen can't get delivery workers. Nationwide kitchens (Caterers, and any kitchen you switch on in "
                        'Vendors) bring those orders themselves for their own travel fee; other kitchens offer pickup only.',
                  ),
                ]),
              ]),
              // Customer pickup.
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(bottom: 4), child: _sectionHeading(context, 'Customer pickup')),
                fields('customer_pickup'),
                ..._ruleRows([
                  ('Delivery fee', 'None', false),
                  ('Pickup code', '${jstr(jmap(rules['customer_pickup'])['code_digits'])} digits, given when the order is placed', false),
                ]),
              ]),
              // `flex flex-wrap items-center gap-3`: save button and status.
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (canEdit)
                  WebButton(label: busy ? 'Saving…' : 'Save rules', onPressed: bad != null || busy ? null : save)
                else
                  const ToneBadge('View only — ask an operations manager or the owner to change it'),
                if (saved)
                  Text('Saved. The system uses these rules now.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.green.foreground(context))),
                if (bad != null)
                  Text('Check “${bad.label}”.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.red.foreground(context))),
                if (dispatch['updated_at'] != null)
                  Text('Last changed ${formatDate(dispatch['updated_at'])}', style: TextStyle(fontSize: 11, color: p.faint)),
              ]),
              if (actionError != null) ErrorNote(error: actionError),
              // `grid gap-6 lg:grid-cols-2 pt-2 border-t border-stone-100`.
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.divider))),
                child: lg
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: clockAndFees),
                        const SizedBox(width: 24),
                        Expanded(child: mapsAndMessages),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [clockAndFees, const SizedBox(height: 24), mapsAndMessages]),
              ),
            ], 24)),
          ),
        ]);
      },
    );
  }

  /// `text-xs font-black uppercase tracking-wider text-stone-400`.
  Widget _sectionHeading(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Palette.of(context).faint),
      );

  /// RuleRow: `flex justify-between gap-4 py-2 border-b border-stone-50 last:border-0`;
  /// label `text-sm text-stone-600`, value `text-sm font-bold text-right` (amber when [warn]).
  List<Widget> _ruleRows(List<(String, String, bool)> rows) {
    final p = Palette.of(context);
    return [
      for (var i = 0; i < rows.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: p.stone50))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(rows[i].$1, style: TextStyle(fontSize: 14, height: 1.43, color: p.textSecondary))),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                rows[i].$2,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.43,
                  fontWeight: FontWeight.w700,
                  color: rows[i].$3 ? Tone.amber.foreground(context) : p.text,
                ),
              ),
            ),
          ]),
        ),
    ];
  }
}

/// `grid gap-4 sm:grid-cols-2 lg:grid-cols-3` (breakpoints on the screen width).
Widget _webGrid(BuildContext context, List<Widget> children) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = width >= 1024 ? 3 : width >= 640 ? 2 : 1;
  if (columns == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(children, 16));
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
    for (var i = 0; i < children.length; i += columns)
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var j = 0; j < columns; j++) ...[
          if (j > 0) const SizedBox(width: 16),
          Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()),
        ],
      ]),
  ], 16));
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
    final p = Palette.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)];
    void changed(_) => setState(() => saved = false);

    // `text-[11px] font-black uppercase tracking-wider text-stone-400`.
    Widget head(String text) => Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11, height: 1.45, fontWeight: FontWeight.w800, letterSpacing: 0.55, color: p.faint),
        );

    // One table row: Bank (flexible), Digits `w-24`, Up to `w-24`, Rule, delete `w-10`; cells `py-2 pr-3`.
    Widget tableRow({required Widget bank, required Widget min, required Widget max, required Widget rule, Widget? remove, bool border = true}) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: border ? Border(top: BorderSide(color: p.divider)) : null),
          child: Row(children: [
            Expanded(child: bank),
            const SizedBox(width: 12),
            SizedBox(width: 84, child: min),
            const SizedBox(width: 12),
            SizedBox(width: 84, child: max),
            const SizedBox(width: 12),
            SizedBox(width: 148, child: Align(alignment: Alignment.centerLeft, child: rule)),
            SizedBox(width: 40, child: Align(alignment: Alignment.centerRight, child: remove)),
          ]),
        );

    return QueryView<Json>(
      query: query,
      builder: (context, data) {
        if (rows == null) return const LoadingBlock();
        final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tableRow(bank: head('Bank'), min: head('Digits'), max: head('Up to'), rule: head('Rule'), border: false),
          for (var i = 0; i < rows!.length; i++)
            tableRow(
              bank: WebInput(
                controller: rows![i].name,
                readOnly: !canEdit,
                inputFormatters: [LengthLimitingTextInputFormatter(60)],
                onChanged: changed,
              ),
              min: WebInput(controller: rows![i].min, readOnly: !canEdit, hint: '?', keyboardType: TextInputType.number, inputFormatters: digits, onChanged: changed),
              max: WebInput(controller: rows![i].max, readOnly: !canEdit, hint: 'same', keyboardType: TextInputType.number, inputFormatters: digits, onChanged: changed),
              rule: _rule(rows![i]),
              // `p-1.5 rounded-lg text-stone-400`, Trash2 `w-4 h-4`.
              remove: canEdit
                  ? InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() {
                        rows!.removeAt(i).dispose();
                        saved = false;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline, size: 16, color: p.faint, semanticLabel: 'Remove ${rows![i].name.text}'),
                      ),
                    )
                  : null,
            ),
        ]);

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Bank account numbers'),
          SectionCard(
            title: 'Bank account numbers',
            description: "Banks people can withdraw to and how many digits each bank's account numbers have. The withdraw popup only accepts that many digits.",
            action: Icon(Icons.account_balance_outlined, size: 20, color: p.faint),
            // `space-y-4`.
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              // `overflow-x-auto`: the table scrolls sideways on narrow screens.
              LayoutBuilder(builder: (context, constraints) {
                const minWidth = 560.0;
                if (constraints.maxWidth >= minWidth) return table;
                return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, child: table));
              }),
              if (canEdit)
                // `inline-flex items-center gap-1.5 text-xs font-bold text-stone-600`.
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => setState(() => rows!.add(_BankRow('', '', ''))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, size: 14, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Text('Add a bank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
                    ]),
                  ),
                ),
              // `flex flex-wrap items-center gap-3`.
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (canEdit) WebButton(label: busy ? 'Saving…' : 'Save banks', onPressed: busy ? null : save) else const ToneBadge('View only'),
                if (saved)
                  Text('Saved. The withdraw popup uses these now.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.green.foreground(context))),
                if (data['updated_at'] != null) Text('Last changed ${formatDate(data['updated_at'])}', style: TextStyle(fontSize: 11, color: p.faint)),
              ]),
              // `text-[11px] text-stone-400`.
              Text(
                'Bank of Kigali (14 digits) and I&M (16 digits) come from real account numbers; confirm the others with each bank before setting them. '
                'Type one number for an exact length, or both for a range. Banks not in the list (“Other bank”) accept 6–30 digits.',
                style: TextStyle(fontSize: 11, height: 1.45, color: p.faint),
              ),
              if (actionError != null) ErrorNote(error: actionError),
            ], 16)),
          ),
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
    final p = Palette.of(context);
    final muted = TextStyle(fontSize: 14, height: 1.43, color: p.muted);
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

        // One range: `flex flex-wrap items-center gap-2 rounded-xl border border-stone-200 px-3 py-2.5`.
        Widget rangeRow(int i) {
          final isLast = i == rows!.length - 1;
          final fee = num.tryParse(rows![i].fee.text) ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Row(children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  // `text-sm font-bold text-gray-900 w-20`.
                  SizedBox(
                    width: 80,
                    child: Text('From ${_km(current[i].from)} km', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: p.text)),
                  ),
                  // `w-32`: "to [km] km", or "and more" on the last range.
                  SizedBox(
                    width: 128,
                    child: isLast
                        ? Text('and more', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: p.textSecondary))
                        : Row(children: [
                            Text('to', style: muted),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 64,
                              child: WebInput(
                                controller: rows![i].to,
                                readOnly: !canEdit,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [kmFormatter],
                                onChanged: (_) => setState(() => saved = false),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('km', style: muted),
                          ]),
                  ),
                  // Fee `w-24` + "RWF".
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 96,
                      child: WebInput(
                        controller: rows![i].fee,
                        readOnly: !canEdit,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        onChanged: (_) => setState(() => saved = false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('RWF', style: muted),
                  ]),
                  if (fee > 0 && fee < _minFee) const ToneBadge('Below 500 RWF', tone: Tone.red),
                ]),
              ),
              // `ml-auto p-1.5 rounded-lg text-stone-400`, Trash2 `w-4 h-4`.
              if (canEdit && rows!.length > 1)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => removeRange(i),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline, size: 16, color: p.faint, semanticLabel: 'Remove range ${i + 1}'),
                  ),
                ),
            ]),
          );
        }

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery fee by distance'),
          SectionCard(
            title: 'Delivery fee by distance',
            description: 'Set the delivery fee for each distance range, from the kitchen to the customer by road. '
                'The delivery worker keeps the whole fee. No fee can be below 500 RWF.',
            action: Icon(Icons.pedal_bike_outlined, size: 20, color: p.faint),
            // `space-y-4`.
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              if (!usingRanges)
                const Note(
                  'Not set yet — fees use the standard formula (500 RWF + 200 RWF per km, at least 800 RWF). Save ranges below to use your own prices.',
                  tone: Tone.amber,
                ),
              // `space-y-2`.
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([for (var i = 0; i < rows!.length; i++) rangeRow(i)], 8)),
              if (canEdit)
                // `inline-flex items-center gap-1.5 text-xs font-bold text-stone-600`.
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: addRange,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, size: 14, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Text('Add a range', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
                    ]),
                  ),
                ),
              if (issues.isNotEmpty)
                // `text-xs font-semibold text-red-700 space-y-0.5`.
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final issue in issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(issue, style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w600, color: Tone.red.foreground(context))),
                    ),
                ])
              else
                // `rounded-2xl bg-stone-50 border border-stone-100 p-3 text-sm text-stone-700`.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.divider)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('CUSTOMERS WILL PAY',
                          style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.faint)),
                    ),
                    for (final r in current)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${_label(r.from, r.to)}: '),
                            TextSpan(text: formatRwf(r.fee), style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                          ]),
                          style: TextStyle(fontSize: 14, height: 1.43, color: p.textSecondary),
                        ),
                      ),
                  ]),
                ),
              // `flex flex-wrap items-center gap-3`.
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (canEdit)
                  WebButton(label: busy ? 'Saving…' : 'Save delivery fees', onPressed: issues.isNotEmpty || busy ? null : () => save(current))
                else
                  const ToneBadge('View only'),
                if (saved)
                  Text('Saved. New orders use these fees.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.green.foreground(context))),
                if (data['updated_at'] != null) Text('Last changed ${formatDate(data['updated_at'])}', style: TextStyle(fontSize: 11, color: p.faint)),
              ]),
              Text(
                'A distance exactly on the edge (e.g. 3 km) uses the next range. Orders already placed keep the fee they were charged.',
                style: TextStyle(fontSize: 11, height: 1.45, color: p.faint),
              ),
              if (actionError != null) ErrorNote(error: actionError),
            ], 16)),
          ),
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
    final p = Palette.of(context);
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
        void changed(_) => setState(() => saved = false);
        final body = TextStyle(fontSize: 14, height: 1.43, color: p.textSecondary);
        TextSpan strong(String text) => TextSpan(text: text, style: TextStyle(fontWeight: FontWeight.w700, color: p.text));

        final fields = [
          WebField(
            label: 'Remind the worker after',
            hint: const Text('minutes'),
            child: WebInput(controller: warning, readOnly: !canEdit, keyboardType: TextInputType.number, inputFormatters: digits, onChanged: changed),
          ),
          WebField(
            label: 'Counts as late after',
            hint: const Text('minutes'),
            child: WebInput(controller: charge, readOnly: !canEdit, keyboardType: TextInputType.number, inputFormatters: digits, onChanged: changed),
          ),
          WebField(
            label: 'Give to another worker after',
            hint: Text(reassignOn ? 'minutes' : 'switched off'),
            // `flex items-center gap-2`: the input and an "On" checkbox.
            child: Row(children: [
              Expanded(
                child: WebInput(
                  controller: reassign,
                  enabled: canEdit && reassignOn,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  onChanged: changed,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: canEdit
                    ? () => setState(() {
                          reassignOn = !reassignOn;
                          saved = false;
                        })
                    : null,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: reassignOn,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: canEdit
                          ? (value) => setState(() {
                                reassignOn = value ?? false;
                                saved = false;
                              })
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('On', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textSecondary)),
                ]),
              ),
            ]),
          ),
        ];

        return PageBody(children: [
          const PageHeader(title: 'Settings', description: 'Delivery timing'),
          SectionCard(
            title: 'Delivery timing',
            description: 'For delivery workers who delay collecting an order that is ready. Times count from when the kitchen marks the food ready. '
                'Workers see these rules before they accept.',
            action: Icon(Icons.timer_outlined, size: 20, color: p.faint),
            // `space-y-5`.
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              // `grid gap-4 sm:grid-cols-3`.
              if (isSm(context))
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: fields[i])],
                ])
              else
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(fields, 16)),
              // `rounded-2xl bg-stone-50 border border-stone-100 p-4 text-sm text-stone-700 space-y-1`.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.divider)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('EXAMPLE: FOOD READY AT ${at(0).toUpperCase()}',
                        style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.faint)),
                  ),
                  if (valid) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text.rich(TextSpan(children: [strong(at(w)), const TextSpan(text: ' — the worker is reminded to collect it.')]), style: body),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text.rich(
                        TextSpan(children: [
                          strong(at(c)),
                          const TextSpan(text: ' — not collected: late pickup recorded and support is alerted. No charge is taken.'),
                        ]),
                        style: body,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: reassignOn
                          ? Text.rich(
                              TextSpan(children: [
                                strong(at(r)),
                                const TextSpan(
                                  text: ' — still not collected: the order is taken away and offered to other nearby workers '
                                      '(never back to the late one). The kitchen and customer are told.',
                                ),
                              ]),
                              style: body,
                            )
                          : Text('The order is never taken away automatically — support can still reassign it by phone.',
                              style: body.copyWith(color: p.muted)),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'The reminder must come before the pickup counts as late${reassignOn ? ', and giving it to another worker must come after that' : ''}.',
                        style: body.copyWith(fontWeight: FontWeight.w600, color: Tone.red.foreground(context)),
                      ),
                    ),
                ]),
              ),
              // `flex flex-wrap items-center gap-3`.
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (canEdit)
                  WebButton(
                    label: busy ? 'Saving…' : 'Save timing',
                    onPressed: !valid || busy
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
                if (saved)
                  Text('Saved. New pickups use these times.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tone.green.foreground(context))),
                if (timing['updated_at'] != null) Text('Last changed ${formatDate(timing['updated_at'])}', style: TextStyle(fontSize: 11, color: p.faint)),
              ]),
              // `text-[11px] text-stone-400`.
              Text(
                'Changes apply to orders that become ready after you save. A worker who takes over a late order '
                '(assigned by support or re-offered) gets this time again from when they take it.',
                style: TextStyle(fontSize: 11, height: 1.45, color: p.faint),
              ),
              Text(
                'Late pickups are never charged: a worker who delivers is always paid the full delivery fee. '
                'A worker who is too late only loses the order to another worker.',
                style: TextStyle(fontSize: 11, height: 1.45, color: p.faint),
              ),
              if (actionError != null) ErrorNote(error: actionError),
            ], 20)),
          ),
        ]);
      },
    );
  }
}
