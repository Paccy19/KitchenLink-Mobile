import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/maps.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';
import 'cart_sheet.dart';
import 'checkout_screen.dart';

/// Order tracking (the website's `/track/:id`): status and progress, the
/// pickup or delivery code, the live delivery map, the refund or event
/// balance, cancel / switch to delivery / directions, and the receipt.
/// Without [orderId] it shows the latest order.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  bool _busy = false;
  bool _switched = false;

  @override
  void initState() {
    super.initState();
    final id = widget.orderId;
    if (id != null) context.read<Orders>().refreshOne(id);
  }

  Future<void> _refresh(String id) async {
    await context.read<Orders>().refreshOne(id);
  }

  Future<void> _cancel(CustomerOrder order) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Cancel this order?', style: kText(17, weight: w900)),
        content: Text('The kitchen is told straight away. If you already paid, the money goes back to you.', style: kText(13, color: K.stone600, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep order')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: K.red500), onPressed: () => Navigator.pop(d, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final orders = context.read<Orders>();
      final updated = await context.read<CustomerApi>().cancelOrder(order.id, 'Cancelled by customer');
      // Record the cancellation even if the customer already left this screen.
      orders.put(updated);
    } catch (e) {
      if (mounted) showMarketSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSession>();
    final orders = context.watch<Orders>();
    if (!session.isSignedIn) {
      return MarketPage(
        title: 'Track order',
        body: SignInPrompt(icon: Icons.receipt_long_outlined, title: 'Sign in to see your orders', message: 'Your orders and their live status show up here.', onSignIn: () => MarketNav.requireSignIn(context)),
      );
    }
    final order = widget.orderId != null ? orders.byId(widget.orderId!) : orders.orders.firstOrNull;
    if (order == null) {
      return MarketPage(
        title: 'Track order',
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (!orders.loaded || (widget.orderId != null && orders.error == null))
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else
            EmptyCard(
              icon: Icons.receipt_long_outlined,
              title: orders.error != null ? 'Unable to load this order' : 'No active order found',
              message: orders.error,
              actionLabel: 'Return to Marketplace',
              onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
        ]),
      );
    }

    final steps = order.steps;
    final index = steps.indexWhere((s) => s.id == order.status);
    final current = index >= 0 ? steps[index] : null;
    final done = order.status == 'delivered';
    final cancelled = order.status == 'cancelled';
    final pickup = order.pickup;
    final pickupCode = '${pickup['code'] ?? ''}';
    final ready = pickup['ready_for_collection'] == true;
    final kitchenLat = (pickup['latitude'] as num?)?.toDouble();
    final kitchenLng = (pickup['longitude'] as num?)?.toDouble();
    final deposit = order.deposit;

    return MarketPage(
      title: 'Order ${order.orderNumber}',
      actions: [
        TextButton.icon(
          onPressed: () => MarketNav.support(context, orderId: order.id),
          icon: const Icon(Icons.support_agent, size: 16, color: K.brown700),
          label: Text('Get help', style: kText(12, weight: FontWeight.w700, color: K.brown700)),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _refresh(order.id),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (orders.error != null) ...[Notice(orders.error!, icon: Icons.error_outline), const SizedBox(height: 10)],
          if ((order.isPickup && !done && !cancelled) || order.canCancel)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                if (order.isPickup && !done && !cancelled)
                  OutlineAction(label: "Can't collect? Get it delivered", icon: Icons.pedal_bike, color: K.brown700, onTap: () => _switchToDelivery(order)),
                if (order.canCancel) OutlineAction(label: _busy ? 'Cancelling…' : 'Cancel order', color: K.red500, onTap: _busy ? null : () => _cancel(order)),
              ]),
            ),
          if (_switched && !order.isPickup) ...[
            const Notice('Done — your order will be delivered. Give your new delivery code to the delivery worker when they arrive.', tone: NoticeTone.success, icon: Icons.check_circle_outline),
            const SizedBox(height: 12),
          ],
          // Status header.
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((done ? 'Order complete' : cancelled ? 'Order cancelled' : 'Order status').toUpperCase(), style: kText(11, weight: FontWeight.w700, color: K.brown500, spacing: 0.6)),
              const SizedBox(height: 4),
              Text(cancelled ? 'Cancelled' : current?.label ?? order.status.replaceAll('_', ' '), style: kText(22, weight: w900)),
              if (current != null && !cancelled) Text(current.description, style: kText(12.5, color: K.stone600)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (order.isPickup) const StatusPill('You pick up', background: K.brown100, foreground: K.brown850),
                if (order.kitchenDelivers) const StatusPill('The kitchen delivers', background: K.brown100, foreground: K.brown850),
                if (order.orderType != 'immediate')
                  StatusPill('${order.orderTypeLabel}${order.scheduledFor.isNotEmpty ? ' · ${formatScheduledFor(order.scheduledFor)}' : ''}', background: const Color(0xFFEDE9FE), foreground: K.violet700),
              ]),
              const Divider(height: 24, color: K.stone100),
              Text(order.isPickup ? 'EXPECTED READY' : 'ESTIMATED DELIVERY', style: kText(10.5, weight: FontWeight.w700, color: K.stone500, spacing: 0.6)),
              Row(children: [const Icon(Icons.schedule, size: 16, color: K.brown500), const SizedBox(width: 6), Text(order.estimatedTime, style: kText(15, weight: w900))]),
              const SizedBox(height: 4),
              Text('${order.vendorName}${order.vendorLocation.isNotEmpty ? ' (${order.vendorLocation})' : ''}', style: kText(12, weight: FontWeight.w600, color: K.stone600)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlineAction(label: 'Message kitchen', icon: Icons.chat_bubble_outline, dense: true, onTap: () => MarketNav.messageKitchen(context, order.vendorId)),
                if (order.vendorPhone.isNotEmpty)
                  OutlineAction(label: 'Call kitchen', icon: Icons.phone_outlined, dense: true, color: K.brown700, onTap: () => showCallSheet(context, phone: order.vendorPhone, who: order.vendorName)),
              ]),
              if (deposit != null && !cancelled) ...[const SizedBox(height: 14), _EventBalance(order: order, deposit: deposit, onPaid: () => _refresh(order.id))],
              const SizedBox(height: 16),
              if (cancelled) ...[
                Notice('This order was cancelled. ${order.cancelReason}', icon: Icons.cancel_outlined),
                if (order.refund != null) ...[const SizedBox(height: 10), _RefundCard(order: order, refund: order.refund!, onChanged: () => _refresh(order.id))],
              ] else
                _Progress(steps: steps, index: index),
            ]),
          ),
          // The pickup / kitchen-delivery code.
          if ((order.isPickup || order.kitchenDelivers) && pickupCode.isNotEmpty && !done) ...[
            const SizedBox(height: 14),
            _CodeCard(
              title: order.kitchenDelivers ? 'Your delivery code' : 'Your pickup code',
              code: pickupCode,
              text: order.kitchenDelivers
                  ? (ready ? 'The kitchen is on the way. Give them this code when they hand you the food.' : 'The kitchen brings this order to you. Give them this code when they hand you the food, never before.')
                  : (ready ? 'Your food is ready. Give this code to the kitchen when you collect your order.' : "Give this code to the kitchen when you collect your order. We'll tell you when the food is ready."),
            ),
          ],
          if (order.kitchenDelivers && done) ...[const SizedBox(height: 14), const Notice('The kitchen delivered your order. Enjoy!', tone: NoticeTone.success, icon: Icons.check_circle_outline)],
          if (order.isPickup && done) ...[const SizedBox(height: 14), const Notice('You collected your order. Enjoy your meal!', tone: NoticeTone.success, icon: Icons.check_circle_outline)],
          // The delivery confirmation code.
          if (order.deliveryCode.isNotEmpty && !order.deliveryConfirmed) ...[
            const SizedBox(height: 14),
            _CodeCard(title: 'Delivery confirmation code', code: order.deliveryCode, text: 'Give this to the delivery worker when your food arrives to confirm the delivery.'),
          ],
          if (order.deliveryConfirmed) ...[const SizedBox(height: 14), const Notice('Delivery confirmed. Enjoy your meal!', tone: NoticeTone.success, icon: Icons.check_circle_outline)],
          // The live map, from the moment a delivery worker accepts.
          if (!order.isPickup && !order.kitchenDelivers && !cancelled && !done) _LiveTracker(orderId: order.id),
          if (order.rider != null && done) ...[
            const SizedBox(height: 14),
            Panel(
              child: Row(children: [
                const CircleAvatar(backgroundColor: K.brown50, child: Icon(Icons.pedal_bike, color: K.brown700)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ASSIGNED DELIVERY WORKER', style: kText(10.5, weight: FontWeight.w700, color: K.stone500)),
                    Text('${order.rider!['name']}', style: kText(15, weight: w900)),
                  ]),
                ),
                if ('${order.rider!['phone'] ?? ''}'.isNotEmpty)
                  OutlineAction(label: 'Call', icon: Icons.phone_outlined, dense: true, onTap: () => showCallSheet(context, phone: '${order.rider!['phone']}', who: '${order.rider!['name']}')),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          // Where.
          if (order.isPickup)
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.storefront_outlined, size: 16, color: K.brown500), const SizedBox(width: 6), Text('PICK UP AT', style: kText(11, weight: FontWeight.w700, color: K.stone500))]),
                const SizedBox(height: 6),
                Text(order.vendorName, style: kText(15, weight: w900)),
                Text([pickup['address'], pickup['neighborhood']].where((s) => s != null && '$s'.isNotEmpty).join(', ').ifEmpty('Kitchen address unavailable'), style: kText(12.5, color: K.stone600)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (kitchenLat != null && kitchenLng != null)
                    OutlineAction(
                      label: 'Directions',
                      icon: Icons.navigation_outlined,
                      dense: true,
                      color: K.brown700,
                      onTap: () => showDirections(context, lat: kitchenLat, lng: kitchenLng, name: order.vendorName, address: '${pickup['address'] ?? ''}'),
                    ),
                  if (order.vendorPhone.isNotEmpty) OutlineAction(label: 'Call kitchen', icon: Icons.phone_outlined, dense: true, onTap: () => showCallSheet(context, phone: order.vendorPhone, who: order.vendorName)),
                ]),
              ]),
            )
          else
            Panel(
              child: Row(children: [
                const Icon(Icons.location_on_outlined, color: K.brown500),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('DELIVERY DESTINATION', style: kText(10.5, weight: FontWeight.w700, color: K.stone500)),
                    Text(order.dropOff.ifEmpty('Address unavailable'), style: kText(13.5, weight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          _receipt(order),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Future<void> _switchToDelivery(CustomerOrder order) async {
    final switched = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _SwitchToDelivery(order: order),
    );
    if (switched == true && mounted) {
      await _refresh(order.id);
      if (mounted) setState(() => _switched = true);
    }
  }

  Widget _receipt(CustomerOrder order) {
    final refund = order.refund;
    final deposit = order.deposit;
    final unpaidBalance = deposit != null && deposit['balance_paid_at'] == null;
    final details = order.paymentDetails;
    final payWith = [
      order.paymentMethod,
      if ('${details['phone'] ?? ''}'.isNotEmpty) '${details['phone']}' else if ('${details['card_last4'] ?? ''}'.isNotEmpty) '•••• ${details['card_last4']}',
    ].join(' · ');
    final status = refund != null && refund['status'] != 'completed' ? '${refund['status_label'] ?? ''}'.toLowerCase() : order.paymentStatus;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Order Receipt', style: kText(16, weight: w900)),
        const SizedBox(height: 10),
        for (final item in order.items) MoneyRow('${item.quantity}x ${item.name}', rwf(item.price * item.quantity)),
        const Divider(height: 20, color: K.stone100),
        MoneyRow('Subtotal', rwf(order.subtotal)),
        MoneyRow(order.kitchenDelivers ? "Kitchen's travel fee" : 'Delivery Fee${order.isPickup ? ' (you pick up)' : ''}', order.isPickup ? 'Free' : rwf(order.deliveryFee)),
        MoneyRow(unpaidBalance ? 'Total' : 'Total Paid', rwf(order.total), strong: true),
        if (unpaidBalance) ...[
          MoneyRow('Paid so far (deposit)', rwf((deposit['amount_paid_rwf'] as num?) ?? 0)),
          MoneyRow('Balance due', rwf((deposit['balance_rwf'] as num?) ?? 0), color: K.amber800),
        ],
        const SizedBox(height: 10),
        Text('Payment via $payWith · Status: $status', style: kText(11.5, color: K.stone500)),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The step-by-step progress (a vertical list on a phone).
class _Progress extends StatelessWidget {
  const _Progress({required this.steps, required this.index});

  final List<OrderStep> steps;
  final int index;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < steps.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: i == index ? K.logoGradient : null,
                  color: i < index ? const Color(0xFF059669) : (i == index ? null : Colors.white),
                  border: i > index ? Border.all(color: K.stone200, width: 2) : null,
                ),
                child: Icon(i < index ? Icons.check : Icons.circle, size: i < index ? 15 : 7, color: i <= index ? Colors.white : K.stone300),
              ),
              if (i < steps.length - 1) Container(width: 2, height: 22, color: i < index ? const Color(0xFF059669) : K.stone200),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(steps[i].label, style: kText(13, weight: i == index ? w900 : FontWeight.w600, color: i == index ? K.brown700 : (i < index ? K.gray900 : K.stone400))),
              ),
            ),
          ]),
      ]);
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.title, required this.code, required this.text});

  final String title;
  final String code;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: K.logoGradient, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.verified_user_outlined, size: 16, color: K.brown300), const SizedBox(width: 6), Text(title.toUpperCase(), style: kText(11, weight: FontWeight.w700, color: K.brown300, spacing: 0.6))]),
          const SizedBox(height: 10),
          SelectableText(code, style: kText(34, weight: w900, color: Colors.white, spacing: 8)),
          const SizedBox(height: 6),
          Text(text, style: kText(12.5, color: K.brown100, height: 1.5)),
          const SizedBox(height: 8),
          Text('Sent to your phone and stored here in your account', style: kText(10.5, color: K.brown300)),
        ]),
      );
}

