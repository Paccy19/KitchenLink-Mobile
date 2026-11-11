import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Today's performance and live marketplace health (the website's
/// AdminOverviewPage), laid out as an operations board: the day's numbers,
/// what needs the admin now (most urgent first) and the live order pipeline.
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

  static String _greeting(DateTime now) => now.hour < 12 ? 'Good morning' : (now.hour < 17 ? 'Good afternoon' : 'Good evening');

  @override
  Widget build(BuildContext context) {
    final go = context.read<ShellNavigator>().go;
    final firstName = (session.admin?['name'] ?? '').toString().trim().split(RegExp(r'\s+')).first;
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

        // What needs the admin, most urgent first; only the ones with a count.
        final attention = <_Alert>[
          if (ops != null) ...[
            _Alert(Tone.red, 'Urgent', ops['orders_awaiting_driver'], (n) => '$n order${n == 1 ? '' : 's'} waiting for a delivery worker',
                'Ready for dispatch with nobody assigned', 'Assign', () => go(const AdminRoute(Pages.deliveries))),
            _Alert(Tone.red, 'Locked', ops['pickups_locked'], (n) => '$n pickup${n == 1 ? '' : 's'} locked after wrong codes',
                'The customer typed the wrong collection code too often', 'Open', () => go(const AdminRoute(Pages.orders))),
            _Alert(Tone.amber, 'Late', ops['late_pickups_waiting'], (n) => '$n late pickup${n == 1 ? '' : 's'} not yet collected',
                'Past the collection time and still at the kitchen', 'Review', () => go(const AdminRoute(Pages.deliveries, {'tab': 'late'}))),
            _Alert(Tone.amber, 'Charge', ops['late_pickups_pending_charge'], (n) => '$n late pickup charge${n == 1 ? '' : 's'} pending',
                'Decide the late-collection charge', 'Review', () => go(const AdminRoute(Pages.deliveries, {'tab': 'late'}))),
          ],
          _Alert(Tone.violet, 'Support', complaints['open'], (n) => '$n open complaint${n == 1 ? '' : 's'}',
              'Customers waiting for an answer', 'Reply', () => go(const AdminRoute(Pages.complaints))),
          _Alert(Tone.blue, 'Approval', vendors['pending'], (n) => '$n kitchen${n == 1 ? '' : 's'} waiting for approval',
              'Check documents and menus before they go live', 'Open queue', () => go(const AdminRoute(Pages.vendors))),
          _Alert(Tone.slate, 'Documents', drivers['pending'], (n) => '$n delivery worker${n == 1 ? '' : 's'} to approve',
              'Licences and IDs waiting for review', 'Review', () => go(const AdminRoute(Pages.drivers))),
        ].where((a) => a.count > 0).toList();

        final now = DateTime.now();
        final subtitle = [
          DateFormat('EEEE, d MMMM').format(now),
          'Kigali',
          attention.isEmpty ? 'nothing needs you right now' : '${attention.length} thing${attention.length == 1 ? '' : 's'} need${attention.length == 1 ? 's' : ''} you',
        ].join(' · ');

        final pipeline = [
          ('Placed, waiting for the kitchen', jint(orders['pending']), Tone.orange),
          ('Live orders', jint(orders['live']), Tone.orange),
          ('Out for delivery', jint(deliveries['active']), Tone.orange),
          if (ops != null) ('Pickups waiting for collection', jint(ops['pickups_awaiting_collection']), Tone.amber),
          ('Completed today', jint(today['completed_orders']), Tone.slate),
        ];

        final wide = MediaQuery.sizeOf(context).width >= 900;
        final attentionCard = _AttentionCard(alerts: attention);
        final pipelineCard = _PipelineCard(
          stages: pipeline,
          footer: ops == null
              ? null
              : '${formatNumber(ops['kitchens_open'])} kitchens open · ${formatNumber(ops['drivers_matchable'])} delivery workers ready for orders · '
                  '$pickups24h pickup order${pickups24h == 1 ? '' : 's'} in the last 24 hours.',
          onMap: () => go(const AdminRoute(Pages.deliveries)),
        );

        return PageBody(onRefresh: query.load, gap: 24, children: [
          PageHeader(title: firstName.isEmpty ? _greeting(now) : '${_greeting(now)}, $firstName', description: subtitle),
          ResponsiveGrid(minWidth: 160, spacing: 12, children: [
            StatCard(
              label: 'Orders today',
              value: formatNumber(today['orders']),
              icon: Icons.receipt_long_outlined,
              hint: '${formatNumber(today['completed_orders'])} completed',
            ),
            StatCard(
              label: 'Sales today',
              value: formatRwf(today['sales_rwf']),
              icon: Icons.payments_outlined,
              hint: '${formatRwf(today['commission_rwf'])} commission · ${jstr(data['commission_percent'], '0')}%',
            ),
            StatCard(
              label: 'Live orders',
              value: formatNumber(orders['live']),
              icon: Icons.local_shipping_outlined,
              hint: '${formatNumber(orders['pending'])} waiting · ${formatNumber(deliveries['active'])} on the road',
            ),
            StatCard(
              label: 'Open complaints',
              value: formatNumber(complaints['open']),
              icon: Icons.support_agent_outlined,
              hint: jint(complaints['open']) > 0 ? 'Customers waiting for a reply' : 'All answered',
            ),
          ]),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 11, child: attentionCard),
              const SizedBox(width: 16),
              Expanded(flex: 9, child: pipelineCard),
            ])
          else ...[
            attentionCard,
            pipelineCard,
          ],
          ResponsiveGrid(minWidth: 300, maxColumns: 3, spacing: 16, equalHeights: false, children: [
            _GroupCard(
              title: 'Kitchens',
              metrics: [
                ('Total', formatNumber(vendors['total']), null),
                ('Waiting for approval', formatNumber(vendors['pending']), _amber600),
                ('Approved', formatNumber(vendors['approved']), _emerald600),
                ('Suspended', formatNumber(vendors['suspended']), _red600),
              ],
              link: 'Manage vendors',
              onLink: () => go(const AdminRoute(Pages.vendors)),
            ),
            _GroupCard(
              title: 'Delivery workers',
              metrics: [
                ('Total', formatNumber(drivers['total']), null),
                ('Online', formatNumber(drivers['online']), _emerald600),
                ('Waiting for approval', formatNumber(drivers['pending']), _amber600),
                ('Suspended', formatNumber(drivers['suspended']), _red600),
              ],
              link: 'Manage delivery workers',
              onLink: () => go(const AdminRoute(Pages.drivers)),
            ),
            _GroupCard(
              title: 'Customers',
              metrics: [
                ('Total', formatNumber(customers['total']), null),
                ('Active', formatNumber(customers['active']), _emerald600),
                ('Suspended', formatNumber(jint(customers['total']) - jint(customers['active'])), _red600),
                ('Delivery fees today', formatRwf(today['delivery_fees_rwf']), null),
              ],
              link: 'Manage customers',
              onLink: () => go(const AdminRoute(Pages.users)),
            ),
          ]),
          SectionCard(
            title: 'Recent orders',
            action: SmallButton('View all', onPressed: () => go(const AdminRoute(Pages.orders))),
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: recent.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    child: Text('No orders yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Palette.of(context).faint)),
                  )
                : wide
                    ? WebTable(
                        columns: [
                          WebColumn('Order', nowrap: true),
                          WebColumn('Customer'),
                          WebColumn('Kitchen'),
                          WebColumn('Placed', nowrap: true),
                          WebColumn('Status', nowrap: true),
                          WebColumn('Total', nowrap: true, alignEnd: true),
                        ],
                        rows: [
                          for (final order in recent)
                            [
                              InkWell(
                                onTap: () => go(AdminRoute(Pages.orders, {'order': jstr(order['id'])})),
                                child: CellText(jstr(order['order_number'])),
                              ),
                              CellText(jstr(jmap(order['customer'])['name'], 'Customer'), bold: false),
                              CellText(jstr(jmap(order['vendor'])['name'], 'Vendor'), bold: false),
                              CellText(formatDate(order['created_at']), bold: false, size: 13, color: Palette.of(context).muted),
                              StatusBadge(jstr(order['status_label'], jstr(order['status']))),
                              CellText(formatRwf(order['total_amount_rwf'])),
                            ],
                        ],
                      )
                    : Column(children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          _RecentOrder(order: recent[i], onTap: () => go(AdminRoute(Pages.orders, {'order': jstr(recent[i]['id'])}))),
                        ],
                      ]),
          ),
        ]);
      },
    );
  }
}

