import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../auth/application/session.dart';
import '../application/settings_providers.dart';
import '../models/event_package.dart';

/// A kitchen's big-event offer: packages with guest ranges and plate prices,
/// (delivery is priced by KitchenLink; where the kitchen delivers is its coverage).
class EventPackageScreen extends ConsumerStatefulWidget {
  const EventPackageScreen({super.key});

  @override
  ConsumerState<EventPackageScreen> createState() => _EventPackageScreenState();
}

class _EventPackageScreenState extends ConsumerState<EventPackageScreen> {
  EventPackageSettings? _draft;
  final _details = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _start(EventPackageSettings loaded) {
    if (_draft != null) return;
    _draft = loaded;
    _details.text = loaded.deliveryDetails;
  }

  Future<void> _editPackage(EventPackageSettings draft, {int? index}) async {
    final result = await Navigator.of(context).push<EventPackage>(
      MaterialPageRoute(
        builder: (_) => _PackageEditor(
          initial: index == null ? const EventPackage(name: '') : draft.packages[index],
          settings: draft,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final list = [...draft.packages];
    if (index == null) {
      list.add(result);
    } else {
      list[index] = result;
    }
    setState(() => _draft = draft.copyWith(packages: list));
  }

  Future<void> _save() async {
    final draft = _draft?.copyWith(deliveryDetails: _details.text);
    if (draft == null || _saving) return;
    final problem = EventPackageValidator.settings(draft);
    if (problem != null) {
      showError(context, problem);
      return;
    }
    setState(() => _saving = true);
    final saved = await runAction(context, () async {
      await ref.read(settingsActionsProvider).saveEventPackage(draft);
      return true;
    }, success: 'Event packages saved.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == true) setState(() => _draft = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = ref.watch(canActProvider);
    final state = ref.watch(eventPackageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Big event packages')),
      body: AsyncBody<EventPackageSettings>(
        value: state,
        onRefresh: () async {
          setState(() => _draft = null);
          ref.invalidate(eventPackageProvider);
        },
        builder: (context, loaded) {
          _start(loaded);
          final draft = _draft!;
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (!canAct)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: NoteBox(message: 'You can change event packages once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
                  ),
                AppCard(
                  child: SwitchRow(
                    title: 'Take big event orders',
                    subtitle: 'Weddings, parties, office lunches. Customers pay half upfront and the rest a day before.',
                    value: draft.enabled,
                    onChanged: canAct ? (v) => setState(() => _draft = draft.copyWith(enabled: v)) : null,
                  ),
                ),
                SectionHeader('Packages (${draft.packages.length}/${draft.limits.packages})'),
                if (draft.packages.isEmpty)
                  const AppCard(child: Text('No packages yet. Add one, for example "Wedding buffet".'))
                else
                  for (var i = 0; i < draft.packages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: canAct ? () => _editPackage(draft, index: i) : null,
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(child: Text(draft.packages[i].name.isEmpty ? 'Unnamed package' : draft.packages[i].name, style: theme.textTheme.titleMedium)),
                                const SizedBox(width: 8),
                                StatusChip(label: draft.packages[i].enabled ? 'On' : 'Off', tone: draft.packages[i].enabled ? Tone.success : Tone.neutral, dense: true),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                draft.packages[i].tiers.isEmpty
                                    ? 'No guest ranges yet'
                                    : draft.packages[i].tiers.map((t) => '${t.minGuests}–${t.maxGuests} guests · ${formatRwf(t.pricePerPlateRwf)}').join('\n'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ]),
                          ),
                          if (canAct)
                            IconButton(
                              tooltip: 'Remove package',
                              onPressed: () => setState(() => _draft = draft.copyWith(packages: [...draft.packages]..removeAt(i))),
                              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                            ),
                        ]),
                      ),
                    ),
                OutlinedButton.icon(
                  onPressed: (!canAct || draft.packages.length >= draft.limits.packages) ? null : () => _editPackage(draft),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add a package'),
                ),
                // KitchenLink prices big-event delivery; the kitchen only
                // chooses where it delivers (the website's Delivery Coverage).
                const SectionHeader('Delivery'),
                AppCard(
                  onTap: () => context.push('/settings/coverage'),
                  child: const Row(children: [
                    Icon(Icons.map_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Delivery coverage', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('Choose where you deliver. KitchenLink sets the delivery price.'),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded),
                  ]),
                ),
                const SizedBox(height: 12),
                AppTextField(label: 'Delivery notes (optional)', controller: _details, enabled: canAct, maxLength: 500, maxLines: 3, minLines: 2),
              ]),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
              child: SafeArea(top: false, child: FilledButton(onPressed: (!canAct || _saving) ? null : _save, child: Text(_saving ? 'Saving…' : 'Save event settings'))),
            ),
          ]);
        },
      ),
    );
  }

}