/// Big events: the deposit is paid, the balance is due a day before.
class _EventBalance extends StatefulWidget {
  const _EventBalance({required this.order, required this.deposit, required this.onPaid});

  final CustomerOrder order;
  final Json deposit;
  final Future<void> Function() onPaid;

  @override
  State<_EventBalance> createState() => _EventBalanceState();
}

class _EventBalanceState extends State<_EventBalance> {
  bool _paying = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final d = widget.deposit;
    num n(String key) => (d[key] as num?) ?? 0;
    if (d['balance_paid_at'] != null) {
      return Notice('Fully paid. Deposit ${rwf(n('deposit_rwf'))} and balance ${rwf(n('balance_rwf'))} received. Your code is below — give it to the kitchen when the food is handed over.', tone: NoticeTone.success, icon: Icons.check_circle_outline);
    }
    final overdue = d['overdue'] == true;
    final due = parseIso(d['balance_due_at']);
    final details = widget.order.paymentDetails;
    final label = [widget.order.paymentMethod, if ('${details['phone'] ?? ''}'.isNotEmpty) '${details['phone']}'].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: overdue ? K.red50 : K.brown50, borderRadius: BorderRadius.circular(16), border: Border.all(color: overdue ? K.red100 : K.brown200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(overdue ? 'Your balance is overdue' : 'Pay the balance before your event', style: kText(14, weight: w900)),
        const SizedBox(height: 4),
        Text(
          'Deposit paid: ${rwf(n('amount_paid_rwf'))}. Balance ${rwf(n('balance_rwf'))} ${overdue ? 'was due' : 'is due by'} ${due == null ? '' : formatScheduledFor(due.toIso8601String())}. '
          "Once the balance is paid you'll get your 6-digit code. The kitchen hands over your food when you give it to them.",
          style: kText(12, color: K.stone600, height: 1.5),
        ),
        if (d['can_pay_balance'] == true) ...[
          const SizedBox(height: 10),
          GradientButton(
            label: _paying ? 'Paying…' : 'Pay balance · ${rwf(n('balance_rwf'))}',
            onTap: _paying
                ? null
                : () async {
                    setState(() {
                      _paying = true;
                      _error = null;
                    });
                    try {
                      await context.read<CustomerApi>().payBalance(widget.order.id);
                      await widget.onPaid();
                    } catch (e) {
                      if (mounted) setState(() => _error = e.toString());
                    } finally {
                      if (mounted) setState(() => _paying = false);
                    }
                  },
          ),
          if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Paid with $label, like your deposit.', style: kText(11, color: K.stone500))),
        ],
        if (_error != null) ...[const SizedBox(height: 8), Notice(_error!)],
      ]),
    );
  }
}

