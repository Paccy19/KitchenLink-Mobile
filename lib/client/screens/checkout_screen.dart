import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/home_bars.dart';
import '../widgets/market_ui.dart';

/// Checkout & Confirmation (the website's `/checkout`): delivery or pickup
/// with the address, when it comes, payment, notes, and the summary with
/// "Place order".
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String? _addressId;
  String _method = 'mobile_money';
  final _phone = TextEditingController();
  final _card = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;
  late final CustomerSession _session;

  @override
  void initState() {
    super.initState();
    final session = _session = context.read<CustomerSession>();
    _addressId = session.defaultAddress?.id;
    _phone.text = localPhone(session.phone);
    session.addListener(_onSession);
  }

  /// Signing in on this page fills the Mobile Money number, unless one was typed.
  void _onSession() {
    final session = _session;
    if (_phone.text.isEmpty && session.phone.isNotEmpty) _phone.text = localPhone(session.phone);
    _addressId ??= session.defaultAddress?.id;
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    for (final c in [_phone, _card, _expiry, _cvv, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cart = context.read<Cart>();
    final session = context.read<CustomerSession>();
    final location = context.read<ClientLocation>();
    final api = context.read<CustomerApi>();
    final orders = context.read<Orders>();
    setState(() => _error = null);
    if (cart.syncing) return setState(() => _error = 'Please wait while your basket syncs with your account.');
    if (!session.isSignedIn) {
      await MarketNav.requireSignIn(context);
      return;
    }
    final address = session.addresses.where((a) => a.id == _addressId).firstOrNull ?? session.defaultAddress;
    if (!cart.isPickup && (address == null || address.street.isEmpty)) {
      return setState(() => _error = 'Add or select a delivery address before placing your order.');
    }
    if (!cart.isPickup && cart.unavailableReason != null) return setState(() => _error = cart.unavailableReason);
    if (!cart.isPickup && cart.deliveryFee == null) {
      return setState(() => _error = "We couldn't calculate the delivery fee for your location. Please check your location and try again.");
    }
    final problem = cart.ruleProblem;
    if (problem != null) return setState(() => _error = problem);
    final payment = buildPaymentDetails(_method, phone: _phone.text, cardNumber: _card.text, cardExpiry: _expiry.text, cardCvv: _cvv.text);
    if (payment.error != null) return setState(() => _error = payment.error);

    setState(() => _submitting = true);
    try {
      if (!await cart.waitForSync()) {
        if (mounted) setState(() => _error = 'Your basket changed. Please check it and confirm again.');
        return;
      }
      final notes = _notes.text.trim();
      final scheduled = cart.scheduledFor;
      final order = await api.checkout({
        'delivery_location': cart.isPickup
            ? {'note': notes}
            : {
                'address': address!.street,
                'neighborhood': address.district,
                'latitude': location.lat,
                'longitude': location.lng,
                'note': [address.instructions, notes].where((s) => s.isNotEmpty).join(' | '),
              },
        'payment_method': _method,
        'payment_details': payment.details,
        'order_type': cart.orderType,
        'fulfillment': cart.fulfillment,
        'scheduled_for': scheduled?.toUtc().toIso8601String(),
        'special_text': cart.orderType == 'preorder' ? cart.preorder?.text ?? '' : '',
      });
      // The order exists now: record it and empty the basket even if the
      // customer left this screen while it was being placed.
      orders.put(order);
      cart.clearAfterCheckout();
      if (!mounted) return;
      await MarketNav.orderAfterCheckout(context, order.id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final session = context.watch<CustomerSession>();
    final location = context.watch<ClientLocation>();
    if (cart.lines.isEmpty) {
      return MarketPage(
        title: 'Checkout',
        body: ListView(padding: const EdgeInsets.all(20), children: [
          EmptyCard(
            icon: Icons.error_outline,
            title: 'Your basket is currently empty',
            message: 'Add dishes from a kitchen before checking out.',
            actionLabel: 'Browse Menus',
            onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ]),
      );
    }
    return MarketPage(
      title: 'Checkout & Confirmation',
      subtitle: 'Choose delivery or pickup, review timing and pay safely in escrow',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _fulfillment(cart, session, location),
        const SizedBox(height: 14),
        _schedule(cart),
        const SizedBox(height: 14),
        _payment(),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(cart.isPickup ? 'Order notes for the kitchen' : 'Order notes / delivery instructions'),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: marketInput(cart.isPickup ? 'Any special notes for the kitchen (e.g. when you will come)...' : 'Any special notes for the kitchen or delivery worker...'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _summary(cart),
      ]),
    );
  }

  Widget _fulfillment(Cart cart, CustomerSession session, ClientLocation location) => StepPanel(
        step: 1,
        title: cart.isPickup ? 'Pickup at the kitchen' : 'Delivery Destination',
        action: cart.isPickup ? null : TextButton.icon(onPressed: _addAddress, icon: const Icon(Icons.add, size: 16), label: Text('Add Location', style: kText(12, weight: FontWeight.w700, color: K.brown700))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChoiceTile(selected: !cart.isPickup, onTap: () => cart.setFulfillment('delivery'), icon: Icons.pedal_bike, title: 'Deliver to me', subtitle: 'A delivery worker brings it'),
          const SizedBox(height: 8),
          ChoiceTile(selected: cart.isPickup, onTap: () => cart.setFulfillment('pickup'), icon: Icons.storefront_outlined, title: "I'll pick it up", subtitle: 'Collect at the kitchen · no delivery fee'),
          const SizedBox(height: 12),
          if (cart.isPickup)
            Notice(
              'Collect from ${cart.vendor?.name ?? 'the kitchen'}${(cart.vendor?.neighborhood ?? '').isNotEmpty ? ' · ${cart.vendor!.neighborhood}' : ''}\n'
              "When your food is ready we'll send you a 6-digit pickup code (it also shows on your order page). Give it to the kitchen when you collect your order.",
              tone: NoticeTone.brand,
              icon: Icons.storefront_outlined,
            )
          else ...[
            if (session.addresses.isEmpty)
              Notice(
                session.isSignedIn ? 'No saved address yet. Tap "Add Location" to add where the food should go.' : 'Add the address where the food should go (tap "Add Location").',
                tone: NoticeTone.warning,
                icon: Icons.location_off_outlined,
              )
            else
              for (final address in session.addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ChoiceTile(
                    selected: (_addressId ?? session.defaultAddress?.id) == address.id,
                    onTap: () => setState(() => _addressId = address.id),
                    icon: Icons.location_on_outlined,
                    title: '${address.title}${address.isDefault ? ' · Default' : ''}',
                    subtitle: [address.street, address.district, if (address.instructions.isNotEmpty) address.instructions].join(' · '),
                  ),
                ),
            const SizedBox(height: 4),
            // The delivery fee and the worker use the map position.
            Row(children: [
              Icon(Icons.my_location, size: 14, color: K.brown500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Drop-off point on the map: ${location.label}. The delivery fee and the worker use it — change it if it is not where you are.',
                  style: kText(11.5, weight: FontWeight.w600, color: K.stone600),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: LocationPill(location: location, onGpsUnavailable: () => showMarketSnack(context, 'Could not get your location. Allow location access, or pick a neighbourhood.')),
            ),
          ],
        ]),
      );

  Future<void> _addAddress() async {
    final added = await showAddressForm(context);
    if (added != null && mounted) setState(() => _addressId = added.id);
  }

  Widget _schedule(Cart cart) {
    final pickup = cart.isPickup;
    final label = cart.orderType == 'immediate'
        ? (pickup ? 'Pick up as soon as it is ready' : 'Immediate Delivery')
        : cart.orderType == 'preorder'
            ? (pickup ? 'Pre-Order · pickup' : 'Pre-Order')
            : (pickup ? 'Scheduled Pickup' : 'Scheduled Delivery');
    final scheduled = cart.scheduledFor;
    final description = cart.orderType == 'immediate'
        ? (pickup
            ? 'You get a pickup code right after ordering — it shows on your order page. Give it to the kitchen when you collect.'
            : 'Estimated delivery time: 25–35 minutes after kitchen preparation')
        : cart.orderType == 'preorder' && cart.preorder != null
            ? '${cart.preorder!.text} — ${pickup ? 'ready to collect' : 'arrives'} by ${scheduled == null ? '' : formatScheduledFor(scheduled.toIso8601String())}'
            : '${pickup ? 'Ready to collect' : 'Scheduled to arrive'}: ${scheduleDayLabel(cart.scheduledDate)} at ${cart.scheduledTime}';
    return StepPanel(
      step: 2,
      title: 'When',
      action: TextButton(onPressed: () => MarketNav.cart(context), child: Text('Change', style: kText(12, weight: FontWeight.w700, color: K.brown700))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.schedule, size: 18, color: K.brown700),
          const SizedBox(width: 8),
          Text(label, style: kText(14, weight: w900)),
        ]),
        const SizedBox(height: 6),
        Text(description, style: kText(12, color: K.stone600, height: 1.5)),
        if (cart.orderType == 'preorder' && cart.preorder != null) ...[
          const SizedBox(height: 6),
          Text('Order before ${formatScheduledFor(cart.preorder!.cutoffAt)} · you pay now, the kitchen is notified straight away', style: kText(11, color: K.stone500)),
        ],
        if (cart.orderType != 'immediate' && !pickup) ...[
          const SizedBox(height: 8),
          const Notice('Please keep this delivery time free — your delivery worker is dispatched close to the scheduled time.', tone: NoticeTone.info),
        ],
      ]),
    );
  }

  Widget _payment() => StepPanel(
        step: 3,
        title: 'Payment',
        child: PaymentFields(
          method: _method,
          onMethod: (m) => setState(() => _method = m),
          phone: _phone,
          card: _card,
          expiry: _expiry,
          cvv: _cvv,
        ),
      );

  Widget _summary(Cart cart) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Order Summary', style: kText(16, weight: w900)),
          if (cart.vendor != null) Text(cart.vendor!.name, style: kText(12, color: K.stone500)),
          const SizedBox(height: 10),
          for (final line in cart.lines) MoneyRow('${line.quantity}x ${line.name}', rwf(line.price * line.quantity)),
          Divider(height: 20, color: K.stone100),
          MoneyRow('Subtotal', rwf(cart.subtotal)),
          MoneyRow(cart.feeLabel, cart.feeValue),
          MoneyRow('Total', rwf(cart.total), strong: true),
          if (cart.unavailableReason != null) ...[const SizedBox(height: 8), Notice(cart.unavailableReason!, tone: NoticeTone.warning)],
          if (cart.kitchenDelivers) ...[
            const SizedBox(height: 8),
            const Notice('You are beyond the delivery workers\' range: the kitchen brings this order itself, so it must be scheduled ahead.', tone: NoticeTone.info),
          ],
          if ((_error ?? cart.error) != null) ...[const SizedBox(height: 10), Notice((_error ?? cart.error)!, icon: Icons.error_outline)],
          const SizedBox(height: 14),
          GradientButton(
            label: _submitting ? 'Placing your order…' : 'Place order · ${rwf(cart.total)}',
            icon: Icons.lock_outline,
            onTap: _submitting || cart.syncing || cart.quoteLoading ? null : _placeOrder,
          ),
          const SizedBox(height: 8),
          Text('Your money is held safely until your food is delivered or collected.', textAlign: TextAlign.center, style: kText(11, color: K.stone500)),
        ]),
      );
}

