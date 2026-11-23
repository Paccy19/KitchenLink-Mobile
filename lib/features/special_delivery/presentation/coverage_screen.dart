import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/json.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/special_delivery_providers.dart';

/// More → Delivery coverage (the website's Vendor → Delivery Coverage): where
/// the kitchen delivers big-event orders, with its own, a rented or a
/// partner's vehicle. Districts and/or "within N km" of the kitchen. The
/// kitchen never sets the price: KitchenLink's pricing is shown read-only.
/// Outside these places customers can ask for a special delivery, which the
/// kitchen may decline.
class DeliveryCoverageScreen extends ConsumerWidget {
  const DeliveryCoverageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverage = ref.watch(deliveryCoverageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery coverage')),
      body: coverage.when(
        loading: () => const SkeletonList(count: 4),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(deliveryCoverageProvider)),
        data: (data) => _CoverageForm(data: data),
      ),
    );
  }
}

class _CoverageForm extends ConsumerStatefulWidget {
  const _CoverageForm({required this.data});

  final Json data;

  @override
  ConsumerState<_CoverageForm> createState() => _CoverageFormState();
}

class _CoverageFormState extends ConsumerState<_CoverageForm> {
  late Json _data = widget.data;
  late bool _enabled;
  late List<Json> _areas;
  String? _district;
  final _radius = TextEditingController(text: '15');
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  Json? _check;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apply(widget.data);
  }

  void _apply(Json data) {
    _data = data;
    final coverage = asJson(data['coverage']);
    _enabled = coverage['big_event_enabled'] == true;
    _areas = [for (final area in asJsonList(coverage['areas'])) Map<String, dynamic>.of(area)];
  }

  @override
  void dispose() {
    _radius.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  List<Json> get _districts => asJsonList(_data['districts']);
  List<num> get _radiusLimits {
    final limits = asJson(_data['limits'])['radius_km'];
    return limits is List && limits.length == 2 ? [limits[0] as num, limits[1] as num] : const [1, 100];
  }

  void _addDistrict() {
    final code = _district;
    if (code == null || _areas.any((a) => a['kind'] == 'district' && a['district'] == code)) return;
    final district = _districts.firstWhere((d) => d['code'] == code, orElse: () => {'name': code});
    setState(() {
      _areas.add({'kind': 'district', 'district': code, 'label': str(district['name'], code), 'district_name': district['name']});
      _district = null;
    });
  }

  void _addRadius() {
    final km = num.tryParse(_radius.text.trim());
    final limits = _radiusLimits;
    if (km == null || km < limits[0] || km > limits[1]) {
      showError(context, 'Choose a distance from ${limits[0]} to ${limits[1]} km.');
      return;
    }
    setState(() => _areas.add({'kind': 'radius', 'radius_km': km, 'label': 'Within $km km of my kitchen'}));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await runAction(
      context,
      () => ref.read(specialDeliveryRepositoryProvider).saveCoverage(enabled: _enabled, areas: _areas),
      success: _enabled ? 'Delivery coverage saved.' : 'Saved. Big-event delivery is off: customers can only pick up.',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved != null) _apply(saved);
    });
  }

  Future<void> _runCheck() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) return showError(context, 'Enter the latitude and longitude of the place.');
    final result = await runAction(context, () => ref.read(specialDeliveryRepositoryProvider).checkCoverage(lat, lng));
    if (mounted && result != null) setState(() => _check = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricing = asJson(_data['platform_pricing']);
    final byProvince = <String, List<Json>>{};
    for (final d in _districts) {
      byProvince.putIfAbsent(str(d['province'], 'Other'), () => []).add(d);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Text(
        'Where you can deliver big-event orders, with your own vehicle, a rented one or a transport partner. You choose the places; KitchenLink sets the delivery price.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
            title: const Text('I deliver big-event orders', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text("Off: customers can still book your event packages and pick the food up, but can't ask you to deliver."),
          ),
          const SectionHeader('Places you deliver to'),
          if (_areas.isEmpty)
            Text('No places yet. Add districts or a distance around your kitchen.', style: theme.textTheme.bodySmall)
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (index, area) in _areas.indexed)
                InputChip(
                  label: Text(area['kind'] == 'district' ? '${str(area['district_name'], str(area['label']))} district' : str(area['label'])),
                  onDeleted: () => setState(() => _areas.removeAt(index)),
                ),
            ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _district,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Add a district'),
            items: [
              for (final entry in byProvince.entries) ...[
                DropdownMenuItem<String>(enabled: false, child: Text(entry.key, style: theme.textTheme.labelSmall)),
                for (final d in entry.value)
                  DropdownMenuItem<String>(value: str(d['code']), child: Text('   ${str(d['name'])}')),
              ],
            ],
            onChanged: (value) => setState(() => _district = value),
          ),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _district == null ? null : _addDistrict, icon: const Icon(Icons.add_rounded), label: const Text('Add district'))),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: AppTextField(
                label: 'Within (km) of my kitchen',
                controller: _radius,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(onPressed: _addRadius, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
          ]),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save coverage')),
        ]),
      ),
      const SectionHeader('KitchenLink big-event delivery pricing'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${formatRwf(intOf(pricing['starting_fee_rwf']))} starting fee + ${pricing['per_meter_rwf']} RWF per meter of road.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Above ${formatRwf(intOf(pricing['auto_ceiling_rwf']))}, or outside your places, the customer asks you for a special delivery and you agree a price with them. Set by KitchenLink; you cannot change it.',
            style: theme.textTheme.bodySmall,
          ),
          if (pricing['automatic_pricing_enabled'] == false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Automatic pricing is paused: every delivery is arranged as a special delivery.', style: theme.textTheme.bodySmall),
            ),
        ]),
      ),
      const SectionHeader('Check a place'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: AppTextField(label: 'Latitude', controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
            const SizedBox(width: 8),
            Expanded(child: AppTextField(label: 'Longitude', controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
          ]),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _runCheck, child: const Text('Check')),
          if (_check != null) ...[
            const SizedBox(height: 8),
            Text(
              _check!['covered'] == true
                  ? 'Inside your coverage (${str(asJson(_check!['matched_area'])['label'], 'matched')}): KitchenLink prices the delivery.'
                  : 'Outside your coverage: the customer would ask you for a special delivery.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_check!['district'] is Map)
              Text('District: ${str(asJson(_check!['district'])['name'])}', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    ]);
  }
}
