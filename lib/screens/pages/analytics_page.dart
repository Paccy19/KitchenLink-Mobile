import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Revenue, growth and payout insights for the selected period.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late final session = context.read<AdminSession>();
  String from = isoDay(DateTime.now().subtract(const Duration(days: 30)));
  String to = isoDay(DateTime.now());
  String granularity = 'day';

  Map<String, Object?> get params => {
        'from': from.isEmpty ? '' : '${from}T00:00:00',
        'to': to.isEmpty ? '' : '${to}T23:59:59',
      };

  late final overviewQuery = Query<Json>(() async => jmap(await session.api.analyticsOverview(params)), client: session.client);
  late final salesQuery = Query<Json>(() async => jmap(await session.api.analyticsSales({...params, 'granularity': granularity})), client: session.client);
  late final payoutsQuery = Query<Json>(() async => jmap(await session.api.analyticsPayouts(params)), client: session.client);

  @override
  void dispose() {
    overviewQuery.dispose();
    salesQuery.dispose();
    payoutsQuery.dispose();
    super.dispose();
  }

  Future<void> reloadAll() async {
    await Future.wait([overviewQuery.load(), salesQuery.load(), payoutsQuery.load()]);
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: reloadAll, children: [
      const PageHeader(title: 'Analytics', description: 'Revenue, growth and payout insights for the selected period.'),
      SectionCard(
        title: 'Date range',
        child: Column(children: spaced([
          Row(children: [
            Expanded(
              child: DateField(
                label: 'From',
                value: from,
                last: DateTime.tryParse(to),
                onChanged: (value) {
                  setState(() => from = value);
                  reloadAll();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DateField(
                label: 'To',
                value: to,
                first: DateTime.tryParse(from),
                onChanged: (value) {
                  setState(() => to = value);
                  reloadAll();
                },
              ),
            ),
          ]),
          Dropdown<String>(
            value: granularity,
            options: const {'day': 'Daily', 'hour': 'Hourly'},
            onChanged: (value) {
              setState(() => granularity = value);
              salesQuery.load();
            },
          ),
        ])),
      ),
      QueryView<Json>(
        query: overviewQuery,
        builder: (context, overview) {
          final sales = jmap(overview['sales']);
          final signups = jmap(overview['signups']);
          final topVendors = jlist(overview['top_vendors']);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            ResponsiveGrid(children: [
              StatCard(label: 'Gross Sales', value: formatRwf(sales['gross_rwf']), icon: Icons.trending_up, tone: Tone.green),
              StatCard(label: 'Completed Orders', value: formatNumber(sales['orders']), icon: Icons.bar_chart, tone: Tone.blue),
              StatCard(label: 'Commission', value: formatRwf(sales['commission_rwf']), hint: '${jstr(sales['commission_percent'], '0')}%', tone: Tone.violet),
              StatCard(label: 'Delivery Fees', value: formatRwf(sales['delivery_fees_rwf']), icon: Icons.account_balance_wallet_outlined, tone: Tone.amber),
              StatCard(label: 'New Customers', value: formatNumber(signups['customers']), icon: Icons.people_outline),
              StatCard(label: 'New Vendors', value: formatNumber(signups['vendors'])),
              StatCard(label: 'New Delivery Workers', value: formatNumber(signups['drivers'])),
              StatCard(label: 'Orders Created', value: formatNumber(overview['orders_created'])),
            ]),
            SectionCard(title: 'Sales Trend', child: _salesTrend()),
            SectionCard(
              title: 'Top Vendors',
              child: topVendors.isEmpty
                  ? const Hint('No vendor sales yet.')
                  : Column(children: [
                      for (final vendor in topVendors)
                        _row(jstr(vendor['name']), '${jint(vendor['orders'])} · ${formatRwf(vendor['gross_rwf'])}'),
                    ]),
            ),
            SectionCard(title: 'Deliveries by Status', child: _breakdown(jmap(overview['deliveries_by_status']))),
            SectionCard(title: 'Complaints by Status', child: _breakdown(jmap(overview['complaints_by_status']))),
          ]));
        },
      ),
      ListenableBuilder(
        listenable: payoutsQuery,
        builder: (context, _) {
          final payouts = payoutsQuery.data;
          if (payouts == null) return const SizedBox.shrink();
          final byStatus = jlist(payouts['withdrawals_by_status']);
          final balances = jlist(payouts['top_vendor_balances']);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            SectionCard(
              title: 'Payouts by Status',
              child: byStatus.isEmpty
                  ? const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No withdrawal activity')
                  : Column(children: [
                      for (final row in byStatus) _row(toTitle(row['status']), '${jint(row['count'])} · ${formatRwf(row['total_rwf'])}'),
                    ]),
            ),
            SectionCard(
              title: 'Top Vendor Balances',
              child: balances.isEmpty
                  ? const Hint('No balances.')
                  : Column(children: [for (final v in balances) _row(jstr(v['name']), formatRwf(v['available_balance_rwf']))]),
            ),
          ], 14));
        },
      ),
    ]);
  }

  Widget _salesTrend() {
    return ListenableBuilder(
      listenable: salesQuery,
      builder: (context, _) {
        if (salesQuery.error != null && salesQuery.data == null) return ErrorNote(error: salesQuery.error, onRetry: salesQuery.load);
        final data = salesQuery.data;
        if (data == null) return const LoadingBlock();
        final series = jlist(data['series']);
        if (series.isEmpty) return const EmptyState(icon: Icons.bar_chart, title: 'No sales in this period');
        final max = series.map((p) => jnum(p['gross_rwf'])).fold<num>(1, (a, b) => b > a ? b : a);
        return Column(children: [
          for (final point in series)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 86, child: Text(jstr(point['period']), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (jnum(point['gross_rwf']) / max).clamp(0.02, 1.0).toDouble(),
                      minHeight: 9,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: AppColors.slate,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(formatRwf(point['gross_rwf']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _breakdown(Json entries) {
    if (entries.isEmpty) return const Hint('No data.');
    return Column(children: [for (final entry in entries.entries) _row(toTitle(entry.key), formatNumber(entry.value))]);
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
}
