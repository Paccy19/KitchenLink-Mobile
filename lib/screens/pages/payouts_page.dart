import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/action_code_field.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Widget _payeeBadge(dynamic type) =>
    type == 'driver' ? const ToneBadge('Delivery worker', tone: Tone.green) : const ToneBadge('Vendor', tone: Tone.violet);

/// Pay vendor and delivery worker withdrawal requests, and review their balances.
class PayoutsPage extends StatefulWidget {
  const PayoutsPage({super.key, this.focusId});

  final String? focusId;

  @override
  State<PayoutsPage> createState() => _PayoutsPageState();
}

class _PayoutsPageState extends State<PayoutsPage> {
  late final session = context.read<AdminSession>();
  String tab = 'withdrawals';
  String status = '';
  String payeeType = '';
  int page = 1;
  int balPage = 1;

  String get balanceType => tab == 'driver-balances' ? 'driver' : 'vendor';

  late final withdrawalsQuery = Query<Json>(
    () async => jmap(await session.api.listPayouts({'status': status, 'payee_type': payeeType, 'page': page, 'limit': 20})),
    client: session.client,
  );
  late final balancesQuery = Query<Json>(
    () async => jmap(await session.api.payoutBalances({
      'page': balPage,
      'limit': 20,
      'sort': 'balance',
      if (balanceType == 'driver') 'payee_type': 'driver',
    })),
    client: session.client,
    enabled: false,
  );
  late final summaryQuery = Query<Json>(
    () async => jmap(await session.api.payoutSummary(payeeType.isEmpty ? null : {'payee_type': payeeType})),
    client: session.client,
  );

  @override
  void initState() {
    super.initState();
    final focus = widget.focusId;
    if (focus != null) {
      session.api.listPayouts({'limit': 100}).then((result) {
        final found = jlist(jmap(result)['items']).where((w) => jstr(w['id']) == focus).firstOrNull;
        if (found != null && mounted) _openPayout(found);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    withdrawalsQuery.dispose();
    balancesQuery.dispose();
    summaryQuery.dispose();
    super.dispose();
  }

  void _openPayout(Json withdrawal) => showAppSheet(context, _PayoutSheet(withdrawal: withdrawal));

  @override
  Widget build(BuildContext context) {
    return PageBody(
      onRefresh: () async {
        await Future.wait([
          tab == 'withdrawals' ? withdrawalsQuery.load() : balancesQuery.load(),
          summaryQuery.load(silent: true),
        ]);
      },
      children: [
        const PageHeader(title: 'Payouts', description: 'Pay vendor and delivery worker withdrawal requests, and review their balances.'),
        ListenableBuilder(
          listenable: summaryQuery,
          builder: (context, _) {
            final rows = jlist(summaryQuery.data?['by_status']);
            if (summaryQuery.data == null) return const SizedBox.shrink();
            return ResponsiveGrid(children: [
              for (final row in rows) StatCard(label: jstr(row['status']), value: formatRwf(row['total_rwf']), hint: '${jint(row['count'])} requests'),
              if (rows.isEmpty) const StatCard(label: 'Requests', value: '0'),
            ]);
          },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'withdrawals', label: Text('Withdrawals')),
              ButtonSegment(value: 'vendor-balances', label: Text('Vendor Balances')),
              ButtonSegment(value: 'driver-balances', label: Text('Worker Balances')),
            ],
            selected: {tab},
            onSelectionChanged: (value) {
              setState(() {
                tab = value.first;
                balPage = 1;
              });
              withdrawalsQuery.enabled = tab == 'withdrawals';
              balancesQuery.enabled = tab != 'withdrawals';
              if (tab != 'withdrawals') balancesQuery.load();
            },
          ),
        ),
        if (tab == 'withdrawals') _withdrawals() else _balances(),
      ],
    );
  }

