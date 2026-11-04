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
            // `grid-cols-2 lg:grid-cols-4 gap-3`.
            return ResponsiveGrid(minWidth: 1, maxColumns: MediaQuery.sizeOf(context).width >= 1024 ? 4 : 2, children: [
              StatCard(label: 'Total', value: formatNumber(counts['total'])),
              StatCard(label: 'Online', value: formatNumber(counts['online'])),
              StatCard(label: 'Pending', value: formatNumber(counts['pending'])),
              StatCard(label: 'Suspended', value: formatNumber(counts['suspended'])),
            ]);
          },
        ),
        _filters(),
        SectionCard(
          child: QueryView<Json>(
            query: listQuery,
            builder: (context, data) {
              final items = jlist(data['items']);
              if (items.isEmpty) {
                return const EmptyState(icon: Icons.pedal_bike_outlined, title: 'No delivery workers found', description: 'Adjust the filters above.');
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                WebTable(
                  columns: const [
                    WebColumn('Delivery worker'),
                    WebColumn('Contact'),
                    WebColumn('Status', nowrap: true),
                    WebColumn('Availability'),
                    WebColumn('Location'),
                    WebColumn('Earnings'),
                    WebColumn('', alignEnd: true, nowrap: true),
                  ],
                  rows: [for (final driver in items) _row(driver)],
                ),
                Pager.of(data, onPage: (next) {
                  setState(() => page = next);
                  listQuery.load();
                }),
              ]);
            },
          ),
        ),
      ],
    );
  }

  /// `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3`, search spanning two columns.
  Widget _filters() {
    final viewport = MediaQuery.sizeOf(context).width;
    final searchBox = WebSearchInput(hint: 'Search delivery workers by name or phone…', onSubmit: (value) => apply(() => search = value));
    final statusSelect = WebSelect<String>(
      value: status,
      options: const {'': 'All statuses', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected', 'suspended': 'Suspended'},
      onChanged: (value) => apply(() => status = value),
    );
    final onlineSelect = WebSelect<String>(
      value: online,
      options: const {'': 'Any availability', 'true': 'Online', 'false': 'Offline'},
      onChanged: (value) => apply(() => online = value),
    );
    return SectionCard(
      title: 'Filters',
      padding: const EdgeInsets.all(16),
      child: viewport >= 1024
          ? Row(children: [
              Expanded(flex: 2, child: searchBox),
              const SizedBox(width: 12),
              Expanded(child: statusSelect),
              const SizedBox(width: 12),
              Expanded(child: onlineSelect),
            ])
          : viewport >= 640
              ? Column(children: spaced([
                  searchBox,
                  Row(children: [Expanded(child: statusSelect), const SizedBox(width: 12), Expanded(child: onlineSelect)]),
                ]))
              : Column(children: spaced([searchBox, statusSelect, onlineSelect])),
    );
  }

  List<Widget> _row(Json driver) {
    final p = Palette.of(context);
    final location = jmap(driver['location']);
    final active = jint(driver['active_deliveries_count']);
    final plate = jstr(driver['plate_number']);
    return [
      CellText(jstr(driver['name']), sub: '${toTitle(driver['vehicle_type'])}${plate.isNotEmpty ? ' · $plate' : ''}'),
      Text(jstr(driver['phone'], jstr(driver['email'], '—')), style: TextStyle(fontSize: 14, color: p.textSecondary)),
      StatusBadge(jstr(driver['verification_status'])),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ToneBadge(driver['is_online'] == true ? 'Online' : 'Offline', tone: driver['is_online'] == true ? Tone.green : Tone.slate),
        if (active > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$active active deliver${active == 1 ? 'y' : 'ies'}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC2410C)),
            ),
          ),
      ]),
      // Orders are only offered to drivers whose phone reported a position recently.
      location['updated_at'] != null
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(formatRelative(location['updated_at']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
              Text(
                location['counts_for_dispatch'] == true ? 'Gets nearby orders' : 'Too old for dispatch',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: location['counts_for_dispatch'] == true ? const Color(0xFF047857) : p.faint),
              ),
              if (location['latitude'] != null)
                InkWell(
                  onTap: () => openMaps(location['latitude'], location['longitude']),
                  child: const Text('Map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0369A1))),
                ),
            ])
          : Text('Never shared', style: TextStyle(fontSize: 12, color: p.faint)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(formatRwf(driver['total_earnings_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        Text(
          '${jint(driver['completed_deliveries'])} deliveries · joined ${formatDate(driver['created_at'], withTime: false)}',
          style: TextStyle(fontSize: 11, color: p.faint),
        ),
      ]),
      session.can('drivers:write') ? SmallButton('Change status', onPressed: () => _changeStatus(driver)) : const SizedBox.shrink(),
    ];
  }
}