/// The refund of a cancelled paid order, and changing where it goes.
class _RefundCard extends StatefulWidget {
  const _RefundCard({required this.order, required this.refund, required this.onChanged});

  final CustomerOrder order;
  final Json refund;
  final Future<void> Function() onChanged;

  @override
  State<_RefundCard> createState() => _RefundCardState();
}

class _RefundCardState extends State<_RefundCard> {
  final _phone = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!isRwandaPhone(_phone.text)) return setState(() => _error = 'Enter a valid Rwandan mobile number (e.g. 0788123456).');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<CustomerApi>().changeRefundDestination(widget.order.id, _phone.text.trim());
      _phone.clear();
      setState(() => _editing = false);
      await widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.refund;
    final status = '${r['status'] ?? 'pending'}';
    final destination = r['destination'] is Map ? (r['destination'] as Map) : const {};
    final tone = status == 'completed' ? NoticeTone.success : status == 'failed' ? NoticeTone.error : NoticeTone.info;
    final lines = <String>[
      '${r['status_label'] ?? 'Refund'}: ${rwf((r['amount_rwf'] as num?) ?? 0)}',
      '${status == 'completed' ? 'Sent to' : 'Going back to'} your ${destination['label'] ?? 'account'}',
      if (status == 'pending') 'Your money is on its way back. It usually arrives within ${r['expected_within_hours'] ?? 24} hours.',
      if (status == 'completed') 'Sent ${parseIso(r['completed_at']) == null ? '' : formatScheduledFor(parseIso(r['completed_at'])!.toIso8601String())}${'${r['reference'] ?? ''}'.isNotEmpty ? ' · Transaction ref ${r['reference']}' : ''}',
      if (status == 'failed') 'We could not send it${'${r['failure_reason'] ?? ''}'.isNotEmpty ? ': ${r['failure_reason']}' : '.'} Give us another mobile money number below.',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Notice(lines.join('\n'), tone: tone, icon: Icons.replay),
      if (r['can_change_destination'] == true && !_editing)
        TextButton(
          onPressed: () => setState(() => _editing = true),
          child: Text(status == 'failed' ? 'Send it to another number' : 'Send it to a different mobile money number', style: kText(12, weight: FontWeight.w700, color: K.brown700)),
        ),
      if (_editing) ...[
        const SizedBox(height: 8),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: marketInput('MTN or Airtel number, e.g. 0788123456')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: GradientButton(label: _busy ? 'Saving…' : 'Save number', height: 42, onTap: _busy ? null : _save)),
          const SizedBox(width: 8),
          OutlineAction(label: 'Cancel', onTap: () => setState(() => _editing = false)),
        ]),
      ],
      if (_error != null) ...[const SizedBox(height: 8), Notice(_error!)],
      TextButton(
        onPressed: () => MarketNav.support(context, orderId: widget.order.id),
        child: Text('Problem with this refund? Contact support →', style: kText(12, weight: FontWeight.w700, color: K.stone600)),
      ),
    ]);
  }
}

