import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _statusTone = {'pending': Tone.amber, 'completed': Tone.green, 'failed': Tone.red};
const _statusLabel = {'pending': 'To send', 'completed': 'Sent', 'failed': 'Failed'};
const _cancelledBy = {'customer': 'Customer', 'vendor': 'Kitchen', 'admin': 'Support', 'system': 'System'};

/// Refunds owed to customers for cancelled paid orders. With a manual payout
/// service the team sends the money back and records the transaction id.
class RefundsPage extends StatefulWidget {
  const RefundsPage({super.key, this.focusId});

  final String? focusId;

  @override
  State<RefundsPage> createState() => _RefundsPageState();
}

class _RefundsPageState extends State<RefundsPage> {
  late final session = context.read<AdminSession>();
  String status = 'pending';
  String search = '';
  int page = 1;
  Timer? _debounce;

  late final query = Query<Json>(
    () async => jmap(await session.api.listRefunds({'status': status, 'search': search, 'page': page, 'limit': 20})),
    client: session.client,
  );

  @override
  void initState() {
    super.initState();
    final focus = widget.focusId;
    if (focus != null) {
      session.api.listRefunds({'limit': 100}).then((result) {
        final found = jlist(jmap(result)['items']).where((r) => jstr(r['id']) == focus).firstOrNull;
        if (found != null && mounted) showAppSheet(context, _RefundSheet(refund: found));
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: query.load, children: [
      const PageHeader(
        title: 'Refunds',
        description: 'Money owed back to customers whose paid orders were cancelled. Send it back the way they paid, then record the transaction reference.',
      ),
      ListenableBuilder(
        listenable: query,
        builder: (context, _) {
          final summary = query.data?['summary'] is Map ? jmap(query.data!['summary']) : null;
          final service = query.data?['payout_service'] is Map ? jmap(query.data!['payout_service']) : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            if (summary != null)
              ResponsiveGrid(minWidth: 110, children: [
                StatCard(label: 'To send', value: formatRwf(jmap(summary['pending'])['amount_rwf']), hint: '${jint(jmap(summary['pending'])['count'])} refunds', tone: Tone.amber),
                StatCard(label: 'Failed (still owed)', value: formatRwf(jmap(summary['failed'])['amount_rwf']), hint: '${jint(jmap(summary['failed'])['count'])} refunds', tone: Tone.red),
                StatCard(label: 'Sent', value: formatRwf(jmap(summary['completed'])['amount_rwf']), hint: '${jint(jmap(summary['completed'])['count'])} refunds', tone: Tone.green),
              ]),
            if (service != null && service['automatic'] != true)
              Hint('Payout service: ${jstr(service['label'])}. Send each refund from the business mobile money / card account, '
                  'then mark it sent here. The customer is notified automatically.'),
          ]));
        },
      ),
      SearchField(
        hint: 'Order number, phone or reference',
        live: true,
        onSubmit: (value) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), () {
            setState(() {
              search = value.trim();
              page = 1;
            });
            query.load();
          });
        },
      ),
      Dropdown<String>(
        value: status,
        options: const {'': 'All refunds', 'pending': 'To send', 'failed': 'Failed', 'completed': 'Sent'},
        onChanged: (value) {
          setState(() {
            status = value;
            page = 1;
          });
          query.load();
        },
      ),
      QueryView<Json>(
        query: query,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return Card(child: EmptyState(icon: Icons.replay_outlined, title: status == 'pending' ? 'No refunds to send' : 'No refunds'));
          }
          return RecordList(
            footer: Pager.of(data, onPage: (next) {
              setState(() => page = next);
              query.load();
            }),
            children: [
              for (final refund in items)
                RecordTile(
                  title: jstr(refund['order_number']),
                  subtitle: '${jstr(jmap(refund['customer'])['name'], '—')}${jstr(jmap(refund['customer'])['phone']).isNotEmpty ? ' · ${jstr(jmap(refund['customer'])['phone'])}' : ''}',
                  trailing: formatRwf(refund['amount_rwf']),
                  badges: [ToneBadge(_statusLabel[refund['status']] ?? toTitle(refund['status']), tone: _statusTone[refund['status']] ?? Tone.slate)],
                  lines: [
                    'by ${_cancelledBy[refund['cancelled_by']] ?? jstr(refund['cancelled_by'])}${jstr(refund['reason']).isNotEmpty ? ' · ${jstr(refund['reason'])}' : ''}',
                    'Send to ${jstr(jmap(refund['destination'])['label'])}',
                    if (jstr(refund['reference']).isNotEmpty) 'ref ${jstr(refund['reference'])}',
                    if (jstr(refund['failure_reason']).isNotEmpty) jstr(refund['failure_reason']),
                    'Cancelled ${formatDate(refund['created_at'])}',
                  ],
                  actions: [
                    if (refund['status'] != 'completed' && session.can('refunds:write'))
                      refund['status'] == 'pending'
                          ? FilledButton(onPressed: () => showAppSheet(context, _RefundSheet(refund: refund)), child: const Text('Send refund'))
                          : OutlinedButton(onPressed: () => showAppSheet(context, _RefundSheet(refund: refund)), child: const Text('Retry')),
                  ],
                ),
            ],
          );
        },
      ),
    ]);
  }
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.refund});

  final Json refund;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> with BusyState {
  late String outcome = widget.refund['status'] == 'failed' ? 'pending' : 'completed';
  final reference = TextEditingController();
  final reason = TextEditingController();

  @override
  void dispose() {
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  bool get saveDisabled =>
      (outcome == 'completed' && reference.text.trim().isEmpty) || (outcome == 'failed' && reason.text.trim().isEmpty);

  Future<void> save() async {
    final api = context.read<AdminSession>().api;
    final body = switch (outcome) {
      'completed' => {'status': 'completed', 'reference': reference.text},
      'failed' => {'status': 'failed', 'reason': reason.text},
      _ => {'status': 'pending'},
    };
    final ok = await run(() => api.updateRefund(jstr(widget.refund['id']), body));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.refund;
    return SheetScaffold(
      title: 'Refund · ${jstr(r['order_number'])}',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: outcome == 'completed' ? 'Mark as sent' : outcome == 'failed' ? 'Mark as failed' : 'Retry refund',
          busy: busy,
          onPressed: saveDisabled ? null : save,
        ),
      ],
      children: [
        InfoTile('', '', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Send '),
            TextSpan(text: formatRwf(r['amount_rwf']), style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' back to '),
            TextSpan(text: jstr(jmap(r['customer'])['name'], 'the customer'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' on their '),
            TextSpan(text: jstr(jmap(r['destination'])['label']), style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: '.'),
          ])),
          Hint('Cancelled by ${_cancelledBy[r['cancelled_by']] ?? jstr(r['cancelled_by'])} · ${formatDate(r['created_at'])}'),
          if (jstr(r['failure_reason']).isNotEmpty) Hint('Last attempt failed: ${jstr(r['failure_reason'])}', color: const Color(0xFFDC2626)),
        ])),
        Dropdown<String>(
          label: 'Outcome',
          value: outcome,
          options: r['status'] == 'pending'
              ? const {
                  'completed': 'Sent: I sent the money back',
                  'failed': 'Failed: it could not be sent (customer is asked for another number)',
                }
              : const {'pending': 'Retry: put it back in the list to send'},
          onChanged: (value) => setState(() => outcome = value),
        ),
        if (outcome == 'completed')
          TextField(
            controller: reference,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Transaction reference (required)', hintText: 'e.g. MoMo transaction ID'),
          ),
        if (outcome == 'failed')
          TextField(
            controller: reason,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Reason (shown to the customer)', hintText: 'e.g. Number not registered for mobile money'),
          ),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