/// Payment method choice and its fields (the website's PaymentSection).
class PaymentFields extends StatelessWidget {
  const PaymentFields({super.key, required this.method, required this.onMethod, required this.phone, required this.card, required this.expiry, required this.cvv});

  final String method;
  final ValueChanged<String> onMethod;
  final TextEditingController phone;
  final TextEditingController card;
  final TextEditingController expiry;
  final TextEditingController cvv;

  static const _icons = {'mobile_money': Icons.smartphone, 'card': Icons.credit_card, 'ekash': Icons.toll_outlined, 'wallet': Icons.account_balance_wallet_outlined};

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final m in paymentMethods)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoiceTile(selected: method == m.code, onTap: () => onMethod(m.code), icon: _icons[m.code], title: m.label, subtitle: m.hint),
          ),
        const SizedBox(height: 4),
        if (method == 'card') ...[
          TextField(
            controller: card,
            keyboardType: TextInputType.number,
            decoration: marketInput('Card number', prefix: const Icon(Icons.credit_card, size: 18)),
            onChanged: (v) {
              final formatted = formatCardNumber(v);
              if (formatted != v) card.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: expiry,
                keyboardType: TextInputType.number,
                decoration: marketInput('MM/YY'),
                onChanged: (v) {
                  final formatted = formatCardExpiry(v);
                  if (formatted != v) expiry.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: cvv, keyboardType: TextInputType.number, obscureText: true, maxLength: 4, decoration: marketInput('CVV').copyWith(counterText: ''))),
          ]),
        ] else
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 13,
            decoration: marketInput(method == 'mobile_money' ? 'MTN or Airtel number, e.g. 0788123456' : 'Phone number, e.g. 0788123456', prefix: const Icon(Icons.phone_outlined, size: 18))
                .copyWith(counterText: ''),
          ),
      ]);
}