/// The delivery worker, live (polled every 4 seconds): where they are on the
/// road route to the kitchen, then to you, with the ETA and a call button.
class _LiveTracker extends StatefulWidget {
  const _LiveTracker({required this.orderId});

  final String orderId;

  @override
  State<_LiveTracker> createState() => _LiveTrackerState();
}

class _LiveTrackerState extends State<_LiveTracker> {
  Json? _live;
  Timer? _timer;
  late final CustomerApi _api;

  @override
  void initState() {
    super.initState();
    _api = context.read<CustomerApi>();
    _poll();
  }

  Future<void> _poll() async {
    try {
      final data = await _api.live(widget.orderId);
      if (mounted) setState(() => _live = data);
    } catch (_) {
      // Keep the last view; try again next tick.
    }
    if (mounted) _timer = Timer(const Duration(seconds: 4), _poll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    if (live == null || live['active'] != true) return const SizedBox.shrink();
    Json m(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    final driver = m(live['driver']);
    final fix = m(driver['location']);
    final route = m(live['route']);
    final kitchen = m(live['kitchen']);
    final destination = m(live['destination']);
    LatLng? point(Json p) => p['latitude'] is num && p['longitude'] is num ? LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()) : null;
    final toKitchen = live['phase'] == 'to_kitchen';
    final minutes = route['duration_s'] is num ? ((route['duration_s'] as num) / 60).ceil() : null;
    final km = route['distance_m'] is num ? (route['distance_m'] as num) / 1000 : null;
    final eta = parseIso(route['eta_at']);
    final vehicle = [driver['vehicle_type'], driver['plate_number']].where((s) => s != null && '$s'.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const Icon(Icons.sensors, size: 14, color: K.forest600), const SizedBox(width: 4), Text('LIVE TRACKING', style: kText(10.5, weight: w900, color: K.forest600))]),
          const SizedBox(height: 4),
          Text('${live['phase_label'] ?? ''}', style: kText(16, weight: w900)),
          Text(
            toKitchen
                ? (live['kitchen_ready'] == true ? 'Your food is ready and your delivery worker is on the way to collect it.' : 'Your delivery worker is heading to the kitchen while your food is prepared.')
                : 'Your delivery worker has your food and is riding to you.',
            style: kText(12, color: K.stone600),
          ),
          if (minutes != null) ...[
            const SizedBox(height: 8),
            Text('${toKitchen ? 'At the kitchen in' : 'Arriving in'} $minutes min', style: kText(18, weight: w900, color: K.brown750)),
            Text('${km == null ? '' : '${km.toStringAsFixed(1)} km · '}${eta == null ? '' : 'around ${formatScheduledFor(eta.toIso8601String()).split(' at ').last}'}', style: kText(11.5, color: K.stone500)),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LiveRouteMap(rider: point(fix), kitchen: point(kitchen), destination: point(destination), geometry: route['geometry'] as List?, height: 300),
          ),
          if (fix.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text("Waiting for your delivery worker's location…", style: kText(12, color: K.stone500))),
          if (fix['stale'] == true)
            Padding(padding: const EdgeInsets.only(top: 8), child: Notice('Location last updated ${formatScheduledFor('${fix['updated_at']}').split(' at ').last} — their phone may have lost signal.', tone: NoticeTone.warning)),
          if (driver.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              const CircleAvatar(backgroundColor: K.brown50, child: Icon(Icons.pedal_bike, color: K.brown700)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${driver['name'] ?? 'Delivery worker'}', style: kText(14, weight: w900)),
                  Text(vehicle.isEmpty ? 'Delivery worker' : vehicle, style: kText(11.5, color: K.stone500)),
                  if (driver['rating'] is num) Text('★ ${(driver['rating'] as num).toStringAsFixed(1)}', style: kText(11.5, weight: FontWeight.w700, color: K.amber800)),
                ]),
              ),
              if ('${driver['phone'] ?? ''}'.isNotEmpty)
                OutlineAction(label: 'Call', icon: Icons.phone_outlined, dense: true, onTap: () => showCallSheet(context, phone: '${driver['phone']}', who: '${driver['name'] ?? 'your delivery worker'}')),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// "Can't collect? Get it delivered": where to, the fee for that distance,
/// and paying it (the website's SwitchToDeliveryModal).
class _SwitchToDelivery extends StatefulWidget {
  const _SwitchToDelivery({required this.order});

