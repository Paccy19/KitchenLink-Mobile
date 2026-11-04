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

const _weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
final _digits = FilteringTextInputFormatter.digitsOnly;
final _signedDigits = FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'));

/// The owner's platform money: books, commission withdrawals to locked company
/// accounts (manual transfer confirmed by reference), adjustments, the
/// payout schedule and statement reconciliation. Super admin only.
class PlatformWalletPage extends StatefulWidget {
  const PlatformWalletPage({super.key, this.sweepAmount = 0});

  /// Pre-fills a withdrawal from the weekly sweep reminder (`?sweep=`).
  final int sweepAmount;

  @override
  State<PlatformWalletPage> createState() => _PlatformWalletPageState();
}

class _PlatformWalletPageState extends State<PlatformWalletPage> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.ownerOverview()), client: session.client);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QueryView<Json>(
      query: query,
      builder: (context, data) {
        final left = [_WithdrawCard(data: data, sweepAmount: widget.sweepAmount), _HistoryCard(withdrawals: jlist(data['withdrawals']))];
        final right = [
          _PayoutSettingsCard(settings: jmap(data['payout_settings']), sweep: jmap(data['sweep'])),
          _DestinationsCard(destinations: jlist(data['destinations'])),
        ];
        return PageBody(onRefresh: query.load, children: [
          const PageHeader(
            title: 'Platform Wallet',
            description: 'Your commission: what you can withdraw, where it goes, and whether the books match the real account.',
          ),
          _SecurityChecklist(security: jmap(data['security'])),
          _BooksCard(books: jmap(data['books'])),
          // `grid xl:grid-cols-3 gap-5`: withdrawals take two columns, settings one.
          if (MediaQuery.sizeOf(context).width >= 1280)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(left, 20))),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(right, 20))),
            ])
          else
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([...left, ...right], 20)),
          _ReconciliationCard(books: jmap(data['books']), checks: jlist(data['reconciliations'])),
        ]);
      },
    );
  }
}

/// Tailwind's `md:` breakpoint (768px and wider).
bool _isMd(BuildContext context) => MediaQuery.sizeOf(context).width >= 768;

/// `grid md:grid-cols-2 gap-3`: side by side from 768px, stacked below.
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!_isMd(context)) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(children, 12));
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: children[i]),
        const SizedBox(width: 12),
        Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(rows, 12));
  }
}

/// The website's `Button variant="secondary"`: white, bordered, `text-xs font-bold`.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
        ),
      ),
    );
  }
}

/// The method toggle in Payout settings: the active one has a brown border and tint.
class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: active ? const Color(0xFFFAF6F2) : p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? const Color(0xFF542813) : p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? const Color(0xFF3D1B0C) : p.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// A saved account: `rounded-xl border bg-stone-50 p-3`.
class _AccountBox extends StatelessWidget {
  const _AccountBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: child,
    );
  }
}

Widget _readyBadge(Json account) =>
    account['ready'] == true ? const ToneBadge('Ready', tone: Tone.green) : ToneBadge('Unlocks ${formatDate(account['activates_at'])}', tone: Tone.amber);

/// `grid md:grid-cols-5 gap-3 items-end`: four fields and the button on one
/// row from 768px, stacked below.
class _ReconciliationForm extends StatelessWidget {
  const _ReconciliationForm({required this.fields, required this.button});

  final List<Widget> fields;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    if (!_isMd(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([...fields, Align(alignment: Alignment.centerLeft, child: button)], 12));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final field in fields) ...[Expanded(child: field), const SizedBox(width: 12)],
      Expanded(child: Align(alignment: Alignment.centerLeft, child: button)),
    ]);
  }
}

class _SecurityChecklist extends StatelessWidget {
  const _SecurityChecklist({required this.security});

  final Json security;