/// One thing that needs the admin: a tag, what it is, why, and the button.
class _Alert {
  _Alert(this.tone, this.tag, dynamic value, this.title, this.subtitle, this.action, this.onTap) : count = jint(value);

  final Tone tone;
  final String tag;
  final int count;
  final String Function(int count) title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
}

/// "Needs your attention · Sorted by urgency".
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.alerts});

  final List<_Alert> alerts;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SectionCard(
      title: 'Needs your attention',
      action: Text('Sorted by urgency', style: TextStyle(fontSize: 12.5, color: p.muted)),
      child: alerts.isEmpty
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Tone.green.background(context), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: Tone.green.foreground(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('All clear — nothing is waiting on you right now.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Tone.green.foreground(context))),
                ),
              ]),
            )
          : Column(children: [
              for (var i = 0; i < alerts.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _AlertRow(alert: alerts[i]),
              ],
            ]),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: alert.tone.background(context), borderRadius: BorderRadius.circular(6)),
      child: Text(alert.tag.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: alert.tone.foreground(context))),
    );
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(alert.title(alert.count), style: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 2),
      Text(alert.subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: p.muted)),
    ]);
    final button = OutlinedButton(onPressed: alert.onTap, child: Text(alert.action));
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: phone
          // A phone: tag, text, then the button across the row.
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              tag,
              const SizedBox(height: 10),
              text,
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: button),
            ])
          : Row(children: [
              tag,
              const SizedBox(width: 14),
              Expanded(child: text),
              const SizedBox(width: 12),
              button,
            ]),
    );
  }
}

