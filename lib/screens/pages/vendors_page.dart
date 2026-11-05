import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../config.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/maps.dart';
import '../../ui/open_document.dart' as document;
import '../../ui/query.dart';
import '../../ui/status_sheet.dart';
import '../../ui/theme.dart';
import '../../ui/vendor_types.dart';
import '../../ui/widgets.dart';

const vendorStatuses = ['pending', 'approved', 'rejected', 'suspended'];

Future<void> openMaps(dynamic lat, dynamic lng) =>
    launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication);

/// Approve, suspend and inspect marketplace kitchens.
class VendorsPage extends StatefulWidget {
  const VendorsPage({super.key, this.focusId});

  final String? focusId;

  @override
  State<VendorsPage> createState() => _VendorsPageState();
}

class _VendorsPageState extends State<VendorsPage> {
  late final session = context.read<AdminSession>();
  String status = '';
  String search = '';
  List<String> types = [];
  bool groupByType = false;
  int page = 1;

  late final listQuery = Query<Json>(
    () async => jmap(await session.api.listVendors({
      'status': status,
      'search': search,
      'vendor_type': types.isEmpty ? null : types.join(','),
      'page': page,
      'limit': 20,
    })),
    client: session.client,
  );
  late final countsQuery = Query<Json>(() async => jmap(await session.api.vendorCounts()), client: session.client);

  @override
  void initState() {
    super.initState();
    if (widget.focusId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openVendor(widget.focusId!));
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

  void _openVendor(String id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorDetailScreen(vendorId: id)));

