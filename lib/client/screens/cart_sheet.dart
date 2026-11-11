import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_theme.dart';
import '../customer_api.dart';
import '../../ui/vendor_types.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';

/// Adds a dish, asking "Start a new basket?" when the basket holds another
/// kitchen's dishes (the website's vendor-conflict modal). True when added.
Future<bool> addDishToCart(BuildContext context, MenuDish dish, KitchenRef kitchen, {int quantity = 1, bool announce = true}) async {
  final cart = context.read<Cart>();
  if (cart.add(dish, kitchen, quantity: quantity) == AddResult.added) {
    if (announce && context.mounted) showMarketSnack(context, '${dish.name} added to cart');
    return true;
  }
  final current = cart.vendor?.name ?? 'another kitchen';
  final replace = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: K.surface,
      title: Text('Start a new basket?', style: kText(18, weight: w900)),
      content: Text(
        'Your basket already contains items from $current. Do you want to clear your current basket and start fresh with items from ${kitchen.name}?',
        style: kText(13, color: K.stone600, height: 1.5),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('Keep Current', style: kText(13, weight: FontWeight.w700, color: K.stone600))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: K.fillBrown700),
          onPressed: () => Navigator.pop(dialog, true),
          child: Text('Start New Basket', style: kText(13, weight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    ),
  );
  if (replace == true) {
    cart.replaceWith();
    if (announce && context.mounted) showMarketSnack(context, '${dish.name} added to cart');
    return true;
  }
  cart.cancelConflict();
  return false;
}

/// The basket (the website's CartDrawer): when the order comes, the dishes
/// with quantities, the totals and "Proceed to Checkout".
Future<void> showCartSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.tone(const Color(0xFFFAF7F4)),
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: _CartBody()),
    );

