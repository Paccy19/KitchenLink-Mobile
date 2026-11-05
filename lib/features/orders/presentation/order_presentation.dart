import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/order.dart';

/// How each order status and payment state looks.
Tone toneForStatus(OrderStatus status) => switch (status) {
      OrderStatus.newOrder => Tone.warning,
      OrderStatus.accepted => Tone.info,
      OrderStatus.preparing => Tone.brand,
      OrderStatus.ready => Tone.success,
      OrderStatus.completed => Tone.success,
      OrderStatus.cancelled => Tone.danger,
    };

IconData iconForStatus(OrderStatus status) => switch (status) {
      OrderStatus.newOrder => Icons.notifications_active_rounded,
      OrderStatus.accepted => Icons.thumb_up_alt_rounded,
      OrderStatus.preparing => Icons.soup_kitchen_rounded,
      OrderStatus.ready => Icons.check_circle_outline_rounded,
      OrderStatus.completed => Icons.task_alt_rounded,
      OrderStatus.cancelled => Icons.cancel_outlined,
    };

Tone toneForPayment(String paymentStatus) => switch (paymentStatus) {
      'paid' => Tone.success,
      'failed' => Tone.danger,
      'refunded' => Tone.neutral,
      _ => Tone.warning,
    };

String paymentLabel(String paymentStatus) => switch (paymentStatus) {
      'paid' => 'Paid',
      'failed' => 'Payment failed',
      'refunded' => 'Refunded',
      _ => 'Awaiting payment',
    };

String paymentMethodLabel(String method) => switch (method) {
      'mobile_money' || 'momo' => 'Mobile Money',
      'card' => 'Card',
      'ekash' => 'eKash',
      'wallet' => 'Wallet',
      '' => '—',
      _ => method,
    };

IconData iconForFulfillment(VendorOrder order) {
  if (order.isPickup) return Icons.storefront_rounded;
  if (order.kitchenDelivers) return Icons.delivery_dining_rounded;
  return Icons.two_wheeler_rounded;
}

/// `Pickup`, `You deliver`, `Delivery worker`.
String fulfillmentTitle(VendorOrder order) {
  if (order.isPickup) return 'Customer collects';
  if (order.kitchenDelivers) return 'You deliver';
  return 'Delivery worker';
}

/// `2× Isombe, 1× Brochettes`, shortened to fit a card.
String itemsSummary(VendorOrder order, {int maxItems = 3}) {
  final parts = [for (final item in order.items) '${item.quantity}× ${item.name}'];
  if (parts.length <= maxItems) return parts.join(', ');
  return '${parts.take(maxItems).join(', ')} +${parts.length - maxItems} more';
}