  Widget _withdrawals() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
      Row(children: [
        Expanded(
          child: Dropdown<String>(
            value: payeeType,
            options: const {'': 'Vendors & delivery workers', 'vendor': 'Vendors', 'driver': 'Delivery workers'},
            onChanged: (value) {
              setState(() {
                payeeType = value;
                page = 1;
              });
              withdrawalsQuery.load();
              summaryQuery.load(silent: true);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Dropdown<String>(
            value: status,
            options: const {'': 'All statuses', 'processing': 'processing', 'completed': 'completed', 'failed': 'failed'},
            onChanged: (value) {
              setState(() {
                status = value;
                page = 1;
              });
              withdrawalsQuery.load();
            },
          ),
        ),
      ]),
      QueryView<Json>(
        query: withdrawalsQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) return const Card(child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No withdrawal requests'));
          return RecordList(
            footer: Pager.of(data, onPage: (next) {
              setState(() => page = next);
              withdrawalsQuery.load();
            }),
            children: [
              for (final w in items)
                RecordTile(
                  title: jstr(w['payee_name'], '—'),
                  trailing: formatRwf(w['amount_rwf']),
                  badges: [_payeeBadge(w['payee_type']), StatusBadge(jstr(w['status']))],
                  lines: [
                    [jstr(w['method_label']), jstr(w['bank_name']), jstr(w['account_number'], 'No number on file')].where((s) => s.isNotEmpty).join(' · '),
                    'Ref ${jstr(w['reference'], '—')}${jstr(w['failure_reason']).isNotEmpty ? ' · ${jstr(w['failure_reason'])}' : ''}',
                    'Requested ${formatDate(w['created_at'])}',
                  ],
                  actions: [
                    if (session.can('payouts:write'))
                      w['status'] == 'processing'
                          ? FilledButton(onPressed: () => _openPayout(w), child: const Text('Pay out'))
                          : OutlinedButton(onPressed: () => _openPayout(w), child: const Text('View')),
                  ],
                ),
            ],
          );
        },
      ),
    ]));
  }

  Widget _balances() {
    final driver = balanceType == 'driver';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
      Hint(driver ? 'Delivery fees earned and not yet withdrawn, ranked by available balance.' : 'Ranked by available balance.'),
      QueryView<Json>(
        query: balancesQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return Card(child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: driver ? 'No delivery worker balances' : 'No vendor balances'));
          }
          return RecordList(
            footer: Pager.of(data, onPage: (next) {
              setState(() => balPage = next);
              balancesQuery.load();
            }),
            children: [
              for (final row in items)
                driver
                    ? RecordTile(
                        title: jstr(row['name']),
                        subtitle: [jstr(row['phone']), jstr(row['vehicle_type'])].where((s) => s.isNotEmpty).join(' · '),
                        trailing: formatRwf(row['available_balance_rwf']),
                        lines: ['Total earned ${formatRwf(row['total_earnings_rwf'])} · ${jint(row['completed_deliveries'])} deliveries'],
                      )
                    : RecordTile(
                        title: jstr(row['name']),
                        subtitle: jstr(row['neighborhood']),
                        trailing: formatRwf(row['available_balance_rwf']),
                        badges: [ToneBadge('Est. commission ${formatRwf(row['estimated_commission_rwf'])}', tone: Tone.violet)],
                        lines: ['Total sales ${formatRwf(row['total_sales_rwf'])}'],
                      ),
            ],
          );
        },
      ),
    ]));
  }
}

/// Paying one withdrawal: mark it paid with the transfer reference (large
/// payouts also need an SMS code), or failed so the money returns to the
/// payee's balance. Finalized payouts can only have their reference corrected.
class _PayoutSheet extends StatefulWidget {
  const _PayoutSheet({required this.withdrawal});

  final Json withdrawal;

  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> with BusyState {
  late final session = context.read<AdminSession>();
  late final isProcessing = widget.withdrawal['status'] == 'processing';
  late String status = isProcessing ? 'completed' : jstr(widget.withdrawal['status']);
  late final reference = TextEditingController(text: isProcessing ? '' : jstr(widget.withdrawal['reference']));
  final reason = TextEditingController();
  String actionCode = '';

  @override
  void dispose() {
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  // Large payouts need an SMS code (the server enforces it too).
  bool get needsCode => isProcessing && status == 'completed' && jint(widget.withdrawal['amount_rwf']) >= session.largeMoneyActionRwf;

  bool get saveDisabled =>
      (needsCode && actionCode.length != 6) || (isProcessing && status == 'completed' && reference.text.trim().isEmpty);

  Future<void> save() async {
    final ok = await run(() => session.api.updatePayout(jstr(widget.withdrawal['id']), {
          'status': status,
          'reference': reference.text,
          if (actionCode.isNotEmpty) 'action_code': actionCode,
          if (status == 'failed') 'reason': reason.text,
        }));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.withdrawal;
    return SheetScaffold(
      title: '${isProcessing ? 'Pay out' : 'Payout'} · ${jstr(w['payee_name'])}',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(isProcessing ? 'Cancel' : 'Close')),
        BusyButton(
          label: !isProcessing
              ? 'Save reference'
              : status == 'completed'
                  ? 'Mark as paid'
                  : 'Mark as failed & refund',
          busy: busy,
          onPressed: saveDisabled ? null : save,
        ),
      ],
      children: [
        InfoTile('', '', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
          Row(children: [_payeeBadge(w['payee_type']), const SizedBox(width: 8), Expanded(child: Text(jstr(w['payee_name']), style: const TextStyle(fontWeight: FontWeight.w800)))]),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Send '),
            TextSpan(text: formatRwf(w['amount_rwf']), style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' via '),
            TextSpan(text: jstr(w['method_label']), style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' to '),
            if (jstr(w['bank_name']).isNotEmpty) TextSpan(text: '${jstr(w['bank_name'])} account ', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: jstr(w['account_number'], 'their saved payout details'), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (jstr(w['account_name']).isNotEmpty) TextSpan(text: ' (${jstr(w['account_name'])})'),
          ])),
          Hint('Requested ${formatDate(w['created_at'])}'),
        ], 6))),
        if (isProcessing)
          Dropdown<String>(
            label: 'Outcome',
            value: status,
            options: const {'completed': 'Paid: I sent the money', 'failed': 'Failed: return the money to their balance'},
            onChanged: (value) => setState(() => status = value),
          )
        else
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Status:'),
            StatusBadge(jstr(w['status'])),
            const Hint("Finalized payouts can't change status. You can still correct the reference."),
          ]),
        if (status == 'completed' || !isProcessing)
          TextField(
            controller: reference,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Transaction reference (required)', hintText: 'e.g. MoMo / Airtel transaction ID'),
          ),
        if (needsCode)
          ActionCodeField(
            purpose: 'large_payment',
            onChanged: (value) => setState(() => actionCode = value),
            label: 'Large payout: code sent to your phone (${formatRwf(session.largeMoneyActionRwf)} or more)',
          ),
        if (isProcessing && status == 'failed')
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason (shown to the payee)', hintText: 'e.g. Number not registered for mobile money'),
          ),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