  @override
  Widget build(BuildContext context) {
    final items = [
      (security['uses_default_password'] != true, 'Admin password changed from the default', 'Change it in Settings'),
      (security['two_factor_enabled'] == true, 'SMS codes on (sign-in and money actions)', 'Turn on in Settings'),
      (security['default_jwt_secret'] != true, 'Server secret (JWT_SECRET) set', 'Set JWT_SECRET in the backend .env'),
    ];
    if (items.every((item) => item.$1)) return const SizedBox.shrink();
    final p = Palette.of(context);
    // `space-y-2` rows: icon, `text-sm` label, then the fix as a small link.
    return SectionCard(
      title: 'Secure your account first',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
        for (final (ok, label, fix) in items)
          Row(children: [
            Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 16, color: ok ? const Color(0xFF059669) : const Color(0xFFD97706)),
            const SizedBox(width: 8),
            Flexible(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text(label, style: TextStyle(fontSize: 14, fontWeight: ok ? FontWeight.w400 : FontWeight.w600, color: ok ? p.muted : p.text)),
                if (!ok)
                  fix.startsWith('Set')
                      ? Text('· $fix', style: TextStyle(fontSize: 11, color: p.faint))
                      : InkWell(
                          onTap: () => context.read<ShellNavigator>().go(const AdminRoute(Pages.settingsProfile)),
                          child: Text('· $fix', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brown)),
                        ),
              ]),
            ),
          ]),
      ], 8)),
    );
  }
}

class _BooksCard extends StatelessWidget {
  const _BooksCard({required this.books});

  final Json books;

  @override
  Widget build(BuildContext context) {
    final balanced = books['balanced'] == true;
    return SectionCard(
      title: 'The books',
      description: "All customer money sits in the platform's account. It must equal what it is made of.",
      action: balanced ? const ToneBadge('Balanced', tone: Tone.green) : ToneBadge('Off by ${formatRwf(books['unreconciled_rwf'])}', tone: Tone.red),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        // `grid-cols-2 lg:grid-cols-5 gap-3`.
        ResponsiveGrid(minWidth: 1, maxColumns: MediaQuery.sizeOf(context).width >= 1024 ? 5 : 2, children: [
          StatCard(label: 'Cash in account', value: formatRwf(books['cash_balance_rwf']), hint: 'Should be in the real account'),
          StatCard(label: 'Held', value: formatRwf(books['held_balance_rwf']), hint: 'Orders in progress'),
          StatCard(label: 'Owed to vendors', value: formatRwf(books['vendor_payable_rwf'])),
          StatCard(label: 'Owed to delivery workers', value: formatRwf(books['driver_payable_rwf'])),
          StatCard(
            label: 'Your balance',
            value: formatRwf(books['owner_balance_rwf']),
            hint: 'Commission earned ${formatRwf(books['total_commission_rwf'])}',
          ),
        ]),
        if (!balanced)
          Note(
            '${formatRwf(books['unreconciled_rwf'])} is unaccounted for, so withdrawals are blocked. If the money was lost '
            '(e.g. paid out twice before the books were fixed), record an adjustment with the reason.',
            icon: Icons.warning_amber_rounded,
            action: BusyButton(
              label: 'Record adjustment',
              danger: true,
              onPressed: () => showAppSheet(context, _AdjustmentSheet(suggested: jint(books['unreconciled_rwf']))),
            ),
          ),
      ])),
    );
  }
}

class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet({required this.suggested});

  final int suggested;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> with BusyState {
  late final amount = TextEditingController(text: widget.suggested == 0 ? '' : '${widget.suggested}');
  final reason = TextEditingController();
  String code = '';

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final value = int.tryParse(amount.text) ?? 0;
    return SheetScaffold(
      title: 'Record adjustment',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Record adjustment',
          busy: busy,
          onPressed: code.length != 6 || reason.text.trim().length < 5 || value == 0
              ? null
              : () async {
                  final ok = await run(() => api.ownerAdjustment({'amount_rwf': value, 'reason': reason.text, 'otp_code': code}));
                  if (ok && context.mounted) Navigator.pop(context);
                },
        ),
      ],
      children: [
        const Text('A negative amount reduces your balance (a write-off). It is recorded permanently on the ledger and in the audit log.'),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          inputFormatters: [_signedDigits],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Amount (RWF)'),
        ),
        TextField(
          controller: reason,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Reason (at least 5 characters)', hintText: 'e.g. Delivery fee paid twice on order OFK-…668BD3'),
        ),
        ActionCodeField(purpose: 'adjustment', onChanged: (value) => setState(() => code = value)),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

class _WithdrawCard extends StatefulWidget {
  const _WithdrawCard({required this.data, required this.sweepAmount});

  final Json data;
  final int sweepAmount;

