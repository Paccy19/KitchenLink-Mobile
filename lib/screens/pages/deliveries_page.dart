import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/maps.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'assign_driver_sheet.dart';
import 'orders_page.dart';

/// Live operations: who is delivering what, where every delivery worker is,
/// and pickups that ran late.
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

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: refresh, children: [
      const PageHeader(
        title: 'Deliveries',
        description: 'Live operations: who is delivering what, where every delivery worker is, and pickups that ran late.',
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'map', label: Text('Live map'), icon: Icon(Icons.map_outlined)),
          ButtonSegment(value: 'active', label: Text('In progress'), icon: Icon(Icons.pedal_bike_outlined)),
          ButtonSegment(value: 'late', label: Text('Late'), icon: Icon(Icons.timer_outlined)),
        ],
        selected: {tab},
        onSelectionChanged: (value) => setTab(value.first),
      ),
      if (tab == 'map') ..._mapTab(),
      if (tab == 'active') _activeTab(),
      if (tab == 'late') _lateTab(),
    ]);
  }

  List<Widget> _mapTab() => [
        ListenableBuilder(
          listenable: mapQuery,
          builder: (context, _) {
            final map = mapQuery.data;
            final deliveries = jlist(map?['deliveries']);
            final busy = deliveries.map((d) => jmap(d['driver'])['id']).where((id) => id != null).toSet();
            final free = jlist(map?['drivers']).where((d) => !busy.contains(d['id']) && d['counts_for_dispatch'] == true).length;
            final waiting = deliveries.where((d) => d['driver'] == null).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              ResponsiveGrid(children: [
                StatCard(label: 'Deliveries in progress', value: map == null ? '—' : '${deliveries.length}', icon: Icons.pedal_bike_outlined, tone: Tone.blue),
                StatCard(label: 'Waiting for a rider', value: map == null ? '—' : '$waiting', icon: Icons.warning_amber_rounded, tone: waiting > 0 ? Tone.amber : Tone.slate),
                StatCard(label: 'Free delivery workers', value: map == null ? '—' : '$free', hint: 'online, location fresh', icon: Icons.pedal_bike_outlined, tone: Tone.green),
                StatCard(label: 'Kitchens open', value: map == null ? '—' : '${jlist(map['kitchens']).length}', icon: Icons.map_outlined),
              ]),
              if (mapQuery.error != null && map == null) ErrorNote(error: mapQuery.error, onRetry: mapQuery.load) else OperationsMap(data: map),
              Hint('Refreshes every 10 seconds${map != null ? ' · updated ${formatRelative(map['generated_at'])}' : ''}. Tap a pin for details.'),
            ]));
          },
        ),
      ];

  Widget _pickupState(Json delivery) {
    if (const ['picked_up', 'out_for_delivery', 'delivered', 'completed'].contains(delivery['status'])) return const ToneBadge('Collected');
    if (delivery['kitchen_ready'] != true) return const ToneBadge('Kitchen preparing', tone: Tone.amber);
    if (delivery['late_pickup'] != null && delivery['late_pickup'] != false) return const ToneBadge('Late pickup', tone: Tone.red);
    final due = parseDate(delivery['pickup_due_at']);
    if (due == null) return const ToneBadge('Ready', tone: Tone.green);
    final left = (due.difference(DateTime.now()).inSeconds / 60).round();
    return ToneBadge(left > 0 ? 'Ready · $left min to collect' : 'Ready · overdue', tone: left <= 5 ? Tone.red : Tone.green);
  }

  Widget _activeTab() => QueryView<Json>(
        query: activeQuery,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return const Card(child: EmptyState(icon: Icons.pedal_bike_outlined, title: 'No active deliveries', description: 'Nothing in progress right now.'));
          }
          return RecordList(
            footer: Pager.of(data, onPage: (next) {
              setState(() => page = next);
              activeQuery.load();
            }),
            children: [
              for (final delivery in items)
                RecordTile(
                  title: jstr(delivery['order_number']),
                  subtitle: jstr(jmap(delivery['vendor'])['name'], '—'),
                  badges: [StatusBadge(jstr(delivery['status_label'], jstr(delivery['status']))), _pickupState(delivery)],
                  lines: [
                    delivery['driver'] != null
                        ? 'Rider: ${jstr(jmap(delivery['driver'])['name'])} · ${jstr(jmap(delivery['driver'])['phone'])}'
                        : 'Waiting · offered to ${jstr(delivery['offered_to'], '0')}',
                    'Updated ${formatDate(delivery['updated_at'])}',
                  ],
                  onTap: () => openOrder(context, jstr(delivery['order_id'])),
                ),
            ],
          );
        },
      );

  Widget _lateTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        const Hint(
          "Delivery workers who didn't collect the food within the grace period after it was ready. Late pickups are not charged; "
          'if the worker is too late the order goes to another worker. Older records may show charges taken before charges were removed.',
        ),
        Dropdown<String>(
          label: 'Filter by charge',
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
        QueryView<Json>(
          query: lateQuery,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const Card(child: EmptyState(icon: Icons.timer_outlined, title: 'No late pickups', description: 'Every collected order was picked up on time.'));
            }
            final pending = jint(data['pending_charges']);
            final waiting = jint(data['still_waiting']);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
              Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600), children: [
                TextSpan(text: '$pending late pickup${pending == 1 ? '' : 's'} with a pending charge'),
                if (waiting > 0)
                  TextSpan(
                    text: ' · $waiting still waiting at the kitchen — call a nearby worker to take over',
                    style: TextStyle(color: Tone.red.foreground(context)),
                  ),
                const TextSpan(text: '.'),
              ])),
              RecordList(
                footer: Pager.of(data, onPage: (next) {
                  setState(() => latePage = next);
                  lateQuery.load();
                }),
                children: [for (final row in items) _lateRow(row)],
              ),
            ]));
          },
        ),
      ]));

  Widget _lateRow(Json row) {
    final charge = jstr(row['charge_status']);
    final driver = jmap(row['driver']);
    return RecordTile(
      highlight: row['still_waiting'] == true,
      title: jstr(row['order_number']),
      subtitle: jstr(jmap(row['vendor'])['name']),
      trailing: '${jstr(row['minutes_late'], '—')} min late',
      badges: [
        ToneBadge(
          charge == 'pending' ? 'Pending' : charge == 'charged' ? 'Charged' : 'No charge',
          tone: charge == 'pending' ? Tone.amber : charge == 'charged' ? Tone.red : Tone.slate,
        ),
      ],
      lines: [
        'Rider: ${jstr(driver['name'], '—')}${jstr(driver['phone']).isNotEmpty ? ' · ${jstr(driver['phone'])}' : ''}',
        'Ready ${formatDate(row['ready_at'])} · due ${formatDate(row['pickup_due_at'])}',
        row['reassigned_at'] != null
            ? 'Replaced ${formatDate(row['reassigned_at'])}'
            : row['still_waiting'] == true
                ? 'Still not collected'
                : 'Collected ${formatDate(row['picked_up_at'])}',
        if (row['charge_rwf'] != null)
          '${formatNumber(row['charge_rwf'])} RWF kept${row['penalty_percent'] != null ? ' (${jstr(row['penalty_percent'])}%)' : ''}',
        if (charge == 'waived' && jstr(row['note']).isNotEmpty) jstr(row['note']),
      ],
      onTap: () => openOrder(context, jstr(row['order_id'])),
      actions: [
        if (row['can_reassign'] == true && session.can('orders:write'))
          FilledButton(
            onPressed: () => showAppSheet(context, AssignDriverSheet(orderId: jstr(row['order_id']))),
            child: const Text('Find nearby worker'),
          ),
      ],
    );
  }
}
