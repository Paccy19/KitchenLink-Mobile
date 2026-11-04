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


  /// Two cards side by side from 1024px (`lg:grid-cols-…`), stacked below.
  /// [equalHeights] matches CSS grid rows; leave it off when a card holds a table.
  Widget _pair(Widget first, Widget second, {int firstFlex = 1, bool equalHeights = true}) {
    if (MediaQuery.sizeOf(context).width < 1024) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([first, second], 16));
    final row = Row(crossAxisAlignment: equalHeights ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, children: [
      Expanded(flex: firstFlex, child: first),
      const SizedBox(width: 16),
      Expanded(child: second),
    ]);
    return equalHeights ? IntrinsicHeight(child: row) : row;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final p = Palette.of(context);
    final range = [
      WebDateInput(
        value: from,
        onChanged: (value) {
          setState(() => from = value);
          reloadAll();
        },
      ),
      WebDateInput(
        value: to,
        onChanged: (value) {
          setState(() => to = value);
          reloadAll();
        },
      ),
      WebSelect<String>(
        value: granularity,
        options: const {'day': 'Daily', 'hour': 'Hourly'},
        onChanged: (value) {
          setState(() => granularity = value);
          salesQuery.load();
        },
      ),
    ];

    return PageBody(onRefresh: reloadAll, children: [
      const PageHeader(title: 'Analytics', description: 'Revenue, growth and payout insights for the selected period.'),
      SectionCard(
        title: 'Date range',
        padding: const EdgeInsets.all(16),
        // `grid-cols-1 sm:grid-cols-3 gap-3`.
        child: ResponsiveGrid(minWidth: 1, maxColumns: viewport >= 640 ? 3 : 1, equalHeights: false, children: range),
      ),
      QueryView<Json>(
        query: overviewQuery,
        builder: (context, overview) {
          final sales = jmap(overview['sales']);
          final signups = jmap(overview['signups']);
          final topVendors = jlist(overview['top_vendors']);
          final columns = viewport >= 1024 ? 4 : 2;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            ResponsiveGrid(minWidth: 1, maxColumns: columns, children: [
              StatCard(label: 'Gross Sales', value: formatRwf(sales['gross_rwf']), icon: Icons.trending_up, tone: Tone.green),
              StatCard(label: 'Completed Orders', value: formatNumber(sales['orders']), icon: Icons.bar_chart, tone: Tone.blue),
              StatCard(label: 'Commission', value: formatRwf(sales['commission_rwf']), hint: '${jstr(sales['commission_percent'], '0')}%', tone: Tone.violet),
              StatCard(label: 'Delivery Fees', value: formatRwf(sales['delivery_fees_rwf']), icon: Icons.account_balance_wallet_outlined, tone: Tone.amber),
            ]),
            ResponsiveGrid(minWidth: 1, maxColumns: columns, children: [
              StatCard(label: 'New Customers', value: formatNumber(signups['customers']), icon: Icons.people_outline),
              StatCard(label: 'New Vendors', value: formatNumber(signups['vendors'])),
              StatCard(label: 'New Delivery Workers', value: formatNumber(signups['drivers'])),
              StatCard(label: 'Orders Created', value: formatNumber(overview['orders_created'])),
            ]),
            // `lg:grid-cols-3`, Sales Trend spanning two columns.
            _pair(
              SectionCard(title: 'Sales Trend', child: _salesTrend()),
              SectionCard(
                title: 'Top Vendors',
                child: topVendors.isEmpty
                    ? Text('No vendor sales yet.', style: TextStyle(fontSize: 14, color: p.faint))
                    : Column(children: spaced([
                        for (final vendor in topVendors)
                          _listRow(jstr(vendor['name']), '${jint(vendor['orders'])} · ${formatRwf(vendor['gross_rwf'])}'),
                      ], 8)),
              ),
              firstFlex: 2,
            ),
            _pair(
              SectionCard(title: 'Deliveries by Status', child: _breakdown(jmap(overview['deliveries_by_status']))),
              SectionCard(title: 'Complaints by Status', child: _breakdown(jmap(overview['complaints_by_status']))),
            ),
          ], 20));
        },
      ),
      ListenableBuilder(
        listenable: payoutsQuery,
        builder: (context, _) {
          final payouts = payoutsQuery.data;
          if (payouts == null) return const SizedBox.shrink();
          final byStatus = jlist(payouts['withdrawals_by_status']);
          final balances = jlist(payouts['top_vendor_balances']);
          return _pair(
            SectionCard(
              title: 'Payouts by Status',
              child: byStatus.isEmpty
                  ? const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No withdrawal activity')
                  : WebTable(
                      columns: const [WebColumn('Status'), WebColumn('Count'), WebColumn('Total')],
                      rows: [
                        for (final row in byStatus)
                          [
                            Text(toTitle(row['status']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                            Text('${jint(row['count'])}', style: TextStyle(fontSize: 14, color: p.textSecondary)),
                            Text(formatRwf(row['total_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                          ],
                      ],
                    ),
            ),
            SectionCard(
              title: 'Top Vendor Balances',
              child: balances.isEmpty
                  ? Text('No balances.', style: TextStyle(fontSize: 14, color: p.faint))
                  : Column(children: spaced([for (final v in balances) _listRow(jstr(v['name']), formatRwf(v['available_balance_rwf']))], 8)),
            ),
            equalHeights: false,
          );
        },
      ),
    ]);
  }

  /// `text-sm font-bold text-gray-800 truncate` name with a `text-xs text-stone-500` value.
  Widget _listRow(String name, String value) {
    final p = Palette.of(context);
    return Row(children: [
      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
      const SizedBox(width: 8),
      Text(value, style: TextStyle(fontSize: 12, color: p.muted)),
    ]);
  }

  /// Bars: `w-24` period, `h-2.5 rounded-full bg-stone-100` track with the
  /// slate gradient, `w-28` amount.
  Widget _salesTrend() {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: salesQuery,
      builder: (context, _) {
        if (salesQuery.error != null && salesQuery.data == null) return ErrorNote(error: salesQuery.error, onRetry: salesQuery.load);
        final data = salesQuery.data;
        if (data == null) return const LoadingBlock();
        final series = jlist(data['series']);
        if (series.isEmpty) return const EmptyState(icon: Icons.bar_chart, title: 'No sales in this period');
        final max = series.map((point) => jnum(point['gross_rwf'])).fold<num>(1, (a, b) => b > a ? b : a);
        return Column(children: spaced([
          for (final point in series)
            Row(children: [
              SizedBox(
                width: 96,
                child: Text(jstr(point['period']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(color: p.stone100, borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (jnum(point['gross_rwf']) / max).clamp(0.02, 1.0).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF4B5563)]),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                child: Text(formatRwf(point['gross_rwf']), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textSecondary)),
              ),
            ]),
        ], 8));
      },
    );
  }

  /// `space-y-2` rows: `text-sm text-stone-600` label, `text-sm font-bold` count.
  Widget _breakdown(Json entries) {
    final p = Palette.of(context);
    if (entries.isEmpty) return Text('No data.', style: TextStyle(fontSize: 14, color: p.faint));
    return Column(children: spaced([
      for (final entry in entries.entries)
        Row(children: [
          Expanded(child: Text(toTitle(entry.key), style: TextStyle(fontSize: 14, color: p.textSecondary))),
          Text(formatNumber(entry.value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        ]),
    ], 8));
  }
}
