import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../nav/admin_nav.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../admin_shell.dart';

// `text-amber-600`, `text-emerald-600`, `text-red-600` metric values.
const _amber600 = Color(0xFFD97706);
const _emerald600 = Color(0xFF059669);
const _red600 = Color(0xFFDC2626);

/// Today's performance and live marketplace health (the website's AdminOverviewPage).
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.dashboard()), client: session.client);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = context.read<ShellNavigator>().go;
    return QueryView<Json>(
      query: query,
      loadingLabel: 'Loading overview…',
      builder: (context, data) {
        final today = jmap(data['today']);
        final orders = jmap(data['orders']);
        final vendors = jmap(data['vendors']);
        final customers = jmap(data['customers']);
        final drivers = jmap(data['drivers']);
        final deliveries = jmap(data['deliveries']);
        final complaints = jmap(data['complaints']);
        final ops = data['operations'] is Map ? jmap(data['operations']) : null;
        final recent = jlist(data['recent_orders']);
        final pickups24h = jint(ops?['pickup_orders_last_24h']);

        return PageBody(onRefresh: query.load, gap: 24, children: [
          const PageHeader(title: 'Overview', description: "Today's performance and live marketplace health."),
          ResponsiveGrid(children: [
            StatCard(label: 'Orders Today', value: formatNumber(today['orders']), icon: Icons.shopping_bag_outlined, tone: Tone.blue),
            StatCard(label: 'Sales Today', value: formatRwf(today['sales_rwf']), icon: Icons.account_balance_wallet_outlined, tone: Tone.green),
            StatCard(label: 'Completed Today', value: formatNumber(today['completed_orders']), icon: Icons.trending_up, tone: Tone.green),
            StatCard(
              label: 'Commission Today',
              value: formatRwf(today['commission_rwf']),
              icon: Icons.percent,
              tone: Tone.violet,
              hint: '${jstr(data['commission_percent'], '0')}% of gross',
            ),
          ]),
          ResponsiveGrid(children: [
            StatCard(label: 'Pending Orders', value: formatNumber(orders['pending']), icon: Icons.shopping_bag_outlined, tone: Tone.amber),
            StatCard(label: 'Live Orders', value: formatNumber(orders['live']), icon: Icons.local_shipping_outlined, tone: Tone.blue),
            StatCard(label: 'Active Deliveries', value: formatNumber(deliveries['active']), icon: Icons.pedal_bike_outlined, tone: Tone.blue),
            StatCard(label: 'Open Complaints', value: formatNumber(complaints['open']), icon: Icons.chat_bubble_outline, tone: Tone.red),
          ]),
          if (ops != null)
            SectionCard(
              title: 'Needs attention now',
              description: 'Dispatch, customer pickups and kitchens, live.',
              action: _Link('Live map', onTap: () => go(const AdminRoute(Pages.deliveries))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ResponsiveGrid(minWidth: 140, maxColumns: 7, children: [
                  _Attention('Waiting for a delivery worker', ops['orders_awaiting_driver'], warn: true, onTap: () => go(const AdminRoute(Pages.deliveries))),
                  _Attention('Late, not yet collected', ops['late_pickups_waiting'], warn: true, onTap: () => go(const AdminRoute(Pages.deliveries, {'tab': 'late'}))),
                  _Attention('Late pickups (charge pending)', ops['late_pickups_pending_charge'], warn: true, onTap: () => go(const AdminRoute(Pages.deliveries, {'tab': 'late'}))),
                  _Attention('Pickups awaiting collection', ops['pickups_awaiting_collection'], onTap: () => go(const AdminRoute(Pages.orders))),
                  _Attention('Pickups locked (wrong codes)', ops['pickups_locked'], warn: true, onTap: () => go(const AdminRoute(Pages.orders))),
                  _Attention('Kitchens open now', ops['kitchens_open'], onTap: () => go(const AdminRoute(Pages.vendors))),
                  _Attention('Delivery workers ready for orders', ops['drivers_matchable'], onTap: () => go(const AdminRoute(Pages.drivers))),
                ]),
                const SizedBox(height: 12),
                Text(
                  '$pickups24h customer pickup order${pickups24h == 1 ? '' : 's'} in the last 24 hours.',
                  style: TextStyle(fontSize: 11, color: Palette.of(context).faint),
                ),
              ]),
            ),
          ResponsiveGrid(minWidth: 300, maxColumns: 3, spacing: 16, equalHeights: false, children: [
            _GroupCard(
              title: 'Vendors',
              metrics: [
                ('Total', formatNumber(vendors['total']), null),
                ('Pending', formatNumber(vendors['pending']), _amber600),
                ('Approved', formatNumber(vendors['approved']), _emerald600),
                ('Suspended', formatNumber(vendors['suspended']), _red600),
              ],
              linkIcon: Icons.storefront_outlined,
              link: 'Manage vendors',
              onLink: () => go(const AdminRoute(Pages.vendors)),
            ),
            _GroupCard(
              title: 'Delivery Workers',
              metrics: [
                ('Total', formatNumber(drivers['total']), null),
                ('Online', formatNumber(drivers['online']), _emerald600),
                ('Pending', formatNumber(drivers['pending']), _amber600),
                ('Suspended', formatNumber(drivers['suspended']), _red600),
              ],
              linkIcon: Icons.pedal_bike_outlined,
              link: 'Manage delivery workers',
              onLink: () => go(const AdminRoute(Pages.drivers)),
            ),
            _GroupCard(
              title: 'Customers',
              metrics: [
                ('Total', formatNumber(customers['total']), null),
                ('Active', formatNumber(customers['active']), _emerald600),
                ('Suspended', formatNumber(jint(customers['total']) - jint(customers['active'])), _red600),
                ('Delivery Fees', formatRwf(today['delivery_fees_rwf']), null),
              ],
              linkIcon: Icons.people_outline,
              link: 'Manage users',
              onLink: () => go(const AdminRoute(Pages.users)),
            ),
          ]),
          SectionCard(
            title: 'Recent Orders',
            action: _Link('View all', onTap: () => go(const AdminRoute(Pages.orders))),
            padding: EdgeInsets.zero,
            child: recent.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    child: Text('No orders yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Palette.of(context).faint)),
                  )
                : Column(children: [
                    for (var i = 0; i < recent.length; i++) ...[
                      if (i > 0) Divider(color: Palette.of(context).stone50),
                      _RecentOrder(order: recent[i], onTap: () => go(AdminRoute(Pages.orders, {'order': jstr(recent[i]['id'])}))),
                    ],
                  ]),
          ),
        ]);
      },
    );
  }
}