  @override
  State<_WithdrawCard> createState() => _WithdrawCardState();
}

class _WithdrawCardState extends State<_WithdrawCard> with BusyState {
  late final w = jmap(widget.data['withdrawable']);
  late final amount = TextEditingController(
    text: widget.sweepAmount > 0 ? '${widget.sweepAmount < jint(w['max_now_rwf']) ? widget.sweepAmount : jint(w['max_now_rwf'])}' : '',
  );
  String destinationId = '';
  String code = '';
  int codeKey = 0;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = jmap(widget.data['withdrawable']);
    final blockers = jlist(widget.data['blockers']);
    final ready = jlist(widget.data['destinations']).where((d) => d['ready'] == true).toList();
    final processing = jlist(widget.data['withdrawals']).where((e) => e['status'] == 'processing').firstOrNull;
    if (destinationId.isEmpty && ready.isNotEmpty) destinationId = jstr(ready.first['id']);
    final maxNow = jint(w['max_now_rwf']);
    final numeric = int.tryParse(amount.text);
    final invalid = numeric == null || numeric <= 0 || numeric > maxNow;
    final api = context.read<AdminSession>().api;

    return SectionCard(
      title: 'Withdraw commission',
      description: 'Requested here, transferred by you, then confirmed with the transfer reference.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        ResponsiveGrid(minWidth: 1, maxColumns: 2, children: [
          StatCard(
            label: 'Available',
            value: formatRwf(w['available_rwf']),
            hint: 'After ${jstr(w['reserve_percent'], '0')}% reserve (${formatRwf(w['reserve_rwf'])})',
            tone: Tone.green,
          ),
          StatCard(label: 'Max now', value: formatRwf(maxNow), hint: 'Per withdrawal ≤ ${formatRwf(w['max_per_withdrawal_rwf'])}'),
          StatCard(label: 'This week', value: formatRwf(w['withdrawn_this_week_rwf']), hint: 'Weekly limit ${formatRwf(w['max_weekly_rwf'])}'),
          StatCard(label: 'In progress', value: formatRwf(w['processing_rwf'])),
        ]),
        if (widget.sweepAmount > 0 && processing == null)
          Note('Weekly sweep: ${formatRwf(widget.sweepAmount)} was ready. The amount is pre-filled below.', tone: Tone.violet, icon: Icons.event_repeat),
        if (processing != null)
          _ProcessingWithdrawal(withdrawal: processing)
        else if (blockers.isNotEmpty)
          // `space-y-1.5 text-sm text-amber-700`, a lock before each reason.
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
            for (final blocker in blockers)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline, size: 16, color: Color(0xFFB45309))),
                const SizedBox(width: 8),
                Expanded(child: Text(jstr(blocker['message']), style: const TextStyle(fontSize: 14, color: Color(0xFFB45309)))),
              ]),
          ], 6))
        else ...[
          // `grid md:grid-cols-2 gap-3`; the code field spans both columns.
          _TwoColumns(children: [
            WebField(
              label: 'Amount (RWF)',
              hint: amount.text.isNotEmpty && invalid
                  ? Text('Enter a whole amount up to ${formatRwf(maxNow)}.', style: const TextStyle(color: AppColors.red600))
                  : null,
              child: Row(children: [
                Expanded(
                  child: WebInput(controller: amount, hint: '0', keyboardType: TextInputType.number, inputFormatters: [_digits], onChanged: (_) => setState(() {})),
                ),
                const SizedBox(width: 8),
                _SecondaryButton(label: 'Max', onPressed: () => setState(() => amount.text = '$maxNow')),
              ]),
            ),
            WebField(
              label: 'To company account',
              child: WebSelect<String>(
                value: destinationId,
                options: {
                  for (final d in ready) jstr(d['id']): '${jstr(d['label'])} · ${jstr(d['provider'])} ${jstr(d['account_number'])}',
                },
                onChanged: (value) => setState(() => destinationId = value),
              ),
            ),
          ]),
          ActionCodeField(key: ValueKey(codeKey), purpose: 'platform_withdrawal', onChanged: (value) => setState(() => code = value)),
          Align(
            alignment: Alignment.centerLeft,
            child: WebButton(
              large: true,
              label: busy ? 'Requesting…' : 'Request withdrawal${(numeric ?? 0) > 0 ? ' of ${formatRwf(numeric)}' : ''}',
              onPressed: busy || invalid || code.length != 6 || destinationId.isEmpty
                  ? null
                  : () async {
                      final ok = await run(() => api.ownerWithdraw({
                            'amount_rwf': numeric,
                            'destination_id': destinationId,
                            'otp_code': code,
                            'source': widget.sweepAmount > 0 ? 'weekly_sweep' : 'manual',
                          }));
                      if (ok && mounted) {
                        setState(() {
                          amount.clear();
                          code = '';
                          codeKey++;
                        });
                      }
                    },
            ),
          ),
          if (actionError != null) ErrorNote(error: actionError),
        ],
      ])),
    );
  }
}

