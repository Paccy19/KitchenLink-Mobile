import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../auth/application/session.dart';
import '../../auth/models/vendor_account.dart';
import '../application/settings_providers.dart';

Widget _pendingNote(bool canAct) => canAct
    ? const SizedBox.shrink()
    : const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: NoteBox(message: 'You can change this once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
      );

// ---------------------------------------------------------------- vendor type

class VendorTypeScreen extends ConsumerStatefulWidget {
  const VendorTypeScreen({super.key});

  @override
  ConsumerState<VendorTypeScreen> createState() => _VendorTypeScreenState();
}

class _VendorTypeScreenState extends ConsumerState<VendorTypeScreen> {
  final _reason = TextEditingController();
  String? _selected;
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    final done = await runAction(
      context,
      () => ref.read(settingsActionsProvider).requestTypeChange(_selected!, _reason.text),
      success: 'Request sent. An admin will review it.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (done != null) {
      _reason.clear();
      setState(() => _selected = null);
    }
  }

  Future<void> _cancelRequest() async {
    final yes = await confirm(context, title: 'Withdraw your request?', message: 'Your kitchen type stays as it is.', confirmLabel: 'Withdraw', cancelLabel: 'Keep it');
    if (!yes || !mounted) return;
    await runAction(context, () => ref.read(settingsActionsProvider).cancelTypeChange(), success: 'Request withdrawn.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendor = ref.watch(vendorProvider);
    final types = ref.watch(vendorTypesProvider);
    final request = vendor.typeRequest;
    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen type')),
      body: FormPage(children: [
        AppCard(
          child: Row(children: [
            Icon(Icons.category_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your kitchen type', style: theme.textTheme.bodySmall),
                Text(vendor.vendorTypeLabel, style: theme.textTheme.titleMedium),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (request != null) ...[
          NoteBox(
            title: 'Change requested: ${request.label}',
            message: 'Waiting for an admin${request.requestedAt == null ? '' : ' since ${formatDate(request.requestedAt)}'}.'
                '${request.reason.isEmpty ? '' : '\nYour reason: ${request.reason}'}',
            tone: Tone.info,
            icon: Icons.hourglass_top_rounded,
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _cancelRequest, child: const Text('Withdraw request')),
        ] else ...[
          Text('A type change is reviewed by an admin. Your type does not change until they approve it.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          types.when(
            loading: () => const SkeletonBox(height: 56, radius: 14),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(vendorTypesProvider)),
            data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Request a new type'),
                items: [
                  for (final type in list.where((t) => t.code != vendor.vendorType)) DropdownMenuItem(value: type.code, child: Text(type.label)),
                ],
                onChanged: (v) => setState(() => _selected = v),
              ),
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(list.firstWhere((t) => t.code == _selected).description, style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              AppTextField(label: 'Why do you want to change? (optional)', controller: _reason, maxLength: 300, maxLines: 3, minLines: 2),
              FilledButton(onPressed: (_selected == null || _saving) ? null : _request, child: Text(_saving ? 'Sending…' : 'Send request')),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------- ordering

class OrderingSettingsScreen extends ConsumerStatefulWidget {
  const OrderingSettingsScreen({super.key});

  @override
  ConsumerState<OrderingSettingsScreen> createState() => _OrderingSettingsScreenState();
}

class _OrderingSettingsScreenState extends ConsumerState<OrderingSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _limit = TextEditingController();
  final _minOrder = TextEditingController();
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _limit.dispose();
    _minOrder.dispose();
    super.dispose();
  }

  void _fill(OrderingRules rules) {
    if (_filled) return;
    _filled = true;
    _limit.text = rules.dailyOrderLimit?.toString() ?? '';
    _minOrder.text = rules.minOrderRwf.toString();
  }

  Future<void> _save(OrderingRules rules) async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await runAction(
      context,
      () => ref.read(settingsActionsProvider).saveOrdering(
            dailyOrderLimit: int.tryParse(_limit.text.trim()),
            minOrderRwf: int.tryParse(_minOrder.text.trim()),
            sendDailyLimit: rules.hasDailyLimit,
          ),
      success: 'Ordering rules saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = ref.watch(canActProvider);
    final state = ref.watch(orderingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('How you take orders')),
      body: AsyncBody<OrderingRules>(
        value: state,
        onRefresh: () async => ref.invalidate(orderingProvider),
        builder: (context, rules) {
          _fill(rules);
          return Form(
            key: _formKey,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _pendingNote(canAct),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${rules.vendorTypeLabel} rules', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _rule(theme, Icons.flash_on_rounded, rules.orderNow ? 'Customers can order for right now' : 'Advance orders only'),
                  _rule(theme, Icons.timer_outlined, 'At least ${rules.leadTimeLabel} notice for scheduled orders'),
                  _rule(theme, Icons.event_rounded, 'Orders up to ${rules.maxDaysAhead} day${rules.maxDaysAhead == 1 ? '' : 's'} ahead'),
                  if (rules.maxItemsPerOrder != null) _rule(theme, Icons.shopping_basket_outlined, 'Up to ${rules.maxItemsPerOrder} dishes per order'),
                  if (rules.hasDailyLimit && rules.ordersToday != null)
                    _rule(theme, Icons.event_available_rounded, '${rules.ordersToday} of ${rules.dailyOrderLimit} orders booked today${rules.fullyBookedToday ? ' (fully booked)' : ''}'),
                ]),
              ),
              const SectionHeader('Your limits'),
              if (rules.hasDailyLimit)
                AppTextField(
                  label: 'Most orders per day',
                  helper: 'Between ${rules.limitRange![0]} and ${rules.limitRange![1]}. Leave empty for the default.',
                  controller: _limit,
                  enabled: canAct,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => Validators.wholeNumber(v, 'Daily limit', min: rules.limitRange![0], max: rules.limitRange![1], optional: true),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('${rules.vendorTypeLabel} kitchens have no daily order limit.', style: theme.textTheme.bodyMedium),
                ),
              AppTextField(
                label: 'Smallest order (RWF)',
                helper: 'Between ${formatNumber(rules.minOrderRange[0])} and ${formatNumber(rules.minOrderRange[1])}. Leave empty for the default.',
                controller: _minOrder,
                enabled: canAct,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => Validators.wholeNumber(v, 'Smallest order', min: rules.minOrderRange[0], max: rules.minOrderRange[1], optional: true),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: (!canAct || _saving) ? null : () => _save(rules), child: Text(_saving ? 'Saving…' : 'Save')),
            ]),
          );
        },
      ),
    );
  }

  Widget _rule(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ]),
      );
}