class _CartBody extends StatelessWidget {
  const _CartBody();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final media = context.read<CustomerApi>().media;
    final rules = cart.rules;
    final problem = cart.ruleProblem;
    final advanceOnly = rules != null && !rules.orderNow;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Row(children: [
        Icon(Icons.shopping_bag_outlined, color: K.brown700),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your basket', style: kText(18, weight: w900)),
            Text(
              cart.syncing ? 'Syncing basket with your account…' : '${cart.itemCount} ${cart.itemCount == 1 ? 'dish' : 'dishes'} selected',
              style: kText(11, color: K.stone500),
            ),
          ]),
        ),
        if (cart.lines.isNotEmpty)
          IconButton(tooltip: 'Clear basket', onPressed: cart.clear, icon: const Icon(Icons.delete_outline, color: K.red500)),
        IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: K.stone500)),
      ]),
    );

    if (cart.lines.isEmpty) {
      return Column(children: [
        header,
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            EmptyCard(
              icon: Icons.shopping_bag_outlined,
              title: 'Your basket is empty',
              message: "Discover delicious dishes prepared by Kigali's home cooks, bakers, and restaurants.",
              actionLabel: 'Explore Kitchens',
              onAction: () => Navigator.pop(context),
            ),
          ]),
        ),
      ]);
    }

    return Column(children: [
      header,
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          if (cart.error != null) ...[
            GestureDetector(onTap: cart.clearError, child: Notice(cart.error!, icon: Icons.error_outline)),
            const SizedBox(height: 10),
          ],
          if (cart.vendor != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(Icons.storefront_outlined, size: 16, color: K.brown500),
                const SizedBox(width: 6),
                Expanded(child: Text(cart.vendor!.name, style: kText(13, weight: w900))),
              ]),
            ),
          // When the order comes.
          Panel(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FieldLabel('Delivery timing'),
              if (advanceOnly) ...[
                Notice('${vendorTypeOf(rules.vendorType).label} kitchens take advance orders only — order at least ${formatLead(rules.minLeadMinutes)} ahead.', tone: NoticeTone.warning),
                const SizedBox(height: 8),
              ],
              Row(children: [
                if (!advanceOnly) ...[
                  Expanded(child: _TimingChip(label: 'Order for Now', icon: Icons.bolt, active: cart.orderType == 'immediate', onTap: () => cart.setOrderType('immediate'))),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _TimingChip(label: 'Schedule / Pre-Order', icon: Icons.calendar_month_outlined, active: cart.orderType == 'scheduled', onTap: () => cart.setOrderType('scheduled')),
                ),
              ]),
              if (cart.orderType == 'scheduled') ...[
                const SizedBox(height: 10),
                if (cart.days.isEmpty)
                  const Notice('This kitchen has no free time slots in its booking window right now.', tone: NoticeTone.warning)
                else
                  Row(children: [
                    Expanded(
                      child: _Picker(
                        value: cart.days.any((d) => d.value == cart.scheduledDate) ? cart.scheduledDate : cart.days.first.value,
                        items: {for (final d in cart.days) d.value: d.label},
                        onChanged: (v) => cart.setSchedule(day: v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Picker(
                        value: cart.slots.contains(cart.scheduledTime) ? cart.scheduledTime : (cart.slots.isEmpty ? null : cart.slots.first),
                        items: {for (final s in cart.slots) s: s},
                        onChanged: (v) => cart.setSchedule(time: v),
                      ),
                    ),
                  ]),
              ],
              if (cart.orderType == 'preorder' && cart.preorder != null) ...[
                const SizedBox(height: 10),
                Notice(
                  '${cart.preorder!.text}\nOrder before ${formatScheduledFor(cart.preorder!.cutoffAt)} · Arrives by ${formatScheduledFor(cart.preorder!.deliveryAt)}',
                  tone: NoticeTone.brand,
                  icon: Icons.restaurant_menu,
                ),
                TextButton(
                  onPressed: () => cart.setOrderType('immediate'),
                  child: Text('Cancel pre-order (switch to immediate)', style: kText(12, weight: FontWeight.w700, color: K.brown700)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          for (final line in cart.lines) _LineTile(line: line, media: media),
        ]),
      ),
      // Totals and checkout.
      Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.stone200))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MoneyRow('Items Subtotal', rwf(cart.subtotal)),
          MoneyRow(cart.feeLabel, cart.feeValue),
          MoneyRow('Total Amount', rwf(cart.total), strong: true),
          if (problem != null) ...[const SizedBox(height: 8), Notice(problem, tone: NoticeTone.warning)],
          const SizedBox(height: 10),
          GradientButton(
            label: 'Proceed to Checkout',
            icon: Icons.arrow_forward,
            onTap: cart.syncing || problem != null
                ? null
                : () {
                    Navigator.pop(context);
                    MarketNav.checkout(context);
                  },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Continue shopping', style: kText(12, weight: FontWeight.w700, color: K.stone600))),
        ]),
      ),
    ]);
  }
}

class _TimingChip extends StatelessWidget {
  const _TimingChip({required this.label, required this.icon, required this.active, required this.onTap});

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? K.brown800 : K.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: active ? K.brown900 : K.stone200)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 14, color: active ? Colors.white : K.stone600),
              const SizedBox(width: 4),
              Flexible(child: Text(label, textAlign: TextAlign.center, style: kText(11.5, weight: FontWeight.w700, color: active ? Colors.white : K.stone700))),
            ]),
          ),
        ),
      );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.value, required this.items, required this.onChanged});

  final String? value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: marketInput(''),
        style: kText(13, weight: FontWeight.w700),
        items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.media});

  final CartLine line;
  final String? Function(String) media;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<Cart>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          SizedBox(width: 64, child: NetImage(url: media(line.image), aspect: 1, radius: BorderRadius.circular(14))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: kText(13.5, weight: w900)),
              if (!line.isAvailable) Text('Sold out now', style: kText(11, weight: FontWeight.w700, color: K.red500)),
              const SizedBox(height: 4),
              Text(rwf(line.price * line.quantity), style: kText(13, weight: w900, color: K.brown750)),
            ]),
          ),
          QuantityStepper(value: line.quantity, label: line.name, onChanged: (q) => cart.setQuantity(line.dishId, q)),
        ]),
      ),
    );
  }
}