class _ProcessingWithdrawal extends StatefulWidget {
  const _ProcessingWithdrawal({required this.withdrawal});

  final Json withdrawal;

  @override
  State<_ProcessingWithdrawal> createState() => _ProcessingWithdrawalState();
}

class _ProcessingWithdrawalState extends State<_ProcessingWithdrawal> with BusyState {
  final reference = TextEditingController();
  final reason = TextEditingController();

  @override
  void dispose() {
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final w = widget.withdrawal;
    final d = jmap(w['destination']);
    final id = jstr(w['id']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tone.amber.background(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tone.amber.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        Text.rich(TextSpan(children: [
          TextSpan(text: w['source'] == 'auto' ? 'Automatic withdrawal: ' : 'Step 2: ', style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: 'transfer '),
          TextSpan(text: formatRwf(w['amount_rwf']), style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: ' to '),
          TextSpan(text: jstr(d['label']), style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' (${jstr(d['provider'])} · ${jstr(d['account_name'])} · ${jstr(d['account_number'])}) from the platform account, then confirm it here.'),
        ])),
        WebField(
          label: 'Transfer reference',
          child: WebInput(controller: reference, hint: 'Bank / MoMo transaction ID', onChanged: (_) => setState(() {})),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: WebButton(
            label: 'I transferred it: confirm',
            onPressed: busy || reference.text.trim().length < 3 ? null : () => run(() => api.ownerCompleteWithdrawal(id, {'reference': reference.text})),
          ),
        ),
        WebField(label: 'Or cancel (reason)', child: WebInput(controller: reason, hint: 'e.g. Bank closed')),
        Align(
          alignment: Alignment.centerLeft,
          child: _SecondaryButton(label: 'Cancel withdrawal', onPressed: busy ? null : () => run(() => api.ownerCancelWithdrawal(id, {'reason': reason.text}))),
        ),
        if (actionError != null) ErrorNote(error: actionError),
      ], 10)),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.withdrawals});

  final List<Json> withdrawals;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SectionCard(
      title: 'Withdrawal history',
      padding: EdgeInsets.zero,
      child: withdrawals.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No withdrawals yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.faint)),
            )
          : WebTable(
              columns: const [
                WebColumn('Amount', nowrap: true),
                WebColumn('To'),
                WebColumn('Status', nowrap: true),
                WebColumn('Reference'),
                WebColumn('Requested'),
              ],
              rows: [
                for (final w in withdrawals)
                  [
                    Text(formatRwf(w['amount_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                    Text('${jstr(jmap(w['destination'])['label'])} · ${jstr(jmap(w['destination'])['account_number'])}',
                        style: TextStyle(fontSize: 12, color: p.textSecondary)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      StatusBadge(jstr(w['status'])),
                      if (w['source'] == 'weekly_sweep') ...[const SizedBox(width: 4), const ToneBadge('Sweep', tone: Tone.violet)],
                      if (w['source'] == 'auto') ...[const SizedBox(width: 4), const ToneBadge('Automatic', tone: Tone.violet)],
                    ]),
                    Text(jstr(w['reference'], jstr(w['failure_reason'], '—')), style: TextStyle(fontSize: 12, color: p.muted)),
                    Text(formatDate(w['created_at']), style: TextStyle(fontSize: 12, color: p.muted)),
                  ],
              ],
            ),
    );
  }
}

class _DestinationsCard extends StatelessWidget {
  const _DestinationsCard({required this.destinations});

