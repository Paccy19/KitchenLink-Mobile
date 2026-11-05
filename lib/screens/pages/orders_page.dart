import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/maps.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'assign_driver_sheet.dart';

const orderStatuses = ['placed', 'confirmed', 'preparing', 'ready', 'assigned', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled'];
const _closed = ['delivered', 'cancelled'];

/// Search, override statuses and reassign delivery workers.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, this.focusId});

  /// Opens this order straight away (notification / deep link).
  final String? focusId;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late final session = context.read<AdminSession>();
  String status = '';
  String fulfillment = '';
  String search = '';
  String from = '';
  String to = '';
  int page = 1;

  late final query = Query<Json>(
    () async => jmap(await session.api.listOrders({
      'status': status,
      'fulfillment': fulfillment,
      'search': search,
      'from': from.isEmpty ? '' : '${from}T00:00:00',
      'to': to.isEmpty ? '' : '${to}T23:59:59',
      'page': page,
      'limit': 20,
    })),
    client: session.client,
  );

  @override
  void initState() {
    super.initState();
    if (widget.focusId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openOrder(context, widget.focusId!));
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void apply(VoidCallback change) {
    setState(() {
      change();
      page = 1;
    });
    query.load();
  }

  @override
  Widget build(BuildContext context) {
    final search = WebSearchInput(hint: 'Search order number, customer…', onSubmit: (value) => apply(() => this.search = value));
    final statusSelect = WebSelect<String>(
      value: status,
      options: {'': 'All statuses', for (final s in orderStatuses) s: toTitle(s)},
      onChanged: (value) => apply(() => status = value),
    );
    final fulfillmentSelect = WebSelect<String>(
      value: fulfillment,
      options: const {'': 'Delivery & pickup', 'delivery': 'Delivery only', 'pickup': 'Customer pickup only'},
      onChanged: (value) => apply(() => fulfillment = value),
    );
    final dates = Row(children: [
      Expanded(child: WebDateInput(value: from, onChanged: (value) => apply(() => from = value))),
      const SizedBox(width: 8),
      Expanded(child: WebDateInput(value: to, onChanged: (value) => apply(() => to = value))),
    ]);

    return PageBody(onRefresh: query.load, children: [
      const PageHeader(title: 'Orders', description: 'Search, override statuses and reassign delivery workers.'),
      SectionCard(
        title: 'Filters',
        padding: const EdgeInsets.all(16),
        // `grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3`, search spanning two columns.
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 860) {
            return Row(children: [
              Expanded(flex: 2, child: search),
              const SizedBox(width: 12),
              Expanded(child: statusSelect),
              const SizedBox(width: 12),
              Expanded(child: fulfillmentSelect),
              const SizedBox(width: 12),
              Expanded(child: dates),
            ]);
          }
          if (constraints.maxWidth >= 560) {
            return Column(children: spaced([
              search,
              Row(children: [Expanded(child: statusSelect), const SizedBox(width: 12), Expanded(child: fulfillmentSelect)]),
              Row(children: [Expanded(child: dates), const SizedBox(width: 12), const Spacer()]),
            ]));
          }
          return Column(children: spaced([search, statusSelect, fulfillmentSelect, dates]));
        }),
      ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const EmptyState(icon: Icons.assignment_outlined, title: 'No orders found', description: 'Adjust the filters above.');
            }
            final p = Palette.of(context);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WebTable(
                columns: const [
                  WebColumn('Order', nowrap: true),
                  WebColumn('Vendor / Customer'),
                  WebColumn('Total', nowrap: true),
                  WebColumn('Status', nowrap: true),
                  WebColumn('Placed', nowrap: true),
                  WebColumn('', alignEnd: true, nowrap: true),
                ],
                rows: [
                  for (final row in items)
                    [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CellText(jstr(row['order_number']), sub: '${toTitle(row['payment_method'])} · ${jstr(row['payment_status'])}'),
                        const SizedBox(height: 4),
                        ToneBadge(row['fulfillment'] == 'pickup' ? 'Pickup' : 'Delivery', tone: row['fulfillment'] == 'pickup' ? Tone.violet : Tone.blue),
                      ]),
                      CellText(jstr(jmap(row['vendor'])['name'], '—'), sub: jstr(jmap(row['customer'])['name'], '—'), color: p.text),
                      CellText(formatRwf(row['total_amount_rwf'])),
                      StatusBadge(jstr(row['status_label'], jstr(row['status']))),
                      Text(formatDate(row['created_at']), style: TextStyle(fontSize: 12, color: p.muted)),
                      SmallButton('Details', onPressed: () => openOrder(context, jstr(row['id']))),
                    ],
                ],
              ),
              Pager.of(data, onPage: (next) {
                setState(() => page = next);
                query.load();
              }),
            ]);
          },
        ),
      ),
    ]);
  }
}