/// "Add Location": a label, the area, the street or landmark and a note for
/// the worker, saved on this device (like the website).
Future<SavedAddress?> showAddressForm(BuildContext context) => showModalBottomSheet<SavedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: K.surface,
      showDragHandle: true,
      builder: (_) => const _AddressForm(),
    );

class _AddressForm extends StatefulWidget {
  const _AddressForm();

  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _title = TextEditingController(text: 'Home');
  final _district = TextEditingController();
  final _street = TextEditingController();
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _district, _street, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Kigali areas matching what is typed (the website's datalist).
  Widget _areaSuggestions() {
    final q = _district.text.trim().toLowerCase();
    final areas = [for (final n in kigaliNeighborhoods) n.name, ...kigaliDistricts];
    final matches = areas.where((a) => a.toLowerCase().contains(q) && a.toLowerCase() != q).take(6).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final area in matches)
          ActionChip(
            label: Text(area, style: kText(11.5, weight: FontWeight.w600, color: K.stone700)),
            backgroundColor: K.stone50,
            side: BorderSide(color: K.stone200),
            onPressed: () => setState(() => _district.text = area),
          ),
      ]),
    );
  }

  void _save() {
    if (_street.text.trim().isEmpty) return setState(() => _error = 'Please specify your street address');
    if (_district.text.trim().isEmpty) return setState(() => _error = 'Please enter your area (e.g. Kicukiro, Nyamirambo)');
    final address = context.read<CustomerSession>().addAddress(title: _title.text, street: _street.text, district: _district.text, instructions: _notes.text);
    Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add New Address in Kigali', style: kText(17, weight: w900)),
          const SizedBox(height: 14),
          TextField(controller: _title, decoration: marketInput('Label (e.g. Home, Work)')),
          const SizedBox(height: 8),
          TextField(controller: _district, maxLength: 80, onChanged: (_) => setState(() {}), decoration: marketInput('Area (any part of Kigali)').copyWith(counterText: '')),
          _areaSuggestions(),
          const SizedBox(height: 8),
          TextField(controller: _street, decoration: marketInput('Street name / Landmark')),
          const SizedBox(height: 8),
          TextField(controller: _notes, decoration: marketInput('Notes for the delivery worker (gate color, doorbell, etc.)')),
          if (_error != null) ...[const SizedBox(height: 10), Notice(_error!)],
          const SizedBox(height: 14),
          GradientButton(label: 'Save', onTap: _save),
        ]),
      );
}
