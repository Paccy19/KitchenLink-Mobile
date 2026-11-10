import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/orders_providers.dart';
import '../models/order.dart';
import '../models/order_actions.dart';
import 'order_action_handler.dart';
import 'order_presentation.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = orderDetailProvider(orderId);
    final state = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(state.value == null ? 'Order' : 'Order #${state.value!.orderNumber}')),
      body: state.when(
        loading: () => const SkeletonList(count: 3, height: 140),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(provider)),
        data: (order) => _OrderBody(order: order, onRefresh: () => ref.read(provider.notifier).reload(silent: false)),
      ),
    );
  }
}

class _OrderBody extends ConsumerStatefulWidget {
  const _OrderBody({required this.order, required this.onRefresh});

  final VendorOrder order;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends ConsumerState<_OrderBody> {
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

  Future<void> _call(String phone) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!opened && mounted) showError(context, 'Could not open the phone app.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final actions = orderActionsFor(order);
    final blocker = orderBlockerNote(order);

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _header(theme, order),
                  if (blocker != null) ...[
                    const SizedBox(height: 12),
                    NoteBox(message: blocker, tone: Tone.warning, icon: Icons.hourglass_empty_rounded),
                  ],
                  if (order.readyAvailableAt != null && order.status == OrderStatus.preparing) ...[
                    const SizedBox(height: 12),
                    NoteBox(
                      message: 'This ${order.orderTypeLabel.toLowerCase()} can be marked ready from '
                          '${formatDateTime(order.readyAvailableAt)}.',
                      tone: Tone.info,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _customerCard(theme, order),
                  const SizedBox(height: 12),
                  _fulfillmentCard(theme, order),
                  if (order.event != null) ...[const SizedBox(height: 12), _eventCard(theme, order)],
                  const SizedBox(height: 12),
                  _itemsCard(theme, order),
                  const SizedBox(height: 12),
                  _paymentCard(theme, order),
                  if (order.history.isNotEmpty) ...[const SizedBox(height: 12), _historyCard(theme, order)],
                ],
              ),
            ),
          ),
        ),
      ),
      if (actions.isNotEmpty) _actionBar(theme, actions),
    ]);
  }

  Widget _header(ThemeData theme, VendorOrder order) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusChip(label: order.statusLabel, tone: toneForStatus(order.status), icon: iconForStatus(order.status)),
            const SizedBox(width: 8),
            StatusChip(label: paymentLabel(order.paymentStatus), tone: toneForPayment(order.paymentStatus)),
          ]),
          const SizedBox(height: 12),
          Text(formatRwf(order.totalRwf), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            'Placed ${formatDateTime(order.createdAt)} · ${order.orderTypeLabel.isEmpty ? 'Order' : order.orderTypeLabel}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (order.scheduledFor != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.schedule_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('For ${formatDateTime(order.scheduledFor)}', style: theme.textTheme.titleSmall)),
            ]),
          ],
          if (order.cancelReason != null && order.status == OrderStatus.cancelled) ...[
            const SizedBox(height: 8),
            Text('Reason: ${order.cancelReason}', style: theme.textTheme.bodyMedium),
          ],
        ]),
      );

  Widget _customerCard(ThemeData theme, VendorOrder order) => AppCard(
        child: Row(children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(initials(order.customer.name), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.customer.name, style: theme.textTheme.titleMedium),
              if (order.customer.phone.isNotEmpty)
                Text(order.customer.phone, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (order.customer.phone.isNotEmpty)
            IconButton.filledTonal(
              tooltip: 'Call customer',
              onPressed: () => _call(order.customer.phone),
              icon: const Icon(Icons.call_rounded),
            ),
        ]),
      );

  Widget _fulfillmentCard(ThemeData theme, VendorOrder order) {
    final location = order.deliveryLocation;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(iconForFulfillment(order), color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(order.fulfillmentLabel.isEmpty ? fulfillmentTitle(order) : order.fulfillmentLabel, style: theme.textTheme.titleMedium),
        ]),
        const SizedBox(height: 10),
        if (order.isPickup)
          Text('The customer collects this order at your kitchen. You complete it with their pickup code.', style: theme.textTheme.bodyMedium)
        else ...[
          if (location.summary.isNotEmpty) _line(theme, Icons.place_rounded, location.summary),
          if (order.deliveryDistanceKm != null)
            _line(theme, Icons.route_rounded, '${order.deliveryDistanceKm!.toStringAsFixed(1)} km from your kitchen'),
          if (location.note.isNotEmpty) _line(theme, Icons.sticky_note_2_outlined, location.note),
          if (order.kitchenDelivers)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This address is too far for delivery workers, so you bring it yourself and confirm with the customer\'s code.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('A delivery worker collects and delivers this order.', style: theme.textTheme.bodySmall),
            ),
        ],
        if (order.specialText.isNotEmpty) ...[
          const SizedBox(height: 10),
          _line(theme, Icons.campaign_outlined, 'Special: ${order.specialText}'),
        ],
        if (order.etaMinutes != null) _line(theme, Icons.timer_outlined, 'ETA ${order.etaMinutes} min'),
      ]),
    );
  }

  Widget _line(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ]),
      );

  Widget _eventCard(ThemeData theme, VendorOrder order) {
    final event = order.event!;
    final deposit = order.deposit;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.celebration_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(event.packageName.isEmpty ? 'Event order' : event.packageName, style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 10),
        _kv(theme, 'Guests', '${event.guests}'),
        _kv(theme, 'Price per plate', formatRwf(event.pricePerPlateRwf)),
        if (event.serviceStyleLabel.isNotEmpty) _kv(theme, 'Service', event.serviceStyleLabel),
        if (event.portion.isNotEmpty) _kv(theme, 'Per person', event.portion),
        if (event.serviceDetails.isNotEmpty) _kv(theme, 'Service notes', event.serviceDetails),
        if (event.deliveryDetails.isNotEmpty) _kv(theme, 'Delivery notes', event.deliveryDetails),
        if (event.menu.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('On the plate', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final item in event.menu) Text('• $item'),
        ],
        if (deposit != null) ...[
          const Divider(height: 24),
          _kv(theme, 'Deposit', formatRwf(deposit.depositRwf)),
          _kv(theme, 'Balance', formatRwf(deposit.balanceRwf)),
          _kv(theme, 'Balance due', formatDateTime(deposit.balanceDueAt)),
          const SizedBox(height: 4),
          StatusChip(
            label: deposit.balanceUnpaid ? 'Balance unpaid' : 'Balance paid',
            tone: deposit.balanceUnpaid ? Tone.warning : Tone.success,
            icon: deposit.balanceUnpaid ? Icons.hourglass_bottom_rounded : Icons.check_rounded,
          ),
        ],
      ]),
    );
  }

  Widget _itemsCard(ThemeData theme, VendorOrder order) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Items (${order.itemCount})', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text('${item.quantity}×', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, style: theme.textTheme.titleSmall),
                    for (final option in item.options)
                      Text(
                        '${option.groupName}: ${option.name}${option.additionalPriceRwf > 0 ? ' (+${formatRwf(option.additionalPriceRwf)})' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(formatRwf(item.subtotalRwf), style: theme.textTheme.titleSmall),
              ]),
            ),
        ]),
      );

  Widget _paymentCard(ThemeData theme, VendorOrder order) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Payment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _kv(theme, 'Subtotal', formatRwf(order.subtotalRwf)),
          if (!order.isPickup) _kv(theme, 'Delivery fee', formatRwf(order.deliveryFeeRwf)),
          _kv(theme, 'Total', formatRwf(order.totalRwf), bold: true),
          const Divider(height: 22),
          _kv(theme, 'Method', paymentMethodLabel(order.paymentMethod)),
          _kv(theme, 'Status', paymentLabel(order.paymentStatus)),
          if (order.commissionRwf > 0 || order.vendorPayoutRwf > 0) ...[
            const Divider(height: 22),
            _kv(theme, 'Commission (${order.commissionPercent.toStringAsFixed(order.commissionPercent % 1 == 0 ? 0 : 1)}%)', formatRwf(order.commissionRwf)),
            _kv(theme, 'Your payout', formatRwf(order.vendorPayoutRwf), bold: true),
          ],
        ]),
      );

  Widget _historyCard(ThemeData theme, VendorOrder order) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Timeline', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final entry in order.history.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 5, right: 10), child: Icon(Icons.circle, size: 8)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.label, style: theme.textTheme.titleSmall),
                    Text(
                      [formatDateTime(entry.at), if (entry.note.isNotEmpty && entry.note != entry.label) entry.note].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ]),
            ),
        ]),
      );

  Widget _kv(ThemeData theme, String key, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(key, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  Widget _actionBar(ThemeData theme, List<OrderAction> actions) {
    final primary = actions.where((a) => a.kind != OrderActionKind.cancel).toList();
    final cancel = actions.where((a) => a.kind == OrderActionKind.cancel).firstOrNull;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final action in primary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(action),
                    icon: Icon(action.kind == OrderActionKind.handover ? Icons.pin_rounded : Icons.arrow_forward_rounded, size: 20),
                    label: Text(action.label),
                  ),
                  if (!action.enabled && action.disabledReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        action.disabledReason!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ]),
              ),
            if (cancel != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                ),
                onPressed: _busy ? null : () => _run(cancel),
                child: Text(cancel.label),
              ),
          ]),
        ),
      ),
    );
  }
}