  final List<Json> destinations;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SectionCard(
      title: 'Company payout accounts',
      description: 'Withdrawals can only go to these. New accounts unlock after a waiting period.',
      action: WebButton(small: true, icon: Icons.add, label: 'Add', onPressed: () => showAppSheet(context, const _AddDestinationSheet())),
      child: destinations.isEmpty
          ? Text("No payout account yet. Add the company's bank account.", style: TextStyle(fontSize: 14, color: p.faint))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              for (final d in destinations)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.account_balance_outlined, size: 16, color: p.faint)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(jstr(d['label']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                        Text('${jstr(d['provider'])} · ${jstr(d['account_name'])} · ${jstr(d['account_number'])}', style: TextStyle(fontSize: 11, color: p.muted)),
                        const SizedBox(height: 6),
                        _readyBadge(d),
                      ]),
                    ),
                    SmallButton('Remove', ghost: true, onPressed: () => showAppSheet(context, _RemoveDestinationSheet(destination: d))),
                  ]),
                ),
            ], 8)),
    );
  }
}

class _AddDestinationSheet extends StatefulWidget {
  const _AddDestinationSheet();

  @override
  State<_AddDestinationSheet> createState() => _AddDestinationSheetState();
}

class _AddDestinationSheetState extends State<_AddDestinationSheet> with BusyState {
  String type = 'bank';
  final label = TextEditingController();
  final provider = TextEditingController();
  final accountName = TextEditingController();
  final accountNumber = TextEditingController();
  String code = '';