void openOrder(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: id)));
}

/// One order: parties, money, pickup / delivery state, live map, items, history
/// and the support actions (set status, assign a worker, cancel).
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.getOrder(widget.orderId)), client: session.client);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final order = jmap(query.data?['order']);
        return Scaffold(
          appBar: AppBar(title: Text(order.isEmpty ? 'Order details' : 'Order ${jstr(order['order_number'])}')),
          body: QueryView<Json>(query: query, builder: (context, data) => _body(context, data)),
        );
      },
    );
  }

  Widget _body(BuildContext context, Json data) {
    final order = jmap(data['order']);
    final delivery = data['delivery'] is Map ? jmap(data['delivery']) : null;
    final dispatch = data['dispatch'] is Map ? jmap(data['dispatch']) : null;
    final isPickup = order['fulfillment'] == 'pickup';
    final status = jstr(order['status']);
    final closed = _closed.contains(status);
    final orderType = jstr(order['order_type']);

    return PageBody(onRefresh: query.load, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusBadge(jstr(order['status_label'], status)),
        ToneBadge('Payment: ${toTitle(order['payment_status'])}', tone: statusTone(jstr(order['payment_status']))),
        Hint('Placed ${formatDate(order['created_at'])}'),
      ]),
      ResponsiveGrid(minWidth: 140, children: [
        InfoTile('Vendor', jstr(jmap(order['vendor'])['name'], '—')),
        InfoTile('Customer', jstr(jmap(order['customer'])['name'], '—')),
        InfoTile('How', jstr(order['fulfillment_label'], 'Delivery')),
        if (!isPickup) InfoTile('Delivery worker', jstr(jmap(order['driver'])['name'], 'Unassigned')),
        InfoTile('Subtotal', formatRwf(order['subtotal_rwf'])),
        InfoTile('Delivery fee', isPickup ? 'None (pickup)' : formatRwf(order['delivery_fee_rwf'])),
        InfoTile('Total', formatRwf(order['total_amount_rwf'])),
        InfoTile('Order type', jstr(order['order_type_label'], toTitle(orderType.isEmpty ? 'immediate' : orderType))),
        if (order['scheduled_for'] != null) InfoTile('Scheduled for', formatDate(order['scheduled_for'])),
        if (jstr(order['special_text']).isNotEmpty) InfoTile('Special', jstr(order['special_text'])),
      ]),
      if (isPickup && order['pickup'] is Map) _PickupSection(pickup: jmap(order['pickup']), status: status),
      if (!isPickup && delivery != null) _DeliverySection(delivery: delivery, dispatch: dispatch),
      if (!isPickup && delivery == null && !closed)
        Note(
          orderType.isNotEmpty && orderType != 'immediate'
              ? 'Scheduled order: delivery workers are offered it when the kitchen marks it ready.'
              : 'No delivery yet — it is created and offered to nearby delivery workers once the order is paid.',
          tone: Tone.slate,
        ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('Items'),
        RecordList(children: [
          for (final item in jlist(order['items']))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(child: Text('${jint(item['quantity'])}× ${jstr(item['name'])}')),
                Text(formatRwf(item['subtotal_rwf']), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('History'),
        for (final entry in jlist(order['status_history']))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: CircleAvatar(radius: 3, backgroundColor: Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(jstr(entry['label']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Hint('${formatDate(entry['at'])}${jstr(entry['note']).isNotEmpty ? ' · ${jstr(entry['note'])}' : ''}'),
                ]),
              ),
            ]),
          ),
      ]),
      if (session.can('orders:write'))
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: () => showAppSheet(context, _SetStatusSheet(orderId: widget.orderId)), child: const Text('Set status')),
          if (!isPickup)
            OutlinedButton(
              onPressed: closed || const ['picked_up', 'out_for_delivery', 'delivered', 'completed'].contains(delivery?['status'])
                  ? null
                  : () => showAppSheet(context, AssignDriverSheet(orderId: widget.orderId)),
              child: Text(order['driver'] != null ? 'Reassign to a nearby worker' : 'Assign a nearby worker'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: closed ? null : () => showAppSheet(context, _CancelSheet(orderId: widget.orderId)),
            child: const Text('Cancel order'),
          ),
        ]),
    ]);
  }
}

