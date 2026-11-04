import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _transactionTypes = [
  'order_payment',
  'vendor_earning',
  'driver_earning',
  'driver_penalty',
  'commission',
  'refund',
  'withdrawal',
  'adjustment',
  'platform_withdrawal',
];

/// The platform's money books (read-only): what the account should hold, what
/// it is made of, and the ledger behind it. For the finance role.
class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  late final session = context.read<AdminSession>();
  String type = '';
  int page = 1;
  late final query = Query<Json>(
    () async => jmap(await session.api.platformWallet({'type': type, 'page': page, 'limit': 20})),
    client: session.client,
  );

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
        final account = jmap(data['account']);
        final reconciliation = jmap(account['reconciliation']);
        final balanced = reconciliation['balanced'] == true;
        final transactions = jlist(data['transactions']);
        return PageBody(onRefresh: query.load, children: [
          const PageHeader(title: 'Platform Books', description: "The marketplace's money: what the account holds and every ledger entry behind it."),
          ResponsiveGrid(children: [
            StatCard(label: 'Cash in account', value: formatRwf(account['cash_balance_rwf']), hint: 'Should be in the real account', tone: balanced ? Tone.green : Tone.red),
            StatCard(label: 'Held', value: formatRwf(account['held_balance_rwf']), hint: 'Orders in progress'),
            StatCard(label: 'Refunds owed', value: formatRwf(account['refunds_owed_rwf'])),
            StatCard(label: 'Owed to vendors', value: formatRwf(account['vendor_payable_rwf'])),
            StatCard(label: 'Owed to delivery workers', value: formatRwf(account['driver_payable_rwf'])),
            StatCard(label: 'Commission balance', value: formatRwf(account['commission_balance_rwf']), tone: Tone.violet),
          ]),
          SectionCard(
            title: 'Reconciliation',
            action: balanced
                ? const ToneBadge('Balanced', tone: Tone.green)
                : ToneBadge('Off by ${formatRwf(reconciliation['unreconciled_rwf'])}', tone: Tone.red),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ResponsiveGrid(children: [
                StatCard(label: 'Collected', value: formatRwf(account['total_collected_rwf'])),
                StatCard(label: 'Refunded', value: formatRwf(account['total_refunded_rwf'])),
                StatCard(label: 'Commission earned', value: formatRwf(account['total_commission_rwf'])),
                StatCard(
                  label: 'Paid out to vendors / workers',
                  value: formatRwf(jnum(account['total_vendor_payouts_rwf']) + jnum(account['total_driver_payouts_rwf'])),
                ),
              ]),
              if (account['computed_at'] != null) ...[const SizedBox(height: 8), Hint('Recomputed ${formatDate(account['computed_at'])}')],
            ]),
          ),
          SectionCard(
            title: 'Ledger',
            description: 'Every money movement on the platform, newest first.',
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              Dropdown<String>(
                value: type,
                options: {'': 'All types', for (final t in _transactionTypes) t: toTitle(t)},
                onChanged: (value) {
                  setState(() {
                    type = value;
                    page = 1;
                  });
                  query.load(silent: true);
                },
              ),
              if (transactions.isEmpty)
                const EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No ledger entries',
                  description: 'Money movements will appear here as orders are paid and settled.',
                )
              else
                RecordList(
                  footer: Pager.of(data, onPage: (next) {
                    setState(() => page = next);
                    query.load(silent: true);
                  }),
                  children: [
                    for (final entry in transactions)
                      RecordTile(
                        title: toTitle(entry['type']),
                        subtitle: jstr(entry['description']),
                        trailing: '${entry['direction'] == 'debit' ? '−' : '+'}${formatRwf(entry['amount_rwf'])}',
                        badges: [ToneBadge(entry['direction'] == 'credit' ? 'Credit' : 'Debit', tone: entry['direction'] == 'credit' ? Tone.green : Tone.amber)],
                        lines: [
                          'Order ${jstr(entry['order_number'], '—')} · Ref ${jstr(entry['reference'], '—')}',
                          formatDate(entry['created_at']),
                        ],
                      ),
                  ],
                ),
            ])),
          ),
        ]);
      },
    );
  }
}