  final CustomerOrder order;

  @override
  State<_SwitchToDelivery> createState() => _SwitchToDeliveryState();
}

class _SwitchToDeliveryState extends State<_SwitchToDelivery> {
  final _street = TextEditingController();
  final _area = TextEditingController();
  final _note = TextEditingController();
  final _phone = TextEditingController();
  final _card = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  String _method = 'mobile_money';
  Json? _quote;
  bool _quoting = false;
  bool _busy = false;
  String? _error;
  late final ClientLocation _location;
  String _quotedAt = '';

  @override
  void initState() {
    super.initState();
    final session = context.read<CustomerSession>();
    _location = context.read<ClientLocation>();
    final saved = session.defaultAddress;
    _street.text = saved?.street ?? '';
    _area.text = saved?.district ?? (_location.isLocated ? _location.label : '');
    _note.text = saved?.instructions ?? '';
    _phone.text = localPhone(session.phone);
    _location.addListener(_requote);
    _requote();
  }

  @override
  void dispose() {
    _location.removeListener(_requote);
    for (final c in [_street, _area, _note, _phone, _card, _expiry, _cvv]) {
      c.dispose();
    }
    super.dispose();
  }

  Json _where() => {
        'address': _street.text.trim().isEmpty ? _location.label : _street.text.trim(),
        'neighborhood': _area.text.trim(),
        'latitude': _location.lat,
        'longitude': _location.lng,
        'note': _note.text.trim(),
      };