// ------------------------------------------------------------------ nationwide

class NationwideScreen extends ConsumerStatefulWidget {
  const NationwideScreen({super.key});

  @override
  ConsumerState<NationwideScreen> createState() => _NationwideScreenState();
}

class _NationwideScreenState extends ConsumerState<NationwideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _base = TextEditingController();
  final _perKm = TextEditingController();
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _base.dispose();
    _perKm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await runAction(
      context,
      () => ref.read(settingsActionsProvider).saveNationwide(
            travelBaseFeeRwf: int.tryParse(_base.text.trim()),
            travelPerKmRwf: int.tryParse(_perKm.text.trim()),
          ),
      success: 'Travel fee saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = ref.watch(canActProvider);
    final state = ref.watch(nationwideProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nationwide events')),
      body: AsyncBody<NationwideInfo>(
        value: state,
        onRefresh: () async => ref.invalidate(nationwideProvider),
        builder: (context, info) {
          if (!_filled) {
            _filled = true;
            _base.text = info.travelBaseFeeRwf.toString();
            _perKm.text = info.travelPerKmRwf.toString();
          }
          return Form(
            key: _formKey,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _pendingNote(canAct),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Orders anywhere in Rwanda', style: theme.textTheme.titleMedium)),
                    StatusChip(label: info.enabled ? 'On' : 'Off', tone: info.enabled ? Tone.success : Tone.neutral),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    info.enabled
                        ? (info.source == 'admin' ? 'An admin switched this on for your kitchen.' : 'This is on because of your kitchen type.')
                        : 'This is off for your kitchen. Ask support if you want to take far-away event orders.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (info.platformDeliveryMaxKm != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Delivery workers cover up to ${info.platformDeliveryMaxKm!.toStringAsFixed(info.platformDeliveryMaxKm! % 1 == 0 ? 0 : 1)} km. '
                      'Beyond that you bring the order yourself and charge a travel fee.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ]),
              ),
              const SectionHeader('Your travel fee'),
              AppTextField(
                label: 'Base fee (RWF)',
                helper: 'Between ${formatNumber(info.baseFeeRange[0])} and ${formatNumber(info.baseFeeRange[1])}.',
                controller: _base,
                enabled: canAct,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => Validators.wholeNumber(v, 'Base fee', min: info.baseFeeRange[0], max: info.baseFeeRange[1], optional: true),
              ),
              AppTextField(
                label: 'Fee per km (RWF)',
                helper: 'Between ${formatNumber(info.perKmRange[0])} and ${formatNumber(info.perKmRange[1])}.',
                controller: _perKm,
                enabled: canAct,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => Validators.wholeNumber(v, 'Fee per km', min: info.perKmRange[0], max: info.perKmRange[1], optional: true),
              ),
              FilledButton(onPressed: (!canAct || _saving) ? null : _save, child: Text(_saving ? 'Saving…' : 'Save travel fee')),
            ]),
          );
        },
      ),
    );
  }
}
