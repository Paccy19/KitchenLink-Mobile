import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../auth/application/session.dart';
import '../application/settings_providers.dart';
import 'widgets/place_search_field.dart';
import '../../../core/widgets/kitchen_location_map.dart';

/// The registered kitchen location. An open store appears to customers at
/// these coordinates; the phone's own position is never used.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _vendor = ref.read(vendorProvider);
  late final _address = TextEditingController(text: _vendor.location.address);
  late final _neighborhood = TextEditingController(text: _vendor.location.neighborhood);
  late final _lat = TextEditingController(text: _vendor.location.latitude?.toStringAsFixed(6));
  late final _lng = TextEditingController(text: _vendor.location.longitude?.toStringAsFixed(6));
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_address, _neighborhood, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await runAction(
      context,
      () => ref.read(settingsActionsProvider).updateProfile({
        'location': {
          'latitude': double.parse(_lat.text.trim()),
          'longitude': double.parse(_lng.text.trim()),
          'address': _address.text.trim(),
          'neighborhood': _neighborhood.text.trim(),
        },
      }),
      success: 'Kitchen location saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final canAct = ref.watch(canActProvider);
    final vendor = ref.watch(vendorProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen location')),
      body: Form(
        key: _formKey,
        child: FormPage(children: [
          if (!canAct)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NoteBox(message: 'You can change your location once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
            ),
          if (!vendor.location.hasCoordinates)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NoteBox(message: 'Add your kitchen coordinates before opening your store.', tone: Tone.danger, icon: Icons.location_off_rounded),
            ),
          AppCard(
            child: Row(children: [
              Icon(Icons.place_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(vendor.location.summary.isEmpty ? 'No address yet' : vendor.location.summary, style: theme.textTheme.titleSmall),
                  if (vendor.location.hasCoordinates)
                    Text(
                      '${vendor.location.latitude!.toStringAsFixed(5)}, ${vendor.location.longitude!.toStringAsFixed(5)}'
                      '${vendor.location.updatedAt == null ? '' : ' · set ${formatDate(vendor.location.updatedAt)}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (canAct)
            PlaceSearchField(
              onPicked: (place) => setState(() {
                _lat.text = place.lat.toStringAsFixed(6);
                _lng.text = place.lng.toStringAsFixed(6);
                if (place.kind == 'area') _neighborhood.text = place.name;
                if (_address.text.trim().isEmpty) {
                  _address.text = [place.name, place.secondary].where((part) => part.isNotEmpty).join(', ');
                }
              }),
            ),
          const SizedBox(height: 16),
          AppTextField(label: 'Street address', controller: _address, enabled: canAct, maxLength: 200, textCapitalization: TextCapitalization.words, validator: (v) => Validators.length(v, 'Address', min: 3, max: 200)),
          AppTextField(label: 'Neighbourhood', controller: _neighborhood, enabled: canAct, maxLength: 120, textCapitalization: TextCapitalization.words),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: AppTextField(
                label: 'Latitude',
                controller: _lat,
                enabled: canAct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: Validators.latitude,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'Longitude',
                controller: _lng,
                enabled: canAct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: Validators.longitude,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          KitchenLocationMap(latitude: _lat, longitude: _lng, enabled: canAct),
          const SizedBox(height: 8),
          FilledButton(onPressed: (!canAct || _saving) ? null : _save, child: Text(_saving ? 'Saving…' : 'Save location')),
        ]),
      ),
    );
  }
}