  /// The fee depends on the distance: re-priced whenever the position changes.
  Future<void> _requote() async {
    final at = '${_location.lat},${_location.lng}';
    if (at == _quotedAt) return;
    _quotedAt = at;
    setState(() {
      _quoting = true;
      _quote = null;
      _error = null;
    });
    try {
      final quote = await context.read<CustomerApi>().quoteSwitchToDelivery(widget.order.id, _where());
      if (mounted && _quotedAt == at) setState(() => _quote = quote);
    } catch (e) {
      if (mounted && _quotedAt == at) setState(() => _error = e.toString());
    } finally {
      if (mounted && _quotedAt == at) setState(() => _quoting = false);
    }
  }

  Future<void> _confirm() async {
    final payNow = (_quote?['pay_now_rwf'] as num?) ?? 0;
    Json details = {};
    if (payNow > 0) {
      final payment = buildPaymentDetails(_method, phone: _phone.text, cardNumber: _card.text, cardExpiry: _expiry.text, cardCvv: _cvv.text);
      if (payment.error != null) return setState(() => _error = payment.error);
      details = payment.details!;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<CustomerApi>().switchToDelivery(widget.order.id, {'delivery_location': _where(), 'payment_method': _method, 'payment_details': details});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<ClientLocation>();
    final quote = _quote;
    final payNow = (quote?['pay_now_rwf'] as num?) ?? 0;
    final addressOk = _street.text.trim().length >= 3;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Get it delivered instead', style: kText(18, weight: w900)),
        Text("Can't collect ${widget.order.orderNumber}? A delivery worker brings it to you. You only pay the delivery fee.", style: kText(12, color: K.stone500)),
        const SizedBox(height: 14),
        const FieldLabel('Deliver to'),
        Row(children: [
          const Icon(Icons.location_on_outlined, color: K.brown500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(location.isGps ? 'My current location' : location.label, style: kText(13, weight: FontWeight.w700)),
              Text(location.isLocated ? 'The delivery worker comes to this spot.' : 'Share your location so the worker can find you.', style: kText(11, color: K.stone500)),
            ]),
          ),
          OutlineAction(
            label: location.status == LocationStatus.requesting ? 'Locating…' : 'Use my location',
            icon: Icons.my_location,
            dense: true,
            onTap: location.status == LocationStatus.requesting
                ? null
                : () async {
                    if (!await location.requestGps() && context.mounted) showMarketSnack(context, 'Could not get your location. Allow location access and try again.');
                  },
          ),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _street, maxLength: 120, onChanged: (_) => setState(() {}), decoration: marketInput('Street, building or landmark').copyWith(counterText: '')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _area, maxLength: 80, decoration: marketInput('Area (e.g. Kimironko)').copyWith(counterText: ''))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _note, maxLength: 200, decoration: marketInput('Note for the worker').copyWith(counterText: ''))),
        ]),
        const SizedBox(height: 12),
        if (_quoting)
          Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text('Working out the delivery fee…', style: kText(12, color: K.stone500))])
        else if (quote != null) ...[
          MoneyRow('Distance', '${quote['distance_km']} km'),
          MoneyRow('Delivery fee', rwf((quote['delivery_fee_rwf'] as num?) ?? 0)),
          MoneyRow('New order total', rwf((quote['new_total_rwf'] as num?) ?? 0), strong: true),
          if (payNow == 0) Text("Your order isn't paid yet — the fee is added to what you pay.", style: kText(11, color: K.stone500)),
        ] else
          Text("Couldn't price the delivery for this location.", style: kText(12, color: K.stone500)),
        if (payNow > 0) ...[
          const SizedBox(height: 12),
          FieldLabel('Pay ${rwf(payNow)} with'),
          PaymentFields(method: _method, onMethod: (m) => setState(() => _method = m), phone: _phone, card: _card, expiry: _expiry, cvv: _cvv),
        ],
        if (_error != null) ...[const SizedBox(height: 10), Notice(_error!)],
        const SizedBox(height: 10),
        Text('Your pickup code stops working and you get a delivery code instead. The kitchen is told right away.', style: kText(11, color: K.stone500)),
        const SizedBox(height: 10),
        GradientButton(
          label: _busy ? 'Switching…' : payNow > 0 ? 'Pay ${rwf(payNow)} & get it delivered' : 'Get it delivered',
          onTap: _busy || _quoting || quote == null || !addressOk ? null : _confirm,
        ),
        if (!addressOk) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Add a street, building or landmark so the worker can find you.', style: kText(11, color: K.amber800))),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      ]),
    );
  }
}