/// Pickup orders: where collection stands (the code itself is never shown).
class _PickupSection extends StatelessWidget {
  const _PickupSection({required this.pickup, required this.status});

  final Json pickup;
  final String status;

  @override
  Widget build(BuildContext context) {
    final collected = pickup['collected_at'] != null;
    return SectionCard(
      title: 'Customer pickup',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ResponsiveGrid(minWidth: 140, children: [
          InfoTile('Pickup code sent', pickup['code_sent_at'] != null ? formatDate(pickup['code_sent_at']) : 'Not yet'),
          InfoTile('Wrong codes', '${jint(pickup['wrong_attempts'])} of ${jint(pickup['max_attempts'])}'),
          InfoTile('Collected', collected ? formatDate(pickup['collected_at']) : status == 'ready' ? 'Waiting for customer' : '—'),
          InfoTile('State', pickup['locked'] == true ? 'Locked (too many wrong codes)' : collected ? 'Completed' : 'Open'),
        ]),
        if (pickup['locked'] == true && !collected) ...[
          const SizedBox(height: 10),
          const Note('The vendor entered too many wrong codes. Check with the customer, then use "Set status → Delivered" to complete it.'),
        ],
      ]),
    );
  }
}

/// Delivery orders: dispatch record, pickup clock and the live map.
class _DeliverySection extends StatelessWidget {
  const _DeliverySection({required this.delivery, required this.dispatch});

  final Json delivery;
  final Json? dispatch;

  @override
  Widget build(BuildContext context) {
    final late = delivery['late_pickup'] is Map ? jmap(delivery['late_pickup']) : null;
    final offers = jlist(dispatch?['offers']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
      SectionCard(
        title: 'Delivery',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
          ResponsiveGrid(minWidth: 140, children: [
            InfoTile('Delivery status', jstr(delivery['status_label'], toTitle(delivery['status']))),
            InfoTile('Food', delivery['kitchen_ready'] == true ? 'Ready ${formatDate(delivery['ready_at'])}' : 'Kitchen preparing'),
            InfoTile('Accepted', delivery['assigned_at'] != null ? formatDate(delivery['assigned_at']) : 'Not yet'),
            InfoTile('Collect by', delivery['pickup_due_at'] != null ? formatDate(delivery['pickup_due_at']) : '—'),
            InfoTile('Picked up', delivery['picked_up_at'] != null ? formatDate(delivery['picked_up_at']) : '—'),
            InfoTile('Delivered', delivery['completed_at'] != null ? formatDate(delivery['completed_at']) : '—'),
            InfoTile('Rider earns', formatRwf(delivery['promised_earnings_rwf'])),
            InfoTile('Trip', delivery['route_distance_km'] != null ? '${jstr(delivery['route_distance_km'])} km' : '—'),
          ]),
          for (final record in jlist(dispatch?['replaced_late']))
            Hint('${jstr(record['driver_name'])} was replaced${record['reassigned_at'] != null ? ' ${formatDate(record['reassigned_at'])}' : ''} for '
                'being late${record['minutes_late'] != null ? ' (${jstr(record['minutes_late'])} min)' : ''} · charge ${jstr(record['charge_status'])}'),
          if (late != null)
            Note(
              'Late pickup${late['minutes_late'] != null ? ' — collected ${jstr(late['minutes_late'])} min late' : ' — not collected within the grace period'}. '
              'Charge: ${jstr(late['charge_status'])}.',
            ),
          if (dispatch != null) ...[
            Hint('Offered to ${offers.length} delivery worker${offers.length == 1 ? '' : 's'} within ${jstr(dispatch!['radius_km'])} km'
                '${dispatch!['last_broadcast_at'] != null ? ' · last broadcast ${formatDate(dispatch!['last_broadcast_at'])}' : ''}'),
            if (offers.isEmpty)
              Hint('No delivery worker was in range yet. Open orders are re-offered every minute.', color: Tone.amber.foreground(context))
            else
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final offer in offers)
                  ToneBadge(
                    '${jstr(offer['driver_name'])} · ${switch (offer['response']) {
                      'accepted' => 'accepted',
                      'cancelled' => 'taken by another',
                      'rejected' => 'declined',
                      _ => 'offered',
                    }}',
                    tone: offer['response'] == 'accepted' ? Tone.green : offer['response'] == 'rejected' ? Tone.red : Tone.slate,
                  ),
              ]),
          ],
        ], 10)),
      ),
      DeliveryLive(deliveryId: jstr(delivery['id'])),
    ]));
  }
}