  Future<void> _changeStatus(Json vendor) async {
    final docs = jlist(vendor['verification_documents']);
    final result = await showAppSheet<dynamic>(
      context,
      StatusSheet(
        title: 'Change status · ${jstr(vendor['name'])}',
        statuses: vendorStatuses,
        current: jstr(vendor['status']),
        approveBlocked: vendor['status'] != 'approved' && docs.isNotEmpty && vendor['documents_reviewed_at'] == null,
        onSubmit: (payload) => session.api.setVendorStatus(jstr(vendor['id']), payload),
      ),
    );
    if (result != null && mounted) showToast(context, _statusToast(result));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final searchBox = WebSearchInput(hint: 'Search vendors by name…', onSubmit: (value) => apply(() => search = value));
    final statusSelect = WebSelect<String>(
      value: status,
      options: const {'': 'All statuses', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected', 'suspended': 'Suspended'},
      onChanged: (value) => apply(() => status = value),
    );
    final viewport = MediaQuery.sizeOf(context).width;

    return PageBody(
      onRefresh: () async {
        await Future.wait([listQuery.load(), countsQuery.load(silent: true)]);
      },
      children: [
        const PageHeader(title: 'Vendors', description: 'Approve, suspend and inspect marketplace kitchens.'),
        ListenableBuilder(
          listenable: countsQuery,
          builder: (context, _) {
            final counts = countsQuery.data;
            if (counts == null) return const SizedBox.shrink();
            // `grid-cols-2 lg:grid-cols-5 gap-3`.
            return ResponsiveGrid(minWidth: 1, maxColumns: viewport >= 1024 ? 5 : 2, children: [
              StatCard(label: 'Total', value: formatNumber(counts['total'])),
              StatCard(label: 'Pending', value: formatNumber(counts['pending'])),
              StatCard(label: 'Approved', value: formatNumber(counts['approved'])),
              StatCard(label: 'Rejected', value: formatNumber(counts['rejected'])),
              StatCard(label: 'Suspended', value: formatNumber(counts['suspended'])),
            ]);
          },
        ),
        SectionCard(
          title: 'Filters',
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`, search spanning two columns.
            if (viewport >= 1024)
              Row(children: [Expanded(flex: 2, child: searchBox), const SizedBox(width: 12), Expanded(child: statusSelect)])
            else if (viewport >= 640)
              Column(children: spaced([searchBox, Row(children: [Expanded(child: statusSelect), const SizedBox(width: 12), const Spacer()])]))
            else
              Column(children: spaced([searchBox, statusSelect])),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: listQuery,
              builder: (context, _) => VendorTypeFilter(
                value: types,
                counts: _typeCounts(listQuery.data),
                onChanged: (codes) => apply(() => types = codes),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => groupByType = !groupByType),
              child: Row(children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: groupByType,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) => setState(() => groupByType = value ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Group the list by vendor type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textSecondary)),
                ),
              ]),
            ),
          ]),
        ),
        SectionCard(
          child: QueryView<Json>(
            query: listQuery,
            builder: (context, data) {
              var items = jlist(data['items']);
              if (items.isEmpty) {
                return const EmptyState(icon: Icons.storefront_outlined, title: 'No vendors found', description: 'Adjust the filters above.');
              }
              final typeCounts = _typeCounts(data);
              if (groupByType) {
                int order(Json v) => vendorTypes.indexWhere((t) => t.code == vendorTypeOf(v['vendor_type']).code);
                items = [...items]..sort((a, b) => order(a).compareTo(order(b)));
              }
              // A header row before each type when grouped.
              final groups = <int, Widget>{};
              if (groupByType) {
                for (var i = 0; i < items.length; i++) {
                  final code = vendorTypeOf(items[i]['vendor_type']).code;
                  if (i > 0 && vendorTypeOf(items[i - 1]['vendor_type']).code == code) continue;
                  final onPage = items.where((row) => vendorTypeOf(row['vendor_type']).code == code).length;
                  groups[i] = Row(mainAxisSize: MainAxisSize.min, children: [
                    VendorTypeBadge(code),
                    const SizedBox(width: 8),
                    Text(
                      softWrap: false,
                      '$onPage on this page${typeCounts[code] != null ? ' · ${typeCounts[code]} in total' : ''}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted),
                    ),
                  ]);
                }
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                WebTable(
                  columns: const [
                    WebColumn('Vendor'),
                    WebColumn('Contact'),
                    WebColumn('Status', nowrap: true),
                    WebColumn('Sales'),
                    WebColumn('Joined'),
                    WebColumn('', alignEnd: true, nowrap: true),
                  ],
                  groupRows: groups,
                  rows: [for (final vendor in items) _vendorRow(vendor)],
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

  Map<String, int> _typeCounts(Json? data) => {
        for (final row in jlist(data?['type_counts'])) jstr(row['code']): jint(row['count']),
      };

  List<Widget> _vendorRow(Json vendor) {
    final p = Palette.of(context);
    final request = vendor['vendor_type_request'] is Map ? jmap(vendor['vendor_type_request']) : null;
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(jstr(vendor['name']), style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          VendorTypeBadge(vendor['vendor_type'], small: true),
          if (jmap(vendor['nationwide'])['enabled'] == true) const ToneBadge('Nationwide', tone: Tone.violet),
          if (request != null) ToneBadge('Wants ${jstr(request['vendor_type_label'])}', tone: Tone.amber),
        ]),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(jstr(vendor['phone'], '—'), style: TextStyle(fontSize: 14, color: p.textSecondary)),
        Text(jstr(vendor['neighborhood']), style: TextStyle(fontSize: 11, color: p.faint)),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        StatusBadge(jstr(vendor['status'])),
        const SizedBox(width: 4),
        ToneBadge(vendor['is_open'] == true ? 'Store open' : 'Store closed', tone: vendor['is_open'] == true ? Tone.green : Tone.slate),
      ]),
      Text(formatRwf(vendor['total_sales_rwf']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textSecondary)),
      Text(formatDate(vendor['created_at'], withTime: false), style: TextStyle(fontSize: 12, color: p.muted)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        SmallButton('View', ghost: true, onPressed: () => _openVendor(jstr(vendor['id']))),
        if (session.can('vendors:write')) ...[const SizedBox(width: 6), SmallButton('Status', onPressed: () => _changeStatus(vendor))],
      ]),
    ];
  }
}

String _statusToast(dynamic result) {
  final cancelled = jint(jmap(result)['cancelled_orders']);
  return cancelled > 0 ? 'Vendor updated. $cancelled open order(s) cancelled.' : 'Vendor status updated.';
}

/// One kitchen: money, type and nationwide settings, location, verification
/// documents (each must be opened before they can be marked reviewed), and
/// recent orders.
class VendorDetailScreen extends StatefulWidget {
  const VendorDetailScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.getVendor(widget.vendorId)), client: session.client);
  final viewedDocs = <int>{};
  String docError = '';
  String? newType;
  bool busy = false;
  Object? actionError;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> act(Future<dynamic> Function() action, String Function(dynamic result) message) async {
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      final result = await action();
      if (mounted) showToast(context, message(result));
    } catch (err) {
      if (mounted) setState(() => actionError = err);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Private documents open with the admin's sign-in (they have no public link).
  Future<void> openDocument(Json doc, int index) async {
    setState(() => docError = '');
    try {
      final url = jstr(doc['url']);
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        final (bytes, type) = await session.client.file(jstr(doc['download_path']));
        if (type.startsWith('image/')) {
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(jstr(doc['label'], 'Document ${index + 1}'))),
              body: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes))),
            ),
          ));
        } else {
          await document.openDocument(bytes, type.split(';').first, 'vendor-document-${widget.vendorId}-$index');
        }
      }
      setState(() => viewedDocs.add(index));
    } catch (err) {
      final message = ErrorNote.messageOf(err);
      setState(() => docError = message.isEmpty || message == 'Something went wrong.' ? 'Could not open the document.' : message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(jstr(jmap(query.data?['vendor'])['name'], 'Vendor details'))),
        body: QueryView<Json>(query: query, builder: (context, data) => _body(data)),
      ),
    );
  }

  Widget _body(Json data) {
    final vendor = jmap(data['vendor']);
    final canWrite = session.can('vendors:write');
    final documents = jlist(vendor['verification_documents']);
    final reviewed = vendor['documents_reviewed_at'] != null;
    final allViewed = documents.isNotEmpty && List.generate(documents.length, (i) => i).every(viewedDocs.contains);
    final reason = jstr(vendor['suspension_reason'], jstr(vendor['rejection_reason']));
    final recent = jlist(data['recent_orders']);

    return PageBody(onRefresh: query.load, children: [
      ResponsiveGrid(minWidth: 140, children: [
        InfoTile('Status', '', child: StatusBadge(jstr(vendor['status']))),
        InfoTile('Type', '', child: VendorTypeBadge(vendor['vendor_type'])),
        InfoTile('Rating', jstr(vendor['rating'], '—')),
        InfoTile('Total Sales', formatRwf(vendor['total_sales_rwf'])),
        InfoTile('Balance', formatRwf(vendor['available_balance_rwf'])),
        InfoTile('Phone', jstr(vendor['phone'], '—')),
      ]),
      _typeCard(vendor, canWrite),
      _nationwideCard(vendor, canWrite),
      _locationCard(vendor),
      if (reason.isNotEmpty) Note(reason),
      SectionCard(
        title: 'Verification documents',
        action: reviewed
            ? const ToneBadge('Reviewed', tone: Tone.green, icon: Icons.verified_user_outlined)
            : const ToneBadge('Not reviewed', tone: Tone.amber, icon: Icons.gpp_maybe_outlined),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
          if (documents.isEmpty) const Hint('No verification documents uploaded.'),
          for (var i = 0; i < documents.length; i++)
            Row(children: [
              const Icon(Icons.description_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(jstr(documents[i]['label'], 'Document ${i + 1}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Hint(formatDate(documents[i]['uploaded_at'], withTime: false)),
                ]),
              ),
              viewedDocs.contains(i)
                  ? TextButton.icon(onPressed: () => openDocument(documents[i], i), icon: const Icon(Icons.check, size: 16), label: const Text('Opened'))
                  : OutlinedButton.icon(onPressed: () => openDocument(documents[i], i), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Open')),
            ]),
          if (docError.isNotEmpty) Note(docError),
          if (canWrite && !reviewed && documents.isNotEmpty)
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              BusyButton(
                label: 'Mark documents as reviewed',
                icon: Icons.check_circle_outline,
                busy: busy,
                onPressed: allViewed ? () => act(() => session.api.reviewVendorDocuments(widget.vendorId), (_) => 'Verification documents marked as reviewed.') : null,
              ),
              if (!allViewed) Hint('Open every document above first (${viewedDocs.length}/${documents.length}).'),
            ]),
          if (canWrite && vendor['status'] != 'approved')
            Note(
              reviewed ? 'Documents reviewed. You can approve this vendor.' : 'Review and confirm the documents before approving.',
              tone: Tone.green,
              action: FilledButton(
                onPressed: !reviewed || busy
                    ? null
                    : () => act(() => session.api.setVendorStatus(widget.vendorId, {'status': 'approved'}), _statusToast),
                child: const Text('Approve vendor'),
              ),
            ),
          if (actionError != null) ErrorNote(error: actionError),
        ], 10)),
      ),
      SectionCard(
        title: 'Recent orders',
        padding: EdgeInsets.zero,
        child: recent.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Hint('No recent orders.'))
            : Column(children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Text(jstr(recent[i]['order_number']), style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(formatRwf(recent[i]['total_amount_rwf'])),
                      const SizedBox(width: 8),
                      StatusBadge(jstr(recent[i]['status_label'], jstr(recent[i]['status']))),
                    ]),
                  ),
                ],
              ]),
      ),
    ]);
  }

  /// Answer the vendor's type change request, or set the type directly.
  Widget _typeCard(Json vendor, bool canWrite) {
    final request = vendor['vendor_type_request'] is Map ? jmap(vendor['vendor_type_request']) : null;
    final currentCode = vendorTypeOf(vendor['vendor_type']).code;
    return SectionCard(
      title: 'Vendor type',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        if (request != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Tone.amber.background(context), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Asked to change from', style: TextStyle(fontSize: 12.5)),
                VendorTypeBadge(vendor['vendor_type']),
                const Text('to', style: TextStyle(fontSize: 12.5)),
                VendorTypeBadge(request['vendor_type']),
                if (request['requested_at'] != null) Hint('· ${formatDate(request['requested_at'])}'),
              ]),
              if (jstr(request['reason']).isNotEmpty) Text('“${jstr(request['reason'])}”', style: const TextStyle(fontSize: 12.5)),
              if (canWrite)
                Wrap(spacing: 8, children: [
                  FilledButton(
                    onPressed: busy ? null : () => act(() => session.api.setVendorType(widget.vendorId, {'decision': 'approve'}), (_) => 'Type change approved.'),
                    child: const Text('Approve change'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => act(() => session.api.setVendorType(widget.vendorId, {'decision': 'reject'}), (_) => 'Type change request declined.'),
                    child: const Text('Decline'),
                  ),
                ]),
            ], 8)),
          ),
        if (canWrite)
          Row(children: [
            Expanded(
              child: Dropdown<String>(
                value: newType ?? '',
                options: {
                  '': 'Change type to…',
                  for (final type in vendorTypes.where((t) => t.code != currentCode)) type.code: type.label,
                },
                onChanged: (value) => setState(() => newType = value.isEmpty ? null : value),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: newType == null || busy
                  ? null
                  : () => act(() async {
                        final result = await session.api.setVendorType(widget.vendorId, {'vendor_type': newType});
                        setState(() => newType = null);
                        return result;
                      }, (_) => 'Vendor type updated.'),
              child: const Text('Save type'),
            ),
          ]),
      ], 10)),
    );
  }

  /// Nationwide events: the kitchen takes orders anywhere in Rwanda and brings
  /// orders beyond the delivery workers' range itself.
  Widget _nationwideCard(Json vendor, bool canWrite) {
    final nationwide = jmap(vendor['nationwide']);
    final choice = nationwide['source'] == 'admin' ? (nationwide['enabled'] == true ? 'on' : 'off') : 'default';
    final options = [
      ('default', 'Type default (${nationwide['by_type'] == true ? 'on' : 'off'})', null),
      ('on', 'On', true),
      ('off', 'Off', false),
    ];
    return SectionCard(
      title: 'Nationwide events',
      action: ToneBadge(nationwide['enabled'] == true ? 'On' : 'Off', tone: nationwide['enabled'] == true ? Tone.violet : Tone.slate),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        Hint("Takes orders anywhere in Rwanda. Orders beyond the delivery workers' range are brought by the kitchen itself, for its travel fee "
            '(${formatNumber(nationwide['travel_base_fee_rwf'])} RWF + ${formatNumber(nationwide['travel_per_km_rwf'])} RWF/km). Caterers are on by default.'),
        if (canWrite)
          Wrap(spacing: 8, children: [
            for (final (value, label, enabled) in options)
              choice == value
                  ? FilledButton(onPressed: null, child: Text(label))
                  : OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => act(
                                () => session.api.setVendorNationwide(widget.vendorId, enabled),
                                (result) => jmap(jmap(result)['vendor'])['nationwide']?['enabled'] == true
                                    ? 'Nationwide orders switched on.'
                                    : 'Nationwide orders switched off.',
                              ),
                      child: Text(label),
                    ),
          ]),
      ], 10)),
    );
  }

  /// The kitchen's registered location and whether the store is open — only
  /// open stores are on the customer map and offered to delivery workers.
  Widget _locationCard(Json vendor) {
    final location = jmap(vendor['location']);
    final lat = location['latitude'];
    final lng = location['longitude'];
    final hasCoords = lat is num && lng is num;
    // Vendors registered before kitchen coordinates were collected got the city centre.
    final isDefault = hasCoords && (lat - kKigaliLat).abs() < 1e-4 && (lng - kKigaliLng).abs() < 1e-4;
    final address = [jstr(vendor['address']), jstr(vendor['neighborhood'])].where((s) => s.isNotEmpty).join(', ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced([
            const SectionLabel('Kitchen location'),
            Text(address.isEmpty ? 'No address' : address, style: const TextStyle(fontWeight: FontWeight.w700)),
            Hint('${hasCoords ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}' : 'No coordinates'}'
                '${location['updated_at'] != null ? ' · set ${formatDate(location['updated_at'])}' : ''}'),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ToneBadge(vendor['is_open'] == true ? 'Store open · on the map' : 'Store closed · hidden', tone: vendor['is_open'] == true ? Tone.green : Tone.slate),
              if (hasCoords)
                TextButton.icon(onPressed: () => openMaps(lat, lng), icon: const Icon(Icons.open_in_new, size: 15), label: const Text('Google Maps')),
            ]),
            if (isDefault)
              const Note('This is the Kigali city-centre default, not the real kitchen. Ask the vendor to set their location in Profile.', tone: Tone.amber),
          ], 6)),
        ),
        if (hasCoords) LiveRouteMap.kitchen(lat.toDouble(), lng.toDouble()),
      ]),
    );
  }
}