class _PackageEditor extends StatefulWidget {
  const _PackageEditor({required this.initial, required this.settings});

  final EventPackage initial;
  final EventPackageSettings settings;

  @override
  State<_PackageEditor> createState() => _PackageEditorState();
}

class _TierRow {
  _TierRow(GuestTier? tier)
      : min = TextEditingController(text: tier?.minGuests.toString()),
        max = TextEditingController(text: tier?.maxGuests.toString()),
        price = TextEditingController(text: tier?.pricePerPlateRwf.toString());
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController price;

  void dispose() {
    min.dispose();
    max.dispose();
    price.dispose();
  }
}

class _PackageEditorState extends State<_PackageEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _description = TextEditingController(text: widget.initial.description);
  late final _menu = TextEditingController(text: widget.initial.menu.join('\n'));
  late final _portion = TextEditingController(text: widget.initial.portion);
  late final _serviceDetails = TextEditingController(text: widget.initial.serviceDetails);
  late String _style = widget.initial.serviceStyle;
  late bool _enabled = widget.initial.enabled;
  late final List<_TierRow> _tiers = [for (final t in widget.initial.tiers) _TierRow(t)];

  @override
  void dispose() {
    for (final c in [_name, _description, _menu, _portion, _serviceDetails]) {
      c.dispose();
    }
    for (final row in _tiers) {
      row.dispose();
    }
    super.dispose();
  }

  void _done() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tiers = [
      for (final row in _tiers)
        GuestTier(
          minGuests: int.parse(row.min.text.trim()),
          maxGuests: int.parse(row.max.text.trim()),
          pricePerPlateRwf: int.parse(row.price.text.trim()),
        ),
    ];
    final package = widget.initial.copyWith(
      name: _name.text,
      description: _description.text,
      enabled: _enabled,
      tiers: tiers,
      menu: _menu.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList(),
      portion: _portion.text,
      serviceStyle: _style,
      serviceDetails: _serviceDetails.text,
    );
    final problem = EventPackageValidator.tiers(tiers, widget.settings.limits, package.name.trim());
    if (problem != null) {
      showError(context, problem);
      return;
    }
    Navigator.pop(context, package);
  }

  @override
  Widget build(BuildContext context) {
    final styles = widget.settings.serviceStyles;
    final limits = widget.settings.limits;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial.name.isEmpty ? 'New package' : 'Edit package'),
        actions: [TextButton(onPressed: _done, child: const Text('Done'))],
      ),
      body: Form(
        key: _formKey,
        child: FormPage(children: [
          AppTextField(label: 'Package name', hint: 'e.g. Wedding buffet', controller: _name, maxLength: 60, validator: (v) => Validators.length(v, 'Name', min: 2, max: 60)),
          AppTextField(label: 'Description (optional)', controller: _description, maxLength: 300, maxLines: 2),
          SwitchRow(title: 'Package is on', subtitle: 'Customers can order it.', value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
          const SectionHeader('Guest ranges & price per plate'),
          for (var i = 0; i < _tiers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _num(_tiers[i].min, 'From', limits.guests[0], limits.guests[1])),
                const SizedBox(width: 8),
                Expanded(child: _num(_tiers[i].max, 'To', limits.guests[0], limits.guests[1])),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _num(_tiers[i].price, 'RWF / plate', limits.plateRwf[0], limits.plateRwf[1])),
                IconButton(onPressed: () => setState(() => _tiers.removeAt(i).dispose()), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
          OutlinedButton.icon(
            onPressed: _tiers.length >= limits.tiers ? null : () => setState(() => _tiers.add(_TierRow(null))),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a guest range'),
          ),
          const SectionHeader('On the plate'),
          AppTextField(label: 'Menu items (one per line)', controller: _menu, maxLines: 6, minLines: 4),
          AppTextField(label: 'Quantity per person (optional)', controller: _portion, maxLength: 300),
          const SectionHeader('Service'),
          DropdownButtonFormField<String>(
            initialValue: styles.any((s) => s.code == _style) ? _style : (styles.isEmpty ? null : styles.first.code),
            decoration: const InputDecoration(labelText: 'Service style'),
            items: [for (final s in styles) DropdownMenuItem(value: s.code, child: Text(s.label))],
            onChanged: (v) => setState(() => _style = v ?? _style),
          ),
          const SizedBox(height: 10),
          AppTextField(label: 'Service details (optional)', controller: _serviceDetails, maxLength: 500, maxLines: 3, minLines: 2),
        ]),
      ),
    );
  }

  Widget _num(TextEditingController controller, String label, int min, int max) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        validator: (v) => Validators.wholeNumber(v, label, min: min, max: max),
      );
}

