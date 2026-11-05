import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/components.dart';
import '../../models/order.dart';
import '../../models/order_actions.dart';
import '../order_action_handler.dart';
import '../order_presentation.dart';

/// A compact order: who, what, how much, and the one or two buttons the
/// kitchen needs next.
class OrderCard extends ConsumerStatefulWidget {
  const OrderCard({super.key, required this.order, required this.onOpen, this.showActions = true});

  final VendorOrder order;
  final VoidCallback onOpen;
  final bool showActions;

  @override
  ConsumerState<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<OrderCard> {
  bool _busy = false;

  Future<void> _run(OrderAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await performOrderAction(context, ref, widget.order, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final actions = widget.showActions ? orderActionsFor(order) : const <OrderAction>[];
    final advance = actions.where((a) => a.kind == OrderActionKind.advance && a.enabled).firstOrNull;
    final reject = actions.where((a) => a.kind == OrderActionKind.cancel).firstOrNull;
    final handover = actions.where((a) => a.kind == OrderActionKind.handover && a.enabled).firstOrNull;
    final highlight = order.status == OrderStatus.newOrder && order.isPaid;

    return AppCard(
      onTap: widget.onOpen,
      borderColor: highlight ? toneColors(context, Tone.warning).foreground.withValues(alpha: 0.55) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('#${order.orderNumber}', style: theme.textTheme.titleMedium),
          ),
          StatusChip(label: order.statusLabel, tone: toneForStatus(order.status), icon: iconForStatus(order.status)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Icon(iconForFulfillment(order), size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${fulfillmentTitle(order)} · ${timeAgo(order.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        if (order.isScheduled || order.isEvent) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (order.isEvent)
              StatusChip(label: 'Event · ${order.event!.guests} guests', tone: Tone.info, icon: Icons.celebration_rounded, dense: true),
            if (order.isScheduled && order.scheduledFor != null)
              StatusChip(
                label: 'For ${formatDateTime(order.scheduledFor)}',
                tone: Tone.brand,
                icon: Icons.schedule_rounded,
                dense: true,
              ),
          ]),
        ],
        const SizedBox(height: 10),
        Text(order.customer.name, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          itemsSummary(order),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text(formatRwf(order.totalRwf), style: theme.textTheme.titleMedium),
          const SizedBox(width: 8),
          StatusChip(label: paymentLabel(order.paymentStatus), tone: toneForPayment(order.paymentStatus), dense: true),
        ]),
        if (actions.isNotEmpty && (advance != null || handover != null || (reject != null && order.status == OrderStatus.newOrder))) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (reject != null && order.status == OrderStatus.newOrder)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _busy ? null : () => _run(reject),
                  child: const Text('Reject'),
                ),
              ),
            if (reject != null && order.status == OrderStatus.newOrder && (advance != null)) const SizedBox(width: 10),
            if (advance != null)
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : () => _run(advance),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(advance.label),
                ),
              )
            else if (handover != null)
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : () => _run(handover),
                  icon: const Icon(Icons.pin_rounded, size: 18),
                  label: Text(handover.label),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}