/// The same live view the customer has — the rider moving on the map, the
/// road route and the ETA — while the delivery runs. Refreshes every 5 seconds.
class DeliveryLive extends StatefulWidget {
  const DeliveryLive({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<DeliveryLive> createState() => _DeliveryLiveState();
}

class _DeliveryLiveState extends State<DeliveryLive> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(
    () async => jmap(await session.api.deliveryLive(widget.deliveryId)),
    poll: const Duration(seconds: 5),
    enabled: widget.deliveryId.isNotEmpty,
  );

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final live = query.data;
        if (live == null || live['active'] != true) return const SizedBox.shrink();
        final driver = jmap(live['driver']);
        final fix = jmap(driver['location']);
        final route = live['route'] is Map ? jmap(live['route']) : null;
        final kitchen = jmap(live['kitchen']);
        final destination = jmap(live['destination']);
        LatLng? at(Json point) => point['latitude'] is num && point['longitude'] is num
            ? LatLng(jnum(point['latitude']).toDouble(), jnum(point['longitude']).toDouble())
            : null;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Live · ${jstr(live['phase_label'])}${driver.isNotEmpty ? ' · ${jstr(driver['name'])}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Hint('${route != null ? '${formatMinutes(jnum(route['duration_s']))} · ${formatDistance(jnum(route['distance_m']))} left' : 'No position yet'}'
                    '${fix.isNotEmpty ? ' · location ${formatRelative(fix['updated_at'])}${fix['stale'] == true ? ' (stale)' : ''}' : ''}'),
              ]),
            ),
            LiveRouteMap(
              rider: at(fix),
              kitchen: at(kitchen),
              destination: at(destination),
              geometry: route?['geometry'] as List?,
              height: 280,
            ),
          ]),
        );
      },
    );
  }
}

class _SetStatusSheet extends StatefulWidget {
  const _SetStatusSheet({required this.orderId});

  final String orderId;

  @override
  State<_SetStatusSheet> createState() => _SetStatusSheetState();
}

class _SetStatusSheetState extends State<_SetStatusSheet> with BusyState {
  String status = 'confirmed';
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return SheetScaffold(
      title: 'Set order status',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Apply',
          busy: busy,
          onPressed: () async {
            final ok = await run(() => api.updateOrderStatus(widget.orderId, {'status': status, 'note': note.text}));
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ],
      children: [
        Dropdown<String>(
          label: 'Status',
          value: status,
          options: {for (final s in orderStatuses) s: toTitle(s)},
          onChanged: (value) => setState(() => status = value),
        ),
        TextField(controller: note, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Note (optional)')),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.orderId});

  final String orderId;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> with BusyState {
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return SheetScaffold(
      title: 'Cancel order',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Keep order')),
        BusyButton(
          label: 'Cancel order',
          busyLabel: 'Cancelling…',
          danger: true,
          busy: busy,
          onPressed: () async {
            final ok = await run(() => api.cancelOrder(widget.orderId, {'reason': reason.text}));
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ],
      children: [
        TextField(
          controller: reason,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Reason', hintText: 'Why is this order being cancelled?'),
        ),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