  @override
  void dispose() {
    for (final c in [label, provider, accountName, accountNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final isBank = type == 'bank';
    final numberInvalid = !isBank && accountNumber.text.isNotEmpty && !isValidRwandaPhone(accountNumber.text);
    final complete = [label, provider, accountName, accountNumber].every((c) => c.text.isNotEmpty) && !numberInvalid && code.length == 6;
    return SheetScaffold(
      title: 'Add company payout account',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Add account',
          busyLabel: 'Adding…',
          busy: busy,
          onPressed: !complete
              ? null
              : () async {
                  final ok = await run(() => api.ownerAddDestination({
                        'type': type,
                        'label': label.text,
                        'provider': provider.text,
                        'account_name': accountName.text,
                        'account_number': accountNumber.text,
                        'otp_code': code,
                      }));
                  if (ok && context.mounted) Navigator.pop(context);
                },
        ),
      ],
      children: [
        const Text('Use a company account, not a personal one. For your security it can receive withdrawals only after the waiting period, and you get an SMS alert.'),
        Dropdown<String>(
          label: 'Type',
          value: type,
          options: const {'bank': 'Bank account', 'mobile_money': 'Business mobile money'},
          onChanged: (value) => setState(() {
            type = value;
            accountNumber.clear();
          }),
        ),
        TextField(controller: label, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name for this account', hintText: 'e.g. Company BK account')),
        TextField(
          controller: provider,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: isBank ? 'Bank' : 'Network', hintText: isBank ? 'e.g. Bank of Kigali' : 'e.g. MTN Mobile Money'),
        ),
        TextField(controller: accountName, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Account holder name', hintText: 'e.g. KitchenLink Ltd')),
        TextField(
          controller: accountNumber,
          keyboardType: isBank ? TextInputType.number : TextInputType.phone,
          onChanged: (_) => setState(() {}),
          inputFormatters: isBank
              ? [_digits, LengthLimitingTextInputFormatter(20)]
              : [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizePhoneInput(next.text)))],
          decoration: InputDecoration(
            labelText: isBank ? 'Account number' : 'Phone number',
            hintText: isBank ? 'Digits only' : phonePlaceholder,
            errorText: numberInvalid ? phoneError : null,
            errorMaxLines: 2,
          ),
        ),
        ActionCodeField(purpose: 'payout_destination', onChanged: (value) => setState(() => code = value)),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

class _RemoveDestinationSheet extends StatefulWidget {
  const _RemoveDestinationSheet({required this.destination});

  final Json destination;

  @override
  State<_RemoveDestinationSheet> createState() => _RemoveDestinationSheetState();
}

class _RemoveDestinationSheetState extends State<_RemoveDestinationSheet> with BusyState {
  String code = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return SheetScaffold(
      title: 'Remove ${jstr(widget.destination['label'], 'account')}',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it')),
        BusyButton(
          label: 'Remove',
          danger: true,
          busy: busy,
          onPressed: code.length != 6
              ? null
              : () async {
                  final ok = await run(() => api.ownerRemoveDestination(jstr(widget.destination['id']), {'otp_code': code}));
                  if (ok && context.mounted) Navigator.pop(context);
                },
        ),
      ],
      children: [
        const Text('Withdrawals can no longer go to this account. Adding it back starts a new waiting period.'),
        ActionCodeField(purpose: 'remove_destination', onChanged: (value) => setState(() => code = value)),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

/// Where your commission goes (a bank account or a mobile money number) and
/// when it is withdrawn. Saved with an SMS code; the system remembers it.
class _PayoutSettingsCard extends StatefulWidget {
  const _PayoutSettingsCard({required this.settings, required this.sweep});

  final Json settings;
  final Json sweep;

  @override
  State<_PayoutSettingsCard> createState() => _PayoutSettingsCardState();
}

class _PayoutSettingsCardState extends State<_PayoutSettingsCard> with BusyState {
  late Json form = _formFrom(widget.settings);
  String code = '';
  int codeKey = 0;
  String message = '';

  static Json _formFrom(Json settings) {
    final account = settings['account'] is Map ? jmap(settings['account']) : null;
    final isPhone = settings['method'] == 'mobile_money';
    final schedule = jmap(settings['schedule']);
    return {
      'method': jstr(settings['method'], 'bank'),
      'bank_name': !isPhone && account != null ? jstr(account['provider']) : '',
      'network': isPhone && account != null ? jstr(account['provider'], 'MTN Mobile Money') : 'MTN Mobile Money',
      'account_name': jstr(account?['account_name']),
      'account_number': !isPhone && account != null ? jstr(account['account_number']) : '',
      'phone': isPhone && account != null ? jstr(account['account_number']) : '',
      'schedule': {
        'mode': jstr(schedule['mode'], 'reminder'),
        'frequency': jstr(schedule['frequency'], 'weekly'),
        'weekday': jint(schedule['weekday'], 5),
        'day_of_month': jint(schedule['day_of_month'], 1),
        'hour': jint(schedule['hour'], 9),
        'amount_mode': jstr(schedule['amount_mode'], 'all_available'),
        'fixed_amount_rwf': jint(schedule['fixed_amount_rwf']) == 0 ? '' : '${jint(schedule['fixed_amount_rwf'])}',
      },
    };
  }

  // Re-sync when the saved settings change (after a save or a reload).
  @override
  void didUpdateWidget(covariant _PayoutSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(_formFrom(oldWidget.settings)) != _signature(_formFrom(widget.settings))) form = _formFrom(widget.settings);
  }

  String _signature(Json value) => value.toString();

  Json get schedule => jmap(form['schedule']);

  void set(String key, dynamic value) => setState(() => form = {...form, key: value});
  void setSchedule(String key, dynamic value) => setState(() => form = {...form, 'schedule': {...schedule, key: value}});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final saved = _formFrom(widget.settings);
    final dirty = _signature(form) != _signature(saved);
    final isBank = form['method'] == 'bank';
    final account = widget.settings['account'] is Map ? jmap(widget.settings['account']) : null;
    final provider = jmap(widget.settings['provider']);
    final mode = jstr(schedule['mode']);
    final accountComplete = isBank
        ? jstr(form['bank_name']).trim().isNotEmpty && jstr(form['account_name']).trim().isNotEmpty && RegExp(r'^[\d\s-]{6,}$').hasMatch(jstr(form['account_number']))
        : jstr(form['account_name']).trim().isNotEmpty && isValidRwandaPhone(jstr(form['phone']));

    final p = Palette.of(context);
    Widget text(String key, String label, {String? hint, TextInputType? keyboard, List<TextInputFormatter>? formatters, String? error}) => WebField(
          label: label,
          hint: error == null ? null : Text(error, style: const TextStyle(color: AppColors.red600)),
          child: WebInput(
            // Rebuilt from the form only when the saved settings change.
            key: ValueKey('$key-${_signature(saved)}'),
            initialValue: jstr(form[key]),
            hint: hint,
            keyboardType: keyboard,
            inputFormatters: formatters,
            onChanged: (value) => set(key, value),
          ),
        );
    Widget select<T>(String label, T value, Map<T, String> options, ValueChanged<T> onChanged) =>
        WebField(label: label, child: WebSelect<T>(value: value, options: options, onChanged: onChanged));

    return SectionCard(
      title: 'Payout settings',
      description: 'Where your commission goes and when it is withdrawn.',
      action: dirty
          ? const ToneBadge('Unsaved changes', tone: Tone.amber)
          : widget.settings['method'] != null
              ? const ToneBadge('Saved', tone: Tone.green)
              : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        if (account != null)
          _AccountBox(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${jstr(account['provider'])} · ${jstr(account['account_number'])}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
                  Text(jstr(account['account_name']), style: TextStyle(fontSize: 11, color: p.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              _readyBadge(account),
            ]),
          ),
        Row(children: [
          Expanded(child: _MethodButton(label: 'Bank account', active: isBank, onTap: () => set('method', 'bank'))),
          const SizedBox(width: 8),
          Expanded(child: _MethodButton(label: 'Phone (MoMo)', active: !isBank, onTap: () => set('method', 'mobile_money'))),
        ]),
        if (isBank) ...[
          text('bank_name', 'Bank', hint: 'e.g. Bank of Kigali'),
          text('account_name', 'Account holder name', hint: 'e.g. KitchenLink Ltd'),
          text('account_number', 'Bank account number', hint: 'Digits only', keyboard: TextInputType.number, formatters: [_digits, LengthLimitingTextInputFormatter(20)]),
        ] else ...[
          select<String>('Network', jstr(form['network']), const {'MTN Mobile Money': 'MTN Mobile Money', 'Airtel Money': 'Airtel Money'}, (value) => set('network', value)),
          text('account_name', 'Registered name', hint: 'Name on the MoMo account'),
          text(
            'phone',
            'Phone number',
            hint: phonePlaceholder,
            keyboard: TextInputType.phone,
            formatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizePhoneInput(next.text)))],
            error: jstr(form['phone']).isNotEmpty && !isValidRwandaPhone(jstr(form['phone'])) ? phoneError : null,
          ),
        ],
        select<String>('Withdraw', mode, const {'auto': 'Automatically, on schedule', 'reminder': 'Remind me only', 'off': 'Off'}, (value) => setSchedule('mode', value)),
        if (mode != 'off') ...[
          select<String>('How often', jstr(schedule['frequency']), const {'weekly': 'Every week', 'monthly': 'Every month'}, (value) => setSchedule('frequency', value)),
          if (schedule['frequency'] == 'weekly')
            select<int>('Day', jint(schedule['weekday']), {for (var i = 0; i < 7; i++) i: _weekdays[i]}, (value) => setSchedule('weekday', value))
          else
            select<int>('Day of month', jint(schedule['day_of_month']), {for (var i = 1; i <= 28; i++) i: '$i'}, (value) => setSchedule('day_of_month', value)),
          select<int>('Time (Kigali)', jint(schedule['hour']), {for (var h = 0; h < 24; h++) h: '${h.toString().padLeft(2, '0')}:00'}, (value) => setSchedule('hour', value)),
          if (mode == 'auto') ...[
            select<String>('Amount', jstr(schedule['amount_mode']), const {'all_available': 'Everything available', 'fixed': 'A fixed amount'},
                (value) => setSchedule('amount_mode', value)),
            if (schedule['amount_mode'] == 'fixed')
              WebField(
                label: 'Fixed amount (RWF)',
                child: WebInput(
                  initialValue: jstr(schedule['fixed_amount_rwf']),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_digits],
                  onChanged: (value) => setSchedule('fixed_amount_rwf', value),
                ),
              ),
            Text(
              provider['automatic'] == true
                  ? 'Withdrawals are sent automatically by ${jstr(provider['label'])}.'
                  : 'No payout service is connected yet: on schedule the system creates the withdrawal and texts you to transfer it and confirm with '
                      'the reference. Once a payout service is connected, the money moves by itself.',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          ],
        ],
        ActionCodeField(key: ValueKey(codeKey), purpose: 'payout_settings', onChanged: (value) => setState(() => code = value)),
        Align(
          alignment: Alignment.centerLeft,
          child: WebButton(
            label: busy ? 'Saving…' : 'Save changes',
            onPressed: busy || !accountComplete || code.length != 6
                ? null
                : () async {
                    setState(() => message = '');
                    dynamic result;
                    final ok = await run(() async => result = await api.ownerSavePayoutSettings({
                          ...form,
                          'schedule': {...schedule, 'fixed_amount_rwf': int.tryParse(jstr(schedule['fixed_amount_rwf'])) ?? 0},
                          'otp_code': code,
                        }));
                    if (ok && mounted) {
                      setState(() {
                        code = '';
                        codeKey++;
                        message = jmap(result)['account_changed'] == true
                            ? 'Saved. Your new payout account unlocks after the waiting period. You will get an SMS.'
                            : 'Saved.';
                      });
                    }
                  },
          ),
        ),
        if (actionError != null) ErrorNote(error: actionError),
        if (message.isNotEmpty) Text(message, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF047857))),
        if (widget.sweep['last_at'] != null)
          Text(
            'Last scheduled run ${formatDate(widget.sweep['last_at'])}${jint(widget.sweep['last_amount_rwf']) > 0 ? ' · ${formatRwf(widget.sweep['last_amount_rwf'])}' : ''}',
            style: TextStyle(fontSize: 11, color: p.faint),
          ),
      ], 12)),
    );
  }
}

