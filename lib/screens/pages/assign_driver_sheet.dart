import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// Support hands an order to another delivery worker — typically because the
/// assigned one is late to collect it. Step 1: workers near the kitchen,
/// nearest first, with a Call button. Step 2: after phoning one who agreed,
/// confirm the call and assign. The server tells the late worker, the
/// kitchen and the customer.
class AssignDriverSheet extends StatefulWidget {
  const AssignDriverSheet({super.key, required this.orderId});

  final String orderId;

  @override
  State<AssignDriverSheet> createState() => _AssignDriverSheetState();
}

class _AssignDriverSheetState extends State<AssignDriverSheet> with BusyState {
  late final session = context.read<AdminSession>();
  bool includeOffline = false;
  Json? chosen;
  bool contacted = false;
  String? reason;
  final note = TextEditingController();
  String error = '';

  late final query = Query<Json>(
    () async => jmap(await session.api.nearbyDrivers(widget.orderId, {'include_offline': includeOffline ? 'true' : ''})),
    poll: const Duration(seconds: 20),
  )..addListener(_syncReason);

  void _syncReason() {
    if (reason == null && query.data != null) setState(() => reason = query.data!['late'] == true ? 'late_pickup' : 'other');
  }

  @override
  void dispose() {
    query.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> assign() async {
    if (!contacted) {
      setState(() => error = 'Call ${jstr(chosen!['name'])} first and tick the box once they agree to take the order.');
      return;
    }
    setState(() => error = '');
    final ok = await run(() => session.api.reassignDriver(widget.orderId, {
          'driver_id': jstr(chosen!['id']),
          'reason': reason ?? 'other',
          'contacted': true,
          if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
        }));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final data = query.data;
        final title = data == null ? 'Find a delivery worker' : 'Find a delivery worker · ${jstr(data['order_number'])}';
        if (query.error != null && data == null) {
          return SheetScaffold(title: title, children: [ErrorNote(error: query.error, onRetry: query.load)]);
        }
        if (data == null) return SheetScaffold(title: title, children: const [LoadingBlock()]);
        if (data['collected'] == true) {
          return SheetScaffold(title: title, children: const [
            Text('This order has already been collected, so it can no longer be reassigned.'),
          ]);
        }
        return chosen != null ? _confirmStep(title, data) : _listStep(title, data);
      },
    );
  }

  Widget _confirmStep(String title, Json data) {
    final driver = chosen!;
    final name = jstr(driver['name']);
    final current = jmap(data['current_driver']);
    final vehicle = [toTitle(driver['vehicle_type']), jstr(driver['plate_number'])].where((s) => s.isNotEmpty).join(' · ');
    return SheetScaffold(
      title: title,
      actions: [
        OutlinedButton.icon(onPressed: () => setState(() => chosen = null), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back to list')),
        BusyButton(label: 'Assign to $name', busyLabel: 'Assigning…', busy: busy, onPressed: assign),
      ],
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
              Hint('$vehicle${driver['distance_km'] != null ? ' · ${jstr(driver['distance_km'])} km from the kitchen' : ''}'),
              if (jstr(driver['phone']).isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                  onPressed: () => callPhone(jstr(driver['phone'])),
                  icon: const Icon(Icons.phone, size: 16),
                  label: Text('Call ${jstr(driver['phone'])}'),
                ),
              ],
            ]),
          ),
        ),
        CheckboxListTile(
          value: contacted,
          onChanged: (value) => setState(() {
            contacted = value ?? false;
            error = '';
          }),
          tileColor: Tone.amber.background(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('I called $name and they agreed to go to the kitchen and collect this order now, without delay.',
              style: const TextStyle(fontSize: 13)),
        ),
        Dropdown<String>(
          label: 'Reason',
          value: reason ?? 'other',
          options: const {
            'late_pickup': 'The current delivery worker is late to collect it',
            'other': 'Other (no worker yet, worker unreachable…)',
          },
          onChanged: (value) => setState(() => reason = value),
        ),
        TextField(
          controller: note,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Note for the order history (optional)',
            hintText: 'e.g. Sam not answering, Nadia 5 minutes away',
          ),
        ),
        Hint([
          if (current.isNotEmpty)
            '${jstr(current['name'])} will be told the order was given to someone else'
                '${reason == 'late_pickup' ? ' because they were late; their late-pickup charge stays on record' : ''}.',
          'The kitchen and the customer are told who is coming. $name gets the order with a fresh pickup time — if they are late too, it is flagged the same way.',
        ].join(' ')),
        if (error.isNotEmpty) Note(error),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }

  Widget _listStep(String title, Json data) {
    final kitchen = jmap(data['kitchen']);
    final current = jmap(data['current_driver']);
    final drivers = jlist(data['drivers']);
    return SheetScaffold(title: title, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.place_outlined, size: 16, color: Color(0xFF8A5332)),
              Text(jstr(kitchen['name'], 'Kitchen'), style: const TextStyle(fontWeight: FontWeight.w800)),
              data['kitchen_ready'] == true
                  ? const ToneBadge('Food ready', tone: Tone.green)
                  : const ToneBadge('Kitchen preparing', tone: Tone.amber),
            ]),
            const SizedBox(height: 6),
            if (current.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Current worker: ${jstr(current['name'])}'),
                if (jstr(current['phone']).isNotEmpty)
                  TextButton(onPressed: () => callPhone(jstr(current['phone'])), child: Text('Call ${jstr(current['phone'])}')),
                if (data['late'] == true)
                  ToneBadge(
                    'Late${data['pickup_due_at'] != null ? ' · was due ${formatDate(data['pickup_due_at'])}' : ''}',
                    tone: Tone.red,
                    icon: Icons.warning_amber_rounded,
                  ),
              ])
            else
              const Text('No delivery worker yet.'),
          ]),
        ),
      ),
      Hint('Nearest first. Call one, and once they agree, choose them. Within ${jstr(data['radius_km'])} km is the normal delivery range.'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Include offline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        value: includeOffline,
        onChanged: (value) {
          setState(() => includeOffline = value);
          query.load();
        },
      ),
      if (drivers.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'No ${includeOffline ? '' : 'online '}delivery workers found. ${includeOffline ? '' : 'Try including offline workers.'}',
            textAlign: TextAlign.center,
          ),
        )
      else
        RecordList(children: [
          for (final driver in drivers)
            RecordTile(
              title: jstr(driver['name']),
              badges: [
                if (driver['is_online'] != true) const ToneBadge('Offline'),
                if (driver['has_capacity'] == true)
                  jint(driver['active_deliveries']) > 0
                      ? ToneBadge('${jint(driver['active_deliveries'])} active', tone: Tone.amber)
                      : const ToneBadge('Free', tone: Tone.green)
                else
                  const ToneBadge('Full', tone: Tone.red),
              ],
              lines: [
                (driver['location_known'] == true
                        ? '${jstr(driver['distance_km'])} km from the kitchen${driver['within_radius'] == true ? ' (in range)' : ''} · location ${formatRelative(driver['location_updated_at'])}${driver['location_fresh'] == true ? '' : ' (old)'}'
                        : 'Location never shared') +
                    (jstr(driver['vehicle_type']).isNotEmpty ? ' · ${toTitle(driver['vehicle_type'])}' : ''),
              ],
              actions: [
                if (jstr(driver['phone']).isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => callPhone(jstr(driver['phone'])),
                    icon: const Icon(Icons.phone, size: 15, color: Color(0xFF059669)),
                    label: Text(jstr(driver['phone'])),
                  ),
                FilledButton(
                  onPressed: driver['has_capacity'] == true
                      ? () => setState(() {
                            chosen = driver;
                            contacted = false;
                            error = '';
                          })
                      : null,
                  child: const Text('Choose'),
                ),
              ],
            ),
        ]),
    ]);
  }
}
