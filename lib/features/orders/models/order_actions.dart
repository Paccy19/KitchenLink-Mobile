import 'order.dart';

/// What the kitchen can do with an order on screen.
enum OrderActionKind {
  /// A forward step (accept, start preparing, mark ready).
  advance,

  /// Reject / cancel; asks for confirmation and an optional reason.
  cancel,

  /// Enter the customer's 6-digit code to hand the order over.
  handover,
}

class OrderAction {
  const OrderAction({
    required this.kind,
    required this.label,
    this.status,
    this.enabled = true,
    this.disabledReason,
  });

  final OrderActionKind kind;
  final String label;

  /// The status sent to the API (null for the handover action).
  final OrderStatus? status;
  final bool enabled;

  /// Why a visible action cannot be used yet.
  final String? disabledReason;
}

/// Decides which buttons an order shows. The backend's `allowed_next_statuses`
/// is the only source of forward and cancel steps; nothing is invented here:
///
/// - the kitchen never gets a "complete" action (a delivery worker completes
///   delivery orders; pickup / kitchen-delivered orders use the code);
/// - a scheduled order's "ready" step stays visible but disabled until
///   `ready_available_at`;
/// - an event order whose balance is unpaid cannot be marked ready or handed
///   over.
List<OrderAction> orderActionsFor(VendorOrder order, {DateTime? now}) {
  if (order.status.isFinal) return const [];
  final actions = <OrderAction>[];
  final allowed = order.allowedNextStatuses;

  for (final next in allowed) {
    if (next == OrderStatus.completed || next == OrderStatus.newOrder) continue;
    if (next == OrderStatus.cancelled) continue; // added last
    actions.add(OrderAction(
      kind: OrderActionKind.advance,
      status: next,
      label: _advanceLabel(next, order),
    ));
  }

  // A scheduled order cannot be marked ready yet: show why, never hide it.
  final readyAt = order.readyAvailableAt;
  if (readyAt != null && order.status == OrderStatus.preparing && !allowed.contains(OrderStatus.ready)) {
    if (readyAt.isAfter(now ?? DateTime.now())) {
      actions.add(OrderAction(
        kind: OrderActionKind.advance,
        status: OrderStatus.ready,
        label: _advanceLabel(OrderStatus.ready, order),
        enabled: false,
        disabledReason: 'Scheduled order. You can mark it ready closer to the delivery time.',
      ));
    }
  }

  if (order.usesHandoverCode && order.status == OrderStatus.ready) {
    final locked = order.pickupAttemptsLeft != null && order.pickupAttemptsLeft! <= 0;
    final unpaid = order.deposit?.balanceUnpaid ?? false;
    actions.add(OrderAction(
      kind: OrderActionKind.handover,
      label: order.kitchenDelivers ? 'Confirm delivery with code' : 'Confirm pickup with code',
      enabled: order.canConfirmPickup,
      disabledReason: order.canConfirmPickup
          ? null
          : unpaid
              ? "The customer hasn't paid the balance of this event yet."
              : locked
                  ? 'Too many wrong codes. Contact support to complete this order.'
                  : 'The order must be ready before it can be handed over.',
    ));
  }

  if (allowed.contains(OrderStatus.cancelled)) {
    actions.add(OrderAction(
      kind: OrderActionKind.cancel,
      status: OrderStatus.cancelled,
      label: order.status == OrderStatus.newOrder ? 'Reject order' : 'Cancel order',
    ));
  }
  return actions;
}

String _advanceLabel(OrderStatus next, VendorOrder order) => switch (next) {
      OrderStatus.accepted => 'Accept order',
      OrderStatus.preparing => 'Start preparing',
      OrderStatus.ready => order.usesHandoverCode ? 'Mark ready' : 'Mark ready for delivery',
      _ => next.label,
    };

/// A short explanation shown on an order that is waiting for something
/// outside the kitchen's control, or null.
String? orderBlockerNote(VendorOrder order) {
  if (order.status.isFinal) return null;
  if (order.awaitingPayment) {
    return "The customer hasn't paid yet. You can accept the order once payment arrives, or reject it.";
  }
  final deposit = order.deposit;
  if (deposit != null && deposit.balanceUnpaid && order.status != OrderStatus.newOrder) {
    return 'The event balance is unpaid. You can mark the order ready once the customer has paid it.';
  }
  return null;
}