/// Directions to the kitchen on our own map: the customer's position, the
/// road route, distance, time and the steps (the website's KitchenDirectionsModal).
Future<void> showDirections(BuildContext context, {required double lat, required double lng, required String name, String address = ''}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: _Directions(lat: lat, lng: lng, name: name, address: address)),
    );

class _Directions extends StatefulWidget {
  const _Directions({required this.lat, required this.lng, required this.name, required this.address});

  final double lat;
  final double lng;
  final String name;
  final String address;

  @override
  State<_Directions> createState() => _DirectionsState();
}

class _DirectionsState extends State<_Directions> {
  Json? _route;
  bool _loading = false;
  String? _error;
  late final ClientLocation _location;
  String _routedFrom = '';

  @override
  void initState() {
    super.initState();
    _location = context.read<ClientLocation>();
    _location.addListener(_reroute);
    if (!_location.isLocated) _location.requestGps();
    _reroute();
  }

  @override
  void dispose() {
    _location.removeListener(_reroute);
    super.dispose();
  }

  Future<void> _reroute() async {
    if (!_location.isLocated) return;
    final from = '${_location.lat},${_location.lng}';
    if (from == _routedFrom) return;
    _routedFrom = from;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final route = await context.read<CustomerApi>().route(_location.lat, _location.lng, widget.lat, widget.lng);
      if (mounted) setState(() => _route = route);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<ClientLocation>();
    final route = _route;
    final steps = (route?['steps'] is List ? route!['steps'] as List : const []).whereType<Map>().where((s) => '${s['instruction'] ?? ''}'.isNotEmpty).toList();
    String distance(num m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
    String duration(num s) {
      final minutes = (s / 60).round().clamp(1, 1 << 30);
      return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
    }

    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
      Text('Directions to ${widget.name}', style: kText(18, weight: w900)),
      if (widget.address.isNotEmpty) Text(widget.address, style: kText(12, color: K.stone500)),
      const SizedBox(height: 8),
      if (route != null)
        Text('${distance((route['distance_m'] as num?) ?? 0)} · about ${duration((route['duration_s'] as num?) ?? 0)} by road', style: kText(13, weight: FontWeight.w700, color: K.brown750))
      else if (_loading)
        Text('Finding the way…', style: kText(12, color: K.stone500)),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LiveRouteMap(
          rider: location.isLocated ? LatLng(location.lat, location.lng) : null,
          kitchen: LatLng(widget.lat, widget.lng),
          geometry: route?['geometry'] as List?,
          height: 320,
        ),
      ),
      if (!location.isLocated) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('Share your location to see the way from where you are.', style: kText(12, color: K.stone600))),
          OutlineAction(label: location.status == LocationStatus.requesting ? 'Locating…' : 'Use my location', dense: true, onTap: () => location.requestGps()),
        ]),
      ] else
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: () => location.requestGps(), icon: const Icon(Icons.my_location, size: 16), label: const Text('Update my position')),
        ),
      if (_error != null) ...[const SizedBox(height: 8), Notice(_error!)],
      if (route?['source'] == 'straight') ...[
        const SizedBox(height: 8),
        const Notice('Road directions are unavailable right now — the line shows the straight way to the kitchen.', tone: NoticeTone.warning),
      ],
      for (final step in steps)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.turn_right, color: K.brown500),
          title: Text('${step['instruction']}', style: kText(12.5, weight: FontWeight.w600)),
          trailing: (step['distance_m'] is num && (step['distance_m'] as num) > 0) ? Text(distance(step['distance_m'] as num), style: kText(11, color: K.stone500)) : null,
        ),
    ]);
  }
}

