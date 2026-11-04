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
    final viewport = MediaQuery.sizeOf(context).width;
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
            // `grid-cols-2 lg:grid-cols-4 gap-3`, one tile per status.
            return ResponsiveGrid(minWidth: 1, maxColumns: viewport >= 1024 ? 4 : 2, children: [
              for (final row in rows) StatCard(label: jstr(row['status']), value: formatRwf(row['total_rwf']), hint: '${jint(row['count'])} requests'),
              if (rows.isEmpty) const StatCard(label: 'Requests', value: '0'),
            ]);
          },
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (key, label) in const [
            ('withdrawals', 'Withdrawals'),
            ('vendor-balances', 'Vendor Balances'),
            ('driver-balances', 'Delivery Worker Balances'),
          ])
            tab == key ? WebButton(label: label, small: true, onPressed: () {}) : SmallButton(label, onPressed: () => _setTab(key)),
        ]),
        if (tab == 'withdrawals') _withdrawals() else _balances(),
      ],
    );
  }

  void _setTab(String key) {
    setState(() {
      tab = key;
      balPage = 1;
    });
    withdrawalsQuery.enabled = key == 'withdrawals';
    balancesQuery.enabled = key != 'withdrawals';
    if (key != 'withdrawals') balancesQuery.load();
  }

  Widget _withdrawals() {
    final p = Palette.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    Widget sized(Widget child) => narrow ? child : SizedBox(width: 358, child: child);
    return SectionCard(
      // Card header with only the two small selects on the right.
      action: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        sized(WebSelect<String>(
          dense: true,
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
        )),
        const SizedBox(height: 8),
        sized(WebSelect<String>(
          dense: true,
          value: status,
          options: const {'': 'All statuses', 'processing': 'processing', 'completed': 'completed', 'failed': 'failed'},
          onChanged: (value) {
            setState(() {
              status = value;
              page = 1;
            });
            withdrawalsQuery.load();
          },
        )),
      ]),
      actionFullWidth: narrow,
      child: QueryView<Json>(
        query: withdrawalsQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) return const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No withdrawal requests');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WebTable(
              columns: const [
                WebColumn('Payee'),
                WebColumn('Amount'),
                WebColumn('Pay to'),
                WebColumn('Status', nowrap: true),
                WebColumn('Reference'),
                WebColumn('Requested'),
                WebColumn('', alignEnd: true, nowrap: true),
              ],
              rows: [
                for (final w in items)
                  [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _payeeBadge(w['payee_type']),
                      const SizedBox(width: 8),
                      Flexible(child: Text(jstr(w['payee_name'], '—'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
                    ]),
                    Text(formatRwf(w['amount_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(jstr(w['method_label']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                      if (jstr(w['bank_name']).isNotEmpty)
                        Text(jstr(w['bank_name']), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted)),
                      Text(jstr(w['account_number'], 'No number on file'), style: TextStyle(fontSize: 11, color: p.faint)),
                    ]),
                    StatusBadge(jstr(w['status'])),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(jstr(w['reference'], '—'), style: TextStyle(fontSize: 12, color: p.muted)),
                      if (jstr(w['failure_reason']).isNotEmpty)
                        Text(jstr(w['failure_reason']), style: const TextStyle(fontSize: 11, color: AppColors.red600)),
                    ]),
                    Text(formatDate(w['created_at']), style: TextStyle(fontSize: 12, color: p.muted)),
                    !session.can('payouts:write')
                        ? const SizedBox.shrink()
                        : w['status'] == 'processing'
                            ? SmallButton('Pay out', primary: true, onPressed: () => _openPayout(w))
                            : SmallButton('View', onPressed: () => _openPayout(w)),
                  ],
              ],
            ),
            Pager.of(data, onPage: (next) {
              setState(() => page = next);
              withdrawalsQuery.load();
            }),
          ]);
        },
      ),
    );
  }

  Widget _balances() {
    final p = Palette.of(context);
    final driver = balanceType == 'driver';
    return SectionCard(
      title: driver ? 'Delivery Worker Balances' : 'Vendor Balances',
      description: driver ? 'Delivery fees earned and not yet withdrawn, ranked by available balance.' : 'Ranked by available balance.',
      child: QueryView<Json>(
        query: balancesQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return EmptyState(icon: Icons.account_balance_wallet_outlined, title: driver ? 'No delivery worker balances' : 'No vendor balances');
          }
          final secondary = TextStyle(fontSize: 14, color: p.textSecondary);
          final bold = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WebTable(
              columns: driver
                  ? const [WebColumn('Delivery worker'), WebColumn('Available', nowrap: true), WebColumn('Total Earned', nowrap: true), WebColumn('Deliveries', nowrap: true)]
                  : const [WebColumn('Vendor'), WebColumn('Available', nowrap: true), WebColumn('Total Sales', nowrap: true), WebColumn('Est. Commission', nowrap: true)],
              rows: [
                for (final row in items)
                  driver
                      ? [
                          CellText(jstr(row['name']), sub: [jstr(row['phone']), jstr(row['vehicle_type'])].where((s) => s.isNotEmpty).join(' · ')),
                          Text(formatRwf(row['available_balance_rwf']), style: bold),
                          Text(formatRwf(row['total_earnings_rwf']), style: secondary),
                          Text('${jint(row['completed_deliveries'])}', style: secondary),
                        ]
                      : [
                          CellText(jstr(row['name']), sub: jstr(row['neighborhood'])),
                          Text(formatRwf(row['available_balance_rwf']), style: bold),
                          Text(formatRwf(row['total_sales_rwf']), style: secondary),
                          ToneBadge(formatRwf(row['estimated_commission_rwf']), tone: Tone.violet),
                        ],
              ],
            ),
            Pager.of(data, onPage: (next) {
              setState(() => balPage = next);
              balancesQuery.load();
            }),
          ]);
        },
      ),
    );
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
