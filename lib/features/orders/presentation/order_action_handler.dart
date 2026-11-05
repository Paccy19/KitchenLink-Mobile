import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/orders_providers.dart';
import '../models/order.dart';
import '../models/order_actions.dart';

/// Carries out a button the vendor tapped on an order. Returns the order as
/// the backend now has it, or null when nothing changed (cancelled, refused,
/// failed). The screen never shows a success the backend did not confirm.
Future<VendorOrder?> performOrderAction(
  BuildContext context,
  WidgetRef ref,
  VendorOrder order,
  OrderAction action,
) async {
  if (!action.enabled) {
    if (action.disabledReason != null) showError(context, action.disabledReason!);
    return null;
  }
  switch (action.kind) {
    case OrderActionKind.advance:
      final updated = await runAction(
        context,
        () => ref.read(orderActionsProvider).advance(order.id, action.status!),
        success: _advanceMessage(action.status!, order),
      );
      return updated;
    case OrderActionKind.cancel:
      final result = await showCancelSheet(context, order);
      if (result == null || !context.mounted) return null;
      return runAction(
        context,
        () => ref.read(orderActionsProvider).advance(order.id, OrderStatus.cancelled, note: result.reason),
        success: order.status == OrderStatus.newOrder ? 'Order rejected.' : 'Order cancelled.',
      );
    case OrderActionKind.handover:
      return showHandoverSheet(context, ref, order);
  }
}

String _advanceMessage(OrderStatus status, VendorOrder order) => switch (status) {
      OrderStatus.accepted => 'Order accepted.',
      OrderStatus.preparing => 'Marked as preparing.',
      OrderStatus.ready => order.usesHandoverCode ? 'Marked ready.' : 'Marked ready. Delivery workers are being notified.',
      _ => 'Order updated.',
    };

class CancelResult {
  const CancelResult(this.reason);
  final String reason;
}

/// Confirms a rejection / cancellation and collects an optional reason that
/// is saved on the order.
Future<CancelResult?> showCancelSheet(BuildContext context, VendorOrder order) {
  final isReject = order.status == OrderStatus.newOrder;
  final controller = TextEditingController();
  return showModalBottomSheet<CancelResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isReject ? 'Reject this order?' : 'Cancel this order?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            order.isPaid
                ? 'The customer will be told, and their payment goes back to them.'
                : 'The customer will be told that you could not take this order.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Reason (optional)',
            hint: 'e.g. Sold out of this dish',
            controller: controller,
            maxLength: 200,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, CancelResult(controller.text.trim())),
            child: Text(isReject ? 'Reject order' : 'Cancel order'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep order')),
        ]),
      );
    },
  );
}

/// Asks for the customer's 6-digit code and sends it to the backend.
/// Success is only reported once the backend completed the order.
Future<VendorOrder?> showHandoverSheet(BuildContext context, WidgetRef ref, VendorOrder order) =>
    showModalBottomSheet<VendorOrder>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HandoverSheet(order: order, ref: ref),
    );

class _HandoverSheet extends StatefulWidget {
  const _HandoverSheet({required this.order, required this.ref});

  final VendorOrder order;
  final WidgetRef ref;

  @override
  State<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<_HandoverSheet> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  late int? _attemptsLeft = widget.order.pickupAttemptsLeft;
  bool _locked = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _locked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.ref.read(orderActionsProvider).collect(widget.order.id, _code.text.trim());
      if (!mounted) return;
      Navigator.pop(context, updated);
      showSuccess(
        context,
        widget.order.kitchenDelivers ? 'Delivery confirmed. The order is complete.' : 'Pickup confirmed. The order is complete.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      final left = error.details['attempts_left'];
      setState(() {
        _error = error.message;
        if (left is num) _attemptsLeft = left.toInt();
        if (error.code == ApiCodes.pickupCodeLocked || (left is num && left <= 0)) _locked = true;
        if (error.code == ApiCodes.pickupCodeIncorrect) _code.clear();
      });
      if (error.isPendingReview) await showPendingReviewDialog(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(order.kitchenDelivers ? 'Confirm delivery' : 'Confirm pickup', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            order.kitchenDelivers
                ? 'Ask ${order.customer.name} for the 6-digit code they received, then enter it here to complete the delivery.'
                : 'Ask ${order.customer.name} for the 6-digit pickup code they received, then enter it here to hand the order over.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _code,
            enabled: !_busy && !_locked,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 10, fontWeight: FontWeight.w800),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(hintText: '••••••', counterText: ''),
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '') ? null : 'Enter the 6-digit code.',
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_attemptsLeft != null) ...[
            const SizedBox(height: 8),
            Text(
              _locked
                  ? 'This order is locked.'
                  : '$_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: (_attemptsLeft ?? 9) <= 1 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoteBox(message: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _locked ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(order.kitchenDelivers ? 'Complete delivery' : 'Complete pickup'),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        ]),
      ),
    );
  }
}