/// `text-xs font-bold text-[#1f2937] hover:underline`.
class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Palette.of(context).accent;
    return InkWell(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

/// A count that links to where it is handled; amber when it needs action.
class _Attention extends StatelessWidget {
  const _Attention(this.label, this.value, {this.warn = false, required this.onTap});

  final String label;
  final dynamic value;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final alert = warn && jint(value) > 0;
    return Material(
      color: alert ? Tone.amber.background(context) : p.stone50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: alert ? Tone.amber.border(context) : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 10, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: p.faint)),
            Text(formatNumber(value),
                style: TextStyle(fontSize: 18, height: 1.55, fontWeight: FontWeight.w800, color: alert ? Tone.amber.foreground(context) : p.text)),
          ]),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.title, required this.metrics, required this.link, required this.linkIcon, required this.onLink});

  final String title;
  final List<(String, String, Color?)> metrics;
  final String link;
  final IconData linkIcon;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SectionCard(
      title: title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ResponsiveGrid(minWidth: 100, maxColumns: 2, children: [
          for (final (label, value, color) in metrics)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: p.faint)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, height: 1.55, fontWeight: FontWeight.w800, color: color ?? p.text)),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        _Link(link, icon: linkIcon, onTap: onLink),
      ]),
    );
  }
}

/// `flex justify-between px-4 py-3`: "number · kitchen" and "customer · date",
/// then the total and status.
class _RecentOrder extends StatelessWidget {
  const _RecentOrder({required this.order, required this.onTap});

  final Json order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${jstr(order['order_number'])} · ${jstr(jmap(order['vendor'])['name'], 'Vendor')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              Text('${jstr(jmap(order['customer'])['name'], 'Customer')} · ${formatDate(order['created_at'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Text(formatRwf(order['total_amount_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(width: 12),
          StatusBadge(jstr(order['status_label'], jstr(order['status']))),
        ]),
      ),
    );
  }
}