class _ReconciliationCard extends StatefulWidget {
  const _ReconciliationCard({required this.books, required this.checks});

  final Json books;
  final List<Json> checks;

  @override
  State<_ReconciliationCard> createState() => _ReconciliationCardState();
}

class _ReconciliationCardState extends State<_ReconciliationCard> with BusyState {
  final accountLabel = TextEditingController(text: 'Platform collection account');
  String statementDate = isoDay(DateTime.now());
  final balance = TextEditingController();
  final note = TextEditingController();

  @override
  void dispose() {
    accountLabel.dispose();
    balance.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final p = Palette.of(context);
    final value = int.tryParse(balance.text);
    return SectionCard(
      title: 'Monthly reconciliation',
      description: 'Compare the real bank / MoMo statement with the ${formatRwf(widget.books['cash_balance_rwf'])} the books say should be there.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        _ReconciliationForm(fields: [
          WebField(label: 'Account', child: WebInput(controller: accountLabel)),
          WebField(label: 'Statement date', child: WebDateInput(value: statementDate, onChanged: (v) => setState(() => statementDate = v))),
          WebField(
            label: 'Statement balance (RWF)',
            child: WebInput(
              controller: balance,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [_signedDigits],
              onChanged: (_) => setState(() {}),
            ),
          ),
          WebField(label: 'Note', child: WebInput(controller: note, hint: 'optional')),
        ], button: WebButton(
          label: busy ? 'Checking…' : 'Check',
          icon: Icons.balance,
          onPressed: busy || value == null
              ? null
              : () async {
                  final ok = await run(() => api.ownerReconciliation({
                        'account_label': accountLabel.text,
                        'statement_date': statementDate,
                        'statement_balance_rwf': value,
                        'note': note.text,
                      }));
                  if (ok && mounted) {
                    setState(() {
                      balance.clear();
                      note.clear();
                    });
                  }
                },
        )),
        if (actionError != null) ErrorNote(error: actionError),
        if (widget.checks.isNotEmpty)
          WebTable(
            columns: const [
              WebColumn('Statement', nowrap: true),
              WebColumn('Account'),
              WebColumn('Statement balance', nowrap: true),
              WebColumn('Books', nowrap: true),
              WebColumn('Result', nowrap: true),
            ],
            rows: [
              for (final check in widget.checks)
                [
                  Text(formatDate(check['statement_date'], withTime: false), style: TextStyle(fontSize: 12, color: p.muted)),
                  Text(jstr(check['account_label']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                  Text(formatRwf(check['statement_balance_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                  Text(formatRwf(check['system_cash_rwf']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                  check['matches'] == true
                      ? const ToneBadge('Matches', tone: Tone.green)
                      : ToneBadge('${jnum(check['difference_rwf']) > 0 ? '+' : ''}${formatRwf(check['difference_rwf'])}', tone: Tone.red),
                ],
            ],
          ),
      ])),
    );
  }
}
