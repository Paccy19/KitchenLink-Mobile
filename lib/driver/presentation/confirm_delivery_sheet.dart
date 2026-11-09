import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/uploads.dart';
import '../../core/widgets/forms.dart';
import '../application/deliveries.dart';
import '../models/delivery.dart';
import 'widgets/trip_widgets.dart';

/// Asks for the customer's code (and an optional photo) and completes the
/// delivery. Returns the result, or null when the worker closed the sheet.
/// It rises from the bottom and is dismissed back down the same way.
Future<DeliveryCompletion?> showConfirmDeliverySheet(BuildContext context, Delivery delivery) =>
    showModalBottomSheet<DeliveryCompletion>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmDeliverySheet(delivery: delivery),
    );

class _ConfirmDeliverySheet extends ConsumerStatefulWidget {
  const _ConfirmDeliverySheet({required this.delivery});

  final Delivery delivery;

  @override
  ConsumerState<_ConfirmDeliverySheet> createState() => _ConfirmDeliverySheetState();
}

class _ConfirmDeliverySheetState extends ConsumerState<_ConfirmDeliverySheet> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  PickedUpload? _photo;
  String? _error;
  bool _busy = false;

  bool get _complete => RegExp(r'^\d{6}$').hasMatch(_code.text);

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await ref.read(mediaPickerProvider).pickImage(fromCamera: true);
      if (photo == null || !mounted) return;
      final problem = photo.validate(UploadRules.image);
      setState(() {
        _error = problem;
        if (problem == null) _photo = photo;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'The camera could not be opened.');
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_complete) {
      setState(() => _error = 'Enter the 6-digit delivery code from the customer.');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final completion = await ref
          .read(driverActionsProvider)
          .confirmDelivery(widget.delivery, code: _code.text, photo: _photo);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(completion);
    } on ApiException catch (error) {
      // e.g. "Incorrect delivery code. 4 attempts left."
      HapticFeedback.vibrate();
      if (mounted) {
        setState(() => _error = error.message);
        _code.clear();
        _focus.requestFocus();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'The photo could not be read. Try again or remove it.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = toneColors(context, Tone.brand);
    final devCode = widget.delivery.devOtp;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Hand over the order', style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text(
              'Ask ${widget.delivery.customer.name} for the 6-digit code in their KitchenLink app.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _CodeBoxes(controller: _code, focusNode: _focus, enabled: !_busy, onChanged: () => setState(() => _error = null)),
            if (kDebugMode && devCode != null) ...[
              const SizedBox(height: 10),
              Center(
                child: ActionChip(
                  avatar: const Icon(Icons.bug_report_rounded, size: 18),
                  label: Text('Development code: $devCode (tap to fill)'),
                  onPressed: () => setState(() => _code.text = devCode),
                ),
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
                    ),
            ),
            const SizedBox(height: 18),
            _PhotoRow(photo: _photo, onTake: _busy ? null : _takePhoto, onRemove: () => setState(() => _photo = null)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: success.background, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.verified_user_rounded, color: success.foreground, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The code proves the order reached the right person and releases your earnings.',
                    style: theme.textTheme.bodySmall?.copyWith(color: success.foreground),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || !_complete ? null : _submit,
              icon: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: theme.colorScheme.onPrimary),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_busy ? 'Completing…' : 'Complete delivery'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Six boxes over one hidden field: the system keyboard, paste and SMS
/// autofill keep working, and each digit gets room to be read at arm's length.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.focusNode, required this.enabled, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(children: [
      // The real input, invisible, covering the boxes so a tap focuses it.
      Positioned.fill(
        child: Opacity(
          opacity: 0,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            enabled: enabled,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (_) {
              HapticFeedback.selectionClick();
              onChanged();
            },
            showCursor: false,
            enableInteractiveSelection: false,
            decoration: const InputDecoration(border: InputBorder.none, filled: false),
          ),
        ),
      ),
      IgnorePointer(
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, focusNode]),
          builder: (context, _) {
            final text = controller.text;
            return Semantics(
              label: 'Delivery code, ${text.length} of 6 digits entered',
              child: Row(children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) SizedBox(width: i == 3 ? 14 : 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          width: focusNode.hasFocus && i == text.length.clamp(0, 5) ? 2 : 1,
                          color: focusNode.hasFocus && i == text.length.clamp(0, 5)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        i < text.length ? text[i] : '',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.photo, required this.onTake, required this.onRemove});

  final PickedUpload? photo;
  final VoidCallback? onTake;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTake,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: photo != null && !kIsWeb
                    ? Image.file(File(photo!.path), fit: BoxFit.cover)
                    : ColoredBox(
                        color: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.photo_camera_rounded, color: theme.colorScheme.primary),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(photo == null ? 'Add a proof photo' : 'Photo attached', style: theme.textTheme.titleSmall),
                Text(
                  photo == null ? 'Optional. Kept private, for disputes only.' : 'Tap to retake',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
            if (photo != null) IconButton(tooltip: 'Remove photo', onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
          ]),
        ),
      ),
    );
  }
}

/// The moment the delivery completes: what was earned, then back to offers.
Future<void> showDeliveredDialog(BuildContext context, DeliveryCompletion completion) => showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = toneColors(dialogContext, Tone.success);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: MediaQuery.maybeDisableAnimationsOf(dialogContext) == true ? 1 : 0.7, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: colors.foreground, size: 42),
                ),
              ),
              const SizedBox(height: 16),
              Text('Delivered', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Order ${completion.delivery.orderNumber} · ${completion.delivery.customer.name}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              MoneyFigure(completion.earnedRwf, size: 38, prefix: '+', color: theme.colorScheme.primary),
              Text('added to your balance', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (completion.penaltyRwf > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Late-pickup deduction: ${completion.penaltyRwf} RWF',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  GoRouter.of(context).go('/home');
                },
                child: const Text('Back to offers'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  GoRouter.of(context).go('/earnings');
                },
                child: const Text('See earnings'),
              ),
            ]),
          ),
        );
      },
    );
