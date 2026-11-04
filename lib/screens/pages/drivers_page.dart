import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/status_sheet.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'vendors_page.dart';

/// Verify, monitor and suspend delivery workers.
class DriversPage extends StatefulWidget {
  const DriversPage({super.key, this.focusId});

  /// Opens this worker's status change straight away.
  final String? focusId;

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  late final session = context.read<AdminSession>();
  String status = '';
  String online = '';
  String search = '';
  int page = 1;

  late final listQuery = Query<Json>(
    () async => jmap(await session.api.listDrivers({'status': status, 'online': online, 'search': search, 'page': page, 'limit': 20})),
    client: session.client,
  );
  late final countsQuery = Query<Json>(() async => jmap(await session.api.driverCounts()), client: session.client);

  @override
  void initState() {
    super.initState();
    if (widget.focusId != null) {
      session.api.getDriver(widget.focusId!).then((result) {
        final driver = jmap(jmap(result)['driver']);
        if (driver.isNotEmpty && mounted) _changeStatus(driver);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    listQuery.dispose();
    countsQuery.dispose();
    super.dispose();
  }

  void apply(VoidCallback change) {
    setState(() {
      change();
      page = 1;
    });
    listQuery.load();
  }

  Future<void> _changeStatus(Json driver) async {
    final result = await showAppSheet<dynamic>(
      context,
      StatusSheet(
        title: 'Change status · ${jstr(driver['name'])}',
        statuses: vendorStatuses,
        current: jstr(driver['verification_status']),
        onSubmit: (payload) => session.api.setDriverStatus(jstr(driver['id']), payload),
      ),
    );
    if (result == null || !mounted) return;
    final released = jint(jmap(result)['released_deliveries']);
    showToast(context, released > 0 ? 'Delivery worker updated. $released delivery(ies) released.' : 'Delivery worker status updated.');
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      onRefresh: () async {
        await Future.wait([listQuery.load(), countsQuery.load(silent: true)]);
      },
      children: [
        const PageHeader(title: 'Delivery Workers', description: 'Verify, monitor and suspend delivery workers.'),
        ListenableBuilder(
          listenable: countsQuery,
          builder: (context, _) {
            final counts = countsQuery.data;
            if (counts == null) return const SizedBox.shrink();
            return ResponsiveGrid(children: [
              StatCard(label: 'Total', value: formatNumber(counts['total'])),
              StatCard(label: 'Online', value: formatNumber(counts['online']), tone: Tone.green),
              StatCard(label: 'Pending', value: formatNumber(counts['pending']), tone: Tone.amber),
              StatCard(label: 'Suspended', value: formatNumber(counts['suspended']), tone: Tone.red),
            ]);
          },
        ),
        SectionCard(
          title: 'Filters',
          child: Column(children: spaced([
            SearchField(hint: 'Search delivery workers by name or phone…', onSubmit: (value) => apply(() => search = value)),
            Row(children: [
              Expanded(
                child: Dropdown<String>(
                  value: status,
                  options: const {'': 'All statuses', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected', 'suspended': 'Suspended'},
                  onChanged: (value) => apply(() => status = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Dropdown<String>(
                  value: online,
                  options: const {'': 'Any availability', 'true': 'Online', 'false': 'Offline'},
                  onChanged: (value) => apply(() => online = value),
                ),
              ),
            ]),
          ])),
        ),
        QueryView<Json>(
          query: listQuery,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const Card(child: EmptyState(icon: Icons.pedal_bike_outlined, title: 'No delivery workers found', description: 'Adjust the filters above.'));
            }
            return RecordList(
              footer: Pager.of(data, onPage: (next) {
                setState(() => page = next);
                listQuery.load();
              }),
              children: [for (final driver in items) _row(driver)],
            );
          },
        ),
      ],
    );
  }

  Widget _row(Json driver) {
    final location = jmap(driver['location']);
    final active = jint(driver['active_deliveries_count']);
    final hasFix = location['updated_at'] != null;
    // Orders are only offered to drivers whose phone reported a position recently.
    final locationLine = hasFix
        ? 'Location ${formatRelative(location['updated_at'])} · ${location['counts_for_dispatch'] == true ? 'Gets nearby orders' : 'Too old for dispatch'}'
        : 'Location never shared';
    return RecordTile(
      title: jstr(driver['name']),
      subtitle: '${toTitle(driver['vehicle_type'])}${jstr(driver['plate_number']).isNotEmpty ? ' · ${jstr(driver['plate_number'])}' : ''}',
      trailing: formatRwf(driver['total_earnings_rwf']),
      badges: [
        StatusBadge(jstr(driver['verification_status'])),
        ToneBadge(driver['is_online'] == true ? 'Online' : 'Offline', tone: driver['is_online'] == true ? Tone.green : Tone.slate),
        if (active > 0) ToneBadge('$active active deliver${active == 1 ? 'y' : 'ies'}', tone: Tone.orange),
      ],
      lines: [
        jstr(driver['phone'], jstr(driver['email'], '—')),
        locationLine,
        '${jint(driver['completed_deliveries'])} deliveries · joined ${formatDate(driver['created_at'], withTime: false)}',
      ],
      actions: [
        if (location['latitude'] != null)
          TextButton.icon(
            onPressed: () => openMaps(location['latitude'], location['longitude']),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Map'),
          ),
        if (session.can('drivers:write'))
          OutlinedButton(onPressed: () => _changeStatus(driver), child: const Text('Change status')),
      ],
    );
  }
}
