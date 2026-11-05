import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../nav/admin_nav.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/maps.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../admin_shell.dart';
import 'assign_driver_sheet.dart';

// `text-red-700` (late by, charge kept) and `text-amber-700` (waiting).
const _red700 = Color(0xFFB91C1C);
const _amber700 = Color(0xFFB45309);

/// Live operations: who is delivering what, where every delivery worker is,
/// and pickups that ran late (the website's AdminDeliveriesPage).
class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key, this.initialTab});

  /// `late` opens the late pickups (the late-pickup alert links here).
  final String? initialTab;

  @override
  State<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends State<DeliveriesPage> {
  late final session = context.read<AdminSession>();
  late String tab = const ['map', 'active', 'late'].contains(widget.initialTab) ? widget.initialTab! : 'map';
  int page = 1;
  int latePage = 1;
  String chargeStatus = '';

  late final mapQuery = Query<Json>(
    () async => jmap(await session.api.liveMap()),
    client: session.client,
    poll: const Duration(seconds: 10),
    enabled: tab == 'map',
  );
  late final activeQuery = Query<Json>(
    () async => jmap(await session.api.liveDeliveries({'page': page, 'limit': 20})),
    client: session.client,
    poll: const Duration(seconds: 15),
    enabled: tab == 'active',
  );
  late final lateQuery = Query<Json>(
    () async => jmap(await session.api.latePickups({'page': latePage, 'limit': 20, 'charge_status': chargeStatus})),
    client: session.client,
    poll: const Duration(seconds: 30),
    enabled: tab == 'late',
  );

  @override
  void dispose() {
    mapQuery.dispose();
    activeQuery.dispose();
    lateQuery.dispose();
    super.dispose();
  }

  void setTab(String next) {
    setState(() => tab = next);
    mapQuery.enabled = next == 'map';
    activeQuery.enabled = next == 'active';
    lateQuery.enabled = next == 'late';
  }

  Future<void> refresh() => switch (tab) {
        'map' => mapQuery.load(silent: true),
        'active' => activeQuery.load(),
        _ => lateQuery.load(),
      };

  /// Order numbers link to the order (`/admin-dashboard/orders?order=…`).
  void openOrder(dynamic orderId) => context.read<ShellNavigator>().go(AdminRoute(Pages.orders, {'order': jstr(orderId)}));

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: refresh, children: [
      const PageHeader(
        title: 'Deliveries',
        description: 'Live operations: who is delivering what, where every delivery worker is, and pickups that ran late.',
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _TabButton(icon: Icons.map_outlined, label: 'Live map', active: tab == 'map', onTap: () => setTab('map')),
        _TabButton(icon: Icons.pedal_bike_outlined, label: 'In progress', active: tab == 'active', onTap: () => setTab('active')),
        _TabButton(icon: Icons.timer_outlined, label: 'Late pickups', active: tab == 'late', onTap: () => setTab('late')),
      ]),
      if (tab == 'map') _mapTab(),
      if (tab == 'active') _activeTab(),
      if (tab == 'late') _lateTab(),
    ]);
  }

  Widget _mapTab() => ListenableBuilder(
        listenable: mapQuery,
        builder: (context, _) {
          final map = mapQuery.data;
          final deliveries = jlist(map?['deliveries']);
          final busy = deliveries.map((d) => jmap(d['driver'])['id']).where((id) => id != null).toSet();
          final free = jlist(map?['drivers']).where((d) => !busy.contains(d['id']) && d['counts_for_dispatch'] == true).length;
          final waiting = deliveries.where((d) => d['driver'] == null).length;
          final height = MediaQuery.sizeOf(context).height * 0.65;
          final pad = isSm(context) ? 12.0 : 8.0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            ResponsiveGrid(children: [
              StatCard(label: 'Deliveries in progress', value: map == null ? '—' : '${deliveries.length}', icon: Icons.pedal_bike_outlined, tone: Tone.blue),
              StatCard(label: 'Waiting for a rider', value: map == null ? '—' : '$waiting', icon: Icons.warning_amber_rounded, tone: waiting > 0 ? Tone.amber : Tone.slate),
              StatCard(label: 'Free delivery workers', value: map == null ? '—' : '$free', hint: 'online, location fresh', icon: Icons.pedal_bike_outlined, tone: Tone.green),
              StatCard(label: 'Kitchens open', value: map == null ? '—' : '${jlist(map['kitchens']).length}', icon: Icons.map_outlined),
            ]),
            SectionCard(
              padding: EdgeInsets.all(pad),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (mapQuery.error != null && map == null)
                  ErrorNote(error: mapQuery.error, onRetry: mapQuery.load)
                else
                  OperationsMap(data: map, height: height < 420 ? 420 : height),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Text(
                    'Refreshes every 10 seconds${map != null ? ' · updated ${formatRelative(map['generated_at'])}' : ''}. Tap a pin for details.',
                    style: TextStyle(fontSize: 11, color: Palette.of(context).faint),
                  ),
                ),
              ]),
            ),
          ], 12));
        },
      );

  /// "Kitchen preparing" / "Ready" and, once ready, how long the worker has left.
  Widget _pickupState(Json delivery) {
    if (const ['picked_up', 'out_for_delivery', 'delivered', 'completed'].contains(delivery['status'])) {
      return Text('Collected', style: TextStyle(fontSize: 12, color: Palette.of(context).faint));
    }
    if (delivery['kitchen_ready'] != true) return const ToneBadge('Kitchen preparing', tone: Tone.amber);
    if (delivery['late_pickup'] != null && delivery['late_pickup'] != false) return const ToneBadge('Late pickup', tone: Tone.red);
    final due = parseDate(delivery['pickup_due_at']);
    if (due == null) return const ToneBadge('Ready', tone: Tone.green);
    final left = (due.difference(DateTime.now()).inSeconds / 60).round();
    return ToneBadge(left > 0 ? 'Ready · $left min to collect' : 'Ready · overdue', tone: left <= 5 ? Tone.red : Tone.green);
  }

  Widget _activeTab() {
    final p = Palette.of(context);
    return SectionCard(
      child: QueryView<Json>(
        query: activeQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.pedal_bike_outlined, title: 'No active deliveries', description: 'Nothing in progress right now.');
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WebTable(
              columns: const [
                WebColumn('Order', nowrap: true),
                WebColumn('Kitchen'),
                WebColumn('Delivery worker'),
                WebColumn('Food / pickup', nowrap: true),
                WebColumn('Status', nowrap: true),
                WebColumn('Updated', nowrap: true),
              ],
              rows: [
                for (final delivery in items)
                  [
                    _OrderLink(jstr(delivery['order_number']), onTap: () => openOrder(delivery['order_id'])),
                    Text(jstr(jmap(delivery['vendor'])['name'], '—'), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                    delivery['driver'] != null
                        ? CellText(jstr(jmap(delivery['driver'])['name']), sub: jstr(jmap(delivery['driver'])['phone']))
                        : Text('Waiting · offered to ${jstr(delivery['offered_to'], '0')}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _amber700)),
                    _pickupState(delivery),
                    StatusBadge(jstr(delivery['status_label'], jstr(delivery['status']))),
                    Text(formatDate(delivery['updated_at']), style: TextStyle(fontSize: 12, color: p.muted)),
                  ],
              ],
            ),
            Pager.of(data, onPage: (next) {
              setState(() => page = next);
              activeQuery.load();
            }),
          ]);
        },
      ),
    );
  }

  Widget _lateTab() {
    return SectionCard(
      title: 'Late pickups',
      description: "Delivery workers who didn't collect the food within the grace period after it was ready. Late pickups are not charged; "
          'if the worker is too late the order goes to another worker. Older records may show charges taken before charges were removed.',
      action: SizedBox(
        width: 176,
        child: WebSelect<String>(
          value: chargeStatus,
          options: const {'': 'All charges', 'pending': 'Charge pending', 'charged': 'Charged', 'waived': 'No charge'},
          onChanged: (value) {
            setState(() {
              chargeStatus = value;
              latePage = 1;
            });
            lateQuery.load();
          },
        ),
      ),
      child: QueryView<Json>(
        query: lateQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.timer_outlined, title: 'No late pickups', description: 'Every collected order was picked up on time.');
          }
          final p = Palette.of(context);
          final pending = jint(data['pending_charges']);
          final waiting = jint(data['still_waiting']);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted), children: [
              TextSpan(text: '$pending late pickup${pending == 1 ? '' : 's'} with a pending charge'),
              if (waiting > 0)
                TextSpan(text: ' · $waiting still waiting at the kitchen — call a nearby worker to take over', style: const TextStyle(color: _red700)),
              const TextSpan(text: '.'),
            ])),
            const SizedBox(height: 12),
            WebTable(
              columns: const [
                WebColumn('Order', nowrap: true),
                WebColumn('Delivery worker'),
                WebColumn('Food ready / due', nowrap: true),
                WebColumn('Late by', nowrap: true),
                WebColumn('Charge'),
                WebColumn('', alignEnd: true, nowrap: true),
              ],
              highlightRows: {for (var i = 0; i < items.length; i++) if (items[i]['still_waiting'] == true) i},
              rows: [for (final row in items) _lateRow(row)],
            ),
            Pager.of(data, onPage: (next) {
              setState(() => latePage = next);
              lateQuery.load();
            }),
          ]);
        },
      ),
    );
  }

  List<Widget> _lateRow(Json row) {
    final p = Palette.of(context);
    final charge = jstr(row['charge_status']);
    final driver = jmap(row['driver']);
    final small = TextStyle(fontSize: 12, height: 1.33, color: p.muted);
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _OrderLink(jstr(row['order_number']), onTap: () => openOrder(row['order_id'])),
        Text(jstr(jmap(row['vendor'])['name']), style: TextStyle(fontSize: 11, color: p.faint)),
      ]),
      CellText(jstr(driver['name'], '—'), sub: jstr(driver['phone'])),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Ready ${formatDate(row['ready_at'])}', style: small),
        Text('Due ${formatDate(row['pickup_due_at'])}', style: small),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${jstr(row['minutes_late'], '—')} min', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _red700)),
        Text(
          row['reassigned_at'] != null
              ? 'Replaced ${formatDate(row['reassigned_at'])}'
              : row['still_waiting'] == true
                  ? 'Still not collected'
                  : 'Collected ${formatDate(row['picked_up_at'])}',
          style: TextStyle(fontSize: 11, color: p.faint),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ToneBadge(
          charge == 'pending' ? 'Pending' : charge == 'charged' ? 'Charged' : 'No charge',
          tone: charge == 'pending' ? Tone.amber : charge == 'charged' ? Tone.red : Tone.slate,
        ),
        if (row['charge_rwf'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${formatNumber(row['charge_rwf'])} RWF kept${row['penalty_percent'] != null ? ' (${jstr(row['penalty_percent'])}%)' : ''}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _red700),
            ),
          ),
        if (charge == 'waived' && jstr(row['note']).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(jstr(row['note']), style: TextStyle(fontSize: 11, color: p.faint))),
      ]),
      row['can_reassign'] == true && session.can('orders:write')
          ? SmallButton('Find nearby worker', primary: true, onPressed: () => showAppSheet(context, AssignDriverSheet(orderId: jstr(row['order_id']))))
          : const SizedBox.shrink(),
    ];
  }
}

/// `inline-flex gap-1.5 px-4 py-2 rounded-xl text-sm font-bold border`;
/// the open tab is `bg-gray-900 text-white`.
class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = active ? (dark ? Colors.white : const Color(0xFF111827)) : p.card;
    final foreground = active ? (dark ? const Color(0xFF111827) : Colors.white) : p.textSecondary;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? background : p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: foreground)),
          ]),
        ),
      ),
    );
  }
}

/// `font-bold text-gray-900 hover:underline` order number.
class _OrderLink extends StatelessWidget {
  const _OrderLink(this.text, {required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: Palette.of(context).text)),
      );
}
