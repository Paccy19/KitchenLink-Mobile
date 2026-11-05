import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../auth/application/session.dart';
import '../application/promotions_providers.dart';
import '../models/promotions.dart';

/// Opens a date and a time picker and returns the combined moment.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) async {
  final now = DateTime.now();
  final start = first ?? now;
  final date = await showDatePicker(
    context: context,
    initialDate: (initial != null && initial.isAfter(start)) ? initial : start,
    firstDate: DateTime(start.year, start.month, start.day),
    lastDate: last ?? now.add(const Duration(days: 60)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? now.add(const Duration(hours: 1))),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// "Tomorrow's Special": a one-line announcement customers can order before a cutoff.
class SpecialScreen extends ConsumerStatefulWidget {
  const SpecialScreen({super.key});

  @override
  ConsumerState<SpecialScreen> createState() => _SpecialScreenState();
}

class _SpecialScreenState extends ConsumerState<SpecialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  DateTime? _cutoff;
  DateTime? _delivery;
  bool _loaded = false;
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _fill(Special? special) {
    if (_loaded) return;
    _loaded = true;
    if (special != null) {
      _text.text = special.text;
      _cutoff = special.cutoffAt;
      _delivery = special.deliveryAt;
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    String? problem;
    if (_cutoff == null || _delivery == null) {
      problem = 'Choose when orders close and when the food is ready.';
    } else if (!_cutoff!.isAfter(DateTime.now())) {
      problem = 'The order-before time must be in the future.';
    } else if (_delivery!.isBefore(_cutoff!)) {
      problem = 'The delivery time must be at or after the order-before time.';
    }
    setState(() => _problem = problem);
    if (problem != null) return;
    setState(() => _saving = true);
    await runAction(
      context,
      () => ref.read(promotionsActionsProvider).saveSpecial(text: _text.text, cutoffAt: _cutoff!, deliveryAt: _delivery!),
      success: "Tomorrow's special is live.",
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _remove() async {
    final yes = await confirm(
      context,
      title: 'Remove the special?',
      message: 'Customers will no longer see it.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!yes || !mounted) return;
    final removed = await runAction(context, () async {
      await ref.read(promotionsActionsProvider).clearSpecial();
      return true;
    }, success: 'Special removed.');
    if (removed == true && mounted) {
      setState(() {
        _text.clear();
        _cutoff = null;
        _delivery = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = ref.watch(canActProvider);
    final state = ref.watch(specialProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Tomorrow's special")),
      body: AsyncBody<Special?>(
        value: state,
        onRefresh: () => ref.read(specialProvider.notifier).reload(silent: false),
        builder: (context, special) {
          _fill(special);
          return Form(
            key: _formKey,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (!canAct) ...[
                  const NoteBox(message: 'You can publish a special once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
                  const SizedBox(height: 12),
                ],
                if (special != null)
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, children: [
                        StatusChip(label: special.isActive ? 'Active' : 'Not active', tone: special.isActive ? Tone.success : Tone.neutral),
                        StatusChip(label: special.isOrderable ? 'Customers can order' : 'Not orderable now', tone: special.isOrderable ? Tone.success : Tone.warning),
                      ]),
                      const SizedBox(height: 10),
                      Text(special.text, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text('Order before ${formatDateTime(special.cutoffAt)}', style: theme.textTheme.bodyMedium),
                      Text('Ready ${formatDateTime(special.deliveryAt)}', style: theme.textTheme.bodyMedium),
                    ]),
                  ),
                const SectionHeader('Announce a special'),
                AppTextField(
                  label: "What's special?",
                  hint: 'e.g. Grilled tilapia with plantain',
                  controller: _text,
                  enabled: canAct,
                  maxLength: Special.textMax,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => Validators.length(value, 'Special', min: 2, max: Special.textMax),
                ),
                const SizedBox(height: 8),
                _TimeTile(
                  icon: Icons.timer_outlined,
                  label: 'Order before',
                  value: _cutoff,
                  enabled: canAct,
                  onPick: () async {
                    final picked = await pickDateTime(context, initial: _cutoff);
                    if (picked != null) setState(() => _cutoff = picked);
                  },
                ),
                const SizedBox(height: 10),
                _TimeTile(
                  icon: Icons.restaurant_rounded,
                  label: 'Food ready / delivered at',
                  value: _delivery,
                  enabled: canAct,
                  onPick: () async {
                    final picked = await pickDateTime(context, initial: _delivery ?? _cutoff, last: DateTime.now().add(const Duration(days: 14)));
                    if (picked != null) setState(() => _delivery = picked);
                  },
                ),
                if (_problem != null) ...[
                  const SizedBox(height: 12),
                  NoteBox(message: _problem!, tone: Tone.danger, icon: Icons.error_outline_rounded),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: (!canAct || _saving) ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(special == null ? 'Publish special' : 'Update special'),
                ),
                if (special != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: canAct ? _remove : null,
                    child: const Text('Remove special'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.icon, required this.label, required this.value, required this.onPick, required this.enabled});

  final IconData icon;
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: enabled ? onPick : null,
      child: Row(children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(value == null ? 'Choose date and time' : formatDateTime(value), style: theme.textTheme.titleSmall),
          ]),
        ),
        const Icon(Icons.edit_calendar_rounded),
      ]),
    );
  }
}