/// "Live order pipeline": how many orders sit in each stage, as bars.
class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.stages, required this.onMap, this.footer});

  final List<(String, int, Tone)> stages;
  final String? footer;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final top = stages.fold<int>(1, (m, s) => s.$2 > m ? s.$2 : m);
    return SectionCard(
      title: 'Live order pipeline',
      action: SmallButton('Live map', icon: Icons.map_outlined, onPressed: onMap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (label, count, tone) in stages) ...[
          Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
            Text('${formatNumber(count)} order${count == 1 ? '' : 's'}', style: TextStyle(fontSize: 13, color: p.muted)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: count / top,
              minHeight: 9,
              backgroundColor: p.stone100,
              color: tone == Tone.slate ? p.faint : (tone == Tone.amber ? const Color(0xFFD97706) : AppColors.orange),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (footer != null) ...[
          Divider(color: p.border),
          const SizedBox(height: 10),
          Text(footer!, style: TextStyle(fontSize: 12.5, height: 1.45, color: p.muted)),
        ],
      ]),
    );
  }
}

/// Kitchens / delivery workers / customers: a few counts and a full-width link.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.title, required this.metrics, required this.link, required this.onLink});

  final String title;
  final List<(String, String, Color?)> metrics;
  final String link;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SectionCard(
      title: title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (label, value, color) in metrics)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textSecondary))),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color ?? p.text)),
            ]),
          ),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: onLink, child: Text(link)),
      ]),
    );
  }
}

/// A recent order on a phone: number and kitchen, customer and time, then
/// the total and status.
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
              const SizedBox(height: 2),
              Text('${jstr(jmap(order['customer'])['name'], 'Customer')} · ${formatDate(order['created_at'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatRwf(order['total_amount_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 4),
            StatusBadge(jstr(order['status_label'], jstr(order['status']))),
          ]),
        ]),
      ),
    );
  }
}