/// Order History & Receipts (the website's `/orders`): every order with its
/// status, refund, live tracking, contact, details and "Reorder Dishes".
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Future<void> _reorder(BuildContext context, CustomerOrder order) async {
    final kitchen = KitchenRef(id: order.vendorId, name: order.vendorName, typeCode: order.vendorTypeCode, neighborhood: order.vendorLocation);
    for (final item in order.items) {
      final dish = MenuDish(id: item.dishId, name: item.name, description: '', price: item.price, image: item.image, category: '', isAvailable: true, isPreorder: false, preorderCutoff: '', popular: false, prepTime: '');
      if (!await addDishToCart(context, dish, kitchen, quantity: item.quantity, announce: false)) {
        if (context.mounted) showMarketSnack(context, 'Could not add the complete order to your basket.');
        return;
      }
    }
    if (context.mounted) await MarketNav.checkout(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSession>();
    final orders = context.watch<Orders>();
    return MarketPage(
      title: 'Order History & Receipts',
      subtitle: 'Review past meals, reorder favorites, and track live deliveries',
      body: !session.isSignedIn
          ? SignInPrompt(icon: Icons.receipt_long_outlined, title: 'Sign in to see your orders', message: 'Your past and live orders show up here.', onSignIn: () => MarketNav.requireSignIn(context))
          : RefreshIndicator(
              onRefresh: orders.refresh,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (orders.error != null) ...[
                  Notice(orders.error!, icon: Icons.error_outline),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: orders.refresh, child: const Text('Retry'))),
                ],
                if (!orders.loaded)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (orders.orders.isEmpty)
                  EmptyCard(
                    icon: Icons.shopping_bag_outlined,
                    title: 'No orders yet',
                    message: 'Explore delicious home cooked meals and Kigali kitchens today!',
                    actionLabel: 'Start Ordering',
                    onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  )
                else
                  for (final order in orders.orders) _OrderCard(order: order, onReorder: () => _reorder(context, order)),
              ]),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onReorder});

  final CustomerOrder order;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt;
    final refund = order.refund;
    final (bg, fg) = order.isLive
        ? (K.brown100, K.brown850)
        : order.status == 'cancelled'
            ? (K.red100, const Color(0xFF991B1B))
            : (const Color(0xFFD1FAE5), const Color(0xFF065F46));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(radius: 18, backgroundColor: K.brown50, child: Icon(Icons.soup_kitchen_outlined, size: 18, color: K.brown700)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(order.vendorName, style: kText(15, weight: w900)),
                Text('${order.orderNumber}${created == null ? '' : ' · ${formatScheduledFor(created.toIso8601String())}'}', style: kText(11, color: K.stone500)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusPill('● ${orderStatusLabel(order.status)}', background: bg, foreground: fg),
            if (refund != null)
              StatusPill(
                '${refund['status_label'] ?? 'Refund'}',
                background: refund['status'] == 'completed' ? const Color(0xFFECFDF5) : refund['status'] == 'failed' ? const Color(0xFFFFF1F2) : const Color(0xFFF0F9FF),
                foreground: refund['status'] == 'completed' ? const Color(0xFF047857) : refund['status'] == 'failed' ? const Color(0xFFBE123C) : const Color(0xFF0369A1),
              ),
          ]),
          const SizedBox(height: 10),
          for (final item in order.items) MoneyRow('${item.quantity}x ${item.name}', rwf(item.price * item.quantity)),
          const Divider(height: 18, color: K.stone100),
          Text('Total: ${rwf(order.total)} via ${order.paymentMethod}', style: kText(12.5, weight: FontWeight.w700, color: K.stone700)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (order.isLive) GradientButton(label: 'Track Live', icon: Icons.schedule, expand: false, height: 38, fontSize: 12, onTap: () => MarketNav.order(context, order.id)),
            OutlineAction(label: 'View Details & Tracking', dense: true, onTap: () => MarketNav.order(context, order.id)),
            OutlineAction(label: 'Reorder Dishes', icon: Icons.replay, dense: true, color: K.brown700, onTap: onReorder),
            OutlineAction(label: 'Message kitchen', icon: Icons.chat_bubble_outline, dense: true, onTap: () => MarketNav.messageKitchen(context, order.vendorId)),
            if (order.vendorPhone.isNotEmpty) OutlineAction(label: 'Call kitchen', icon: Icons.phone_outlined, dense: true, onTap: () => showCallSheet(context, phone: order.vendorPhone, who: order.vendorName)),
          ]),
        ]),
      ),
    );
  }
}

