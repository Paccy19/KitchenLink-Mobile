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

/// "Offer Days": deals announced for a chosen day, from tomorrow on.
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offersProvider);
    final canAct = ref.watch(canActProvider);
    final theme = Theme.of(context);
    final full = (state.value?.length ?? 0) >= Offer.maxUpcoming;

    return Scaffold(
      appBar: AppBar(title: const Text('Offer days')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (!canAct || full) ? null : () => _compose(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New offer'),
      ),
      body: AsyncBody<List<Offer>>(
        value: state,
        onRefresh: () => ref.read(offersProvider.notifier).reload(silent: false),
        builder: (context, offers) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (!canAct)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteBox(message: 'You can announce offers once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
              ),
            Text(
              'Announce a deal for a future day. Customers who ordered from you are told straight away. '
              'You can have up to ${Offer.maxUpcoming} upcoming offers.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (offers.isEmpty)
              const SizedBox(
                height: 260,
                child: EmptyState(icon: Icons.local_offer_outlined, title: 'No upcoming offers', message: 'Tap "New offer" to announce one.'),
              )
            else
              for (final offer in offers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.local_offer_rounded, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(offer.title, style: theme.textTheme.titleMedium),
                          Text(formatOfferDay(offer.offerDate), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w700)),
                          if (offer.details.isNotEmpty) ...[const SizedBox(height: 4), Text(offer.details, style: theme.textTheme.bodyMedium)],
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Cancel offer',
                        onPressed: canAct ? () => _cancel(context, ref, offer) : null,
                        icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                      ),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Offer offer) async {
    final yes = await confirm(
      context,
      title: 'Cancel this offer?',
      message: '"${offer.title}" on ${formatOfferDay(offer.offerDate)} will be removed.',
      confirmLabel: 'Cancel offer',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!yes || !context.mounted) return;
    await runAction(context, () => ref.read(promotionsActionsProvider).cancelOffer(offer.id), success: 'Offer cancelled.');
  }

  Future<void> _compose(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => const _OfferComposer(),
      );
}

class _OfferComposer extends ConsumerStatefulWidget {
  const _OfferComposer();

  @override
  ConsumerState<_OfferComposer> createState() => _OfferComposerState();
}

class _OfferComposerState extends ConsumerState<_OfferComposer> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  DateTime? _day;
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? tomorrow,
      firstDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
      lastDate: DateTime.now().add(const Duration(days: Offer.maxDaysAhead)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_day == null) {
      setState(() => _problem = 'Choose the day of the offer.');
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    final ok = await runAction(context, () async {
      await ref.read(promotionsActionsProvider).createOffer(title: _title.text, details: _details.text, offerDate: formatIsoDay(_day!));
      return true;
    }, success: 'Offer announced to your customers.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('New offer day', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Title',
              hint: 'e.g. Buy 2 brochettes, get 1 free',
              controller: _title,
              maxLength: Offer.titleMax,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => Validators.length(value, 'Title', min: 2, max: Offer.titleMax),
            ),
            AppTextField(
              label: 'Details (optional)',
              controller: _details,
              maxLength: Offer.detailsMax,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 4),
            AppCard(
              onTap: _pickDay,
              child: Row(children: [
                Icon(Icons.event_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(_day == null ? 'Choose the day' : formatDate(_day), style: theme.textTheme.titleSmall)),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 10),
              NoteBox(message: _problem!, tone: Tone.danger, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Announce offer'),
            ),
          ]),
        ),
      ),
    );
  }
}
