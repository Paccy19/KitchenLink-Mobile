import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/motion.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';
import 'cart_sheet.dart';

/// What each kitchen type is like (the website's vendor type notes).
const _typeNotes = {
  'home_cook': 'Best for homemade food with limited daily slots.',
  'restaurant': 'Classic full-service kitchen.',
  'cafe': 'Casual and daytime-focused.',
  'bakery': 'Can still sell savoury items.',
  'caterer': 'Strong with Offer Days and pre-orders.',
  'food_truck': 'Location can change.',
  'chef': 'More personalised and higher-end.',
  'meal_prep': 'Best with recurring orders.',
  'juice_drinks': 'Can still sell light food.',
  'other': 'Catch-all for unique businesses — fully open.',
};

/// A kitchen's page (the website's `/vendor/:id`): banner, details, how it
/// takes orders, its "Tomorrow's Special", the menu by category with
/// add-to-basket and save, and the basket bar.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key, required this.vendorId, this.openDishId});

  final String vendorId;

  /// A dish to open straight away (from search or the homepage).
  final String? openDishId;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  Storefront? _store;
  Object? _error;
  bool _loading = true;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await context.read<CustomerApi>().storefront(widget.vendorId, context.read<ClientLocation>());
      if (!mounted) return;
      setState(() => _store = store);
      final dish = store.menu.where((d) => d.id == widget.openDishId).firstOrNull;
      if (dish != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? showDishSheet(context, dish, store.ref) : null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return MarketPage(
        title: 'Kitchen',
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                if (_error is ApiException && (_error as ApiException).status == 404)
                  EmptyCard(
                    icon: Icons.no_meals_outlined,
                    title: 'Kitchen not found',
                    message: 'This kitchen may have been removed or the link is incorrect.',
                    actionLabel: 'Browse nearby kitchens',
                    onAction: () => MarketNav.kitchens(context),
                  )
                else
                  ErrorCard(title: 'Storefront unavailable', message: _error?.toString() ?? 'We could not load this kitchen right now.', onRetry: _load, retrying: _loading),
              ]),
      );
    }

    final cart = context.watch<Cart>();
    final wishlist = context.watch<Wishlist>();
    final orders = context.watch<Orders>();
    final media = context.read<CustomerApi>().media;
    final vendor = store.vendor;
    final kitchen = store.ref;
    final categories = ['All', ...store.categories];
    final menu = _category == 'All' ? store.menu : store.menu.where((d) => d.category == _category).toList();
    final mine = cart.lines.where((l) => l.vendorId == vendor.id).toList();
    final mineTotal = mine.fold<num>(0, (s, l) => s + l.price * l.quantity);
    final orderHere = orders.withKitchen(vendor.id);
    final special = vendor.special;
    final preorderOn = cart.orderType == 'preorder' && cart.preorder?.vendorId == vendor.id;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: K.tone(const Color(0xFFFAF7F4)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            backgroundColor: K.brown900,
            foregroundColor: Colors.white,
            leading: Navigator.canPop(context) ? Center(child: _glass(Icons.arrow_back_ios_new_rounded, 'Back', () => Navigator.of(context).maybePop())) : null,
            actions: [
              _glass(Icons.shopping_bag_outlined, 'View cart', () => MarketNav.cart(context), count: cart.itemCount),
              const SizedBox(width: 12),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                Container(decoration: const BoxDecoration(gradient: K.logoGradient)),
                if (media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl) != null)
                  Image.network(media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl)!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xD9000000), Color(0x73000000), Color(0x40000000)])),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      VendorTypeBadge(vendor.typeCode),
                      if (!vendor.isOpen) const Pill('Closed now · schedule for later', background: K.fillStone700, foreground: Colors.white),
                      if (vendor.deliveryAvailable) const Pill('Delivery', icon: Icons.delivery_dining_rounded, background: Color(0xE6FFFFFF), foreground: K.forest600),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      VendorAvatar(vendor: vendor, media: media, size: 52),
                      const SizedBox(width: 12),
                      Expanded(child: Text(vendor.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: kDisplay(28, color: Colors.white))),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _fact(Icons.star, vendor.rating > 0 ? '${numText(vendor.rating)}${vendor.reviewsCount > 0 ? ' (${vendor.reviewsCount} reviews)' : ''}' : 'New', iconColor: K.amber400),
                      _fact(Icons.schedule, '${vendor.prepTime} prep'),
                      _fact(Icons.location_on_outlined, vendor.neighborhood),
                      if (vendor.deliveryFee > 0) _fact(Icons.pedal_bike, '${formatRwf(vendor.deliveryFee)} delivery'),
                    ]),
                    const SizedBox(height: 12),
                    // Only customers who have ordered here can message or call the kitchen.
                    if (orderHere != null)
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlineAction(label: 'Message kitchen', icon: Icons.chat_bubble_outline, dense: true, onTap: () => MarketNav.messageKitchen(context, vendor.id)),
                        if (orderHere.vendorPhone.isNotEmpty)
                          OutlineAction(label: 'Call kitchen', icon: Icons.phone_outlined, dense: true, color: K.brown700, onTap: () => showCallSheet(context, phone: orderHere.vendorPhone, who: vendor.name)),
                      ])
                    else
                      Row(children: [
                        Icon(Icons.chat_bubble_outline, size: 13, color: K.stone400),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Place an order to message or call this kitchen', style: kText(11, weight: FontWeight.w600, color: K.stone400))),
                      ]),
                    const SizedBox(height: 12),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${vendorTypeOf(vendor.typeCode).label}: ', style: kText(12, weight: FontWeight.w700, color: K.stone700)),
                      TextSpan(text: _typeNotes[vendor.typeCode] ?? '', style: kText(12, color: K.stone500)),
                    ])),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final line in store.ordering.lines)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: K.stone100, borderRadius: BorderRadius.circular(99)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.event_available, size: 12, color: K.stone600),
                            const SizedBox(width: 4),
                            Text(line, style: kText(11, weight: FontWeight.w600, color: K.stone600)),
                          ]),
                        ),
                    ]),
                    if (store.ordering.fullyBookedToday) ...[
                      const SizedBox(height: 8),
                      const Notice('Fully booked today — you can still schedule your order for another day.', tone: NoticeTone.warning),
                    ],
                    if (vendor.description.isNotEmpty) ...[
                      Divider(height: 28, color: K.stone100),
                      Text(vendor.description, style: kText(13, color: K.stone600, height: 1.6)),
                    ],
                  ]),
                ),
                if (special != null) ...[
                  const SizedBox(height: 16),
                  _specialBanner(special, store, preorderOn),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final active = categories[i] == _category;
                      return ChoiceChip(
                        label: Text(categories[i]),
                        selected: active,
                        showCheckmark: false,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _category = categories[i]);
                        },
                        labelStyle: kText(13, weight: FontWeight.w700, color: active ? K.onStrong : K.stone700),
                        selectedColor: K.strong,
                        backgroundColor: K.dark ? K.surface : K.stone100,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_category != 'All')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('$_category  ·  ${menu.length} ${menu.length == 1 ? 'item' : 'items'}', style: kText(16, weight: w900)),
                  ),
              ]),
            ),
          ),
          if (menu.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: EmptyCard(
                  icon: Icons.no_meals_outlined,
                  title: _category == 'All' ? 'No dishes on the menu yet' : 'No $_category dishes right now',
                  message: 'Check back soon — menus change daily.',
                  actionLabel: _category == 'All' ? null : 'Show full menu',
                  onAction: () => setState(() => _category = 'All'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 286),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DishTile(dish: menu[i], kitchen: kitchen, media: media, saved: wishlist.contains(menu[i].id)),
                  childCount: menu.length,
                ),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: _basketBar(mine.length, mineTotal, cart.itemCount, vendor.name),
    );
  }

  /// A frosted round button over the kitchen's photo.
  Widget _glass(IconData icon, String tooltip, VoidCallback onTap, {int count = 0}) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: count > 0 ? '$tooltip, $count dishes' : tooltip,
          excludeSemantics: true,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Material(
                color: Colors.black.withValues(alpha: 0.28),
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      backgroundColor: const Color(0xFFDDAE7E),
                      textColor: K.brown950,
                      offset: const Offset(-2, 2),
                      alignment: Alignment.topRight,
                      child: Center(child: Icon(icon, size: 19, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _fact(IconData icon, String text, {Color? iconColor}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: iconColor ?? K.brown500),
        const SizedBox(width: 5),
        Text(text, style: kText(13, weight: FontWeight.w700, color: K.stone700)),
      ]);

  Widget _specialBanner(Special special, Storefront store, bool preorderOn) {
    final cart = context.read<Cart>();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: K.brown100,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Pill("Tomorrow's special", icon: Icons.schedule_rounded, background: Color(0xFFDDAE7E), foreground: K.brown950),
        const SizedBox(height: 10),
        Text(special.text, style: kDisplay(21, color: K.brown850)),
        const SizedBox(height: 6),
        Text('Order before ${formatScheduledFor(special.cutoffAt)}  ·  Arrives ${formatScheduledFor(special.deliveryAt)}', style: kText(12, weight: FontWeight.w600, color: K.stone600)),
        const SizedBox(height: 12),
        preorderOn
            ? OutlineAction(label: 'Pre-order on · Cancel', icon: Icons.close, onTap: () => cart.setOrderType('immediate'))
            : GradientButton(
                label: 'Pre-order this special',
                expand: false,
                height: 44,
                onTap: store.specialOrderable
                    ? () {
                        cart.startPreorder(PreorderSpecial(vendorId: store.vendor.id, vendorName: store.vendor.name, text: special.text, cutoffAt: special.cutoffAt, deliveryAt: special.deliveryAt));
                        showMarketSnack(context, 'Pre-order on — add dishes from ${store.vendor.name} to your basket.');
                      }
                    : null,
              ),
      ]),
    );
  }

  Widget _basketBar(int lines, num total, int count, String name) => Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.stone200, width: 0.6))),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lines > 0 ? '$lines item${lines > 1 ? 's' : ''} from $name' : 'Hungry?', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11.5, weight: FontWeight.w600, color: K.stone500)),
              Text(lines > 0 ? formatRwf(total) : 'Add dishes from the menu above', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(16, weight: w900, color: lines > 0 ? K.brown750 : K.gray900).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(width: 12),
          GradientButton(label: count > 0 ? 'View basket · $count' : 'View basket', icon: Icons.shopping_bag_outlined, expand: false, onTap: count == 0 ? null : () => MarketNav.cart(context)),
        ]),
      );
}

class _DishTile extends StatelessWidget {
  const _DishTile({required this.dish, required this.kitchen, required this.media, required this.saved});

  final MenuDish dish;
  final KitchenRef kitchen;
  final String? Function(String) media;
  final bool saved;

  @override
  Widget build(BuildContext context) => PressScale(
        pressedScale: 0.98,
        child: Material(
          color: K.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: K.stone200.withValues(alpha: 0.6))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showDishSheet(context, dish, kitchen),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  NetImage(url: media(dish.image), aspect: 1.15, radius: BorderRadius.circular(16)),
                  Positioned(top: 6, right: 6, child: SaveButton(dish: dish, kitchen: kitchen, saved: saved)),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Wrap(spacing: 4, children: [
                      if (!dish.isAvailable) Pill('SOLD OUT', background: K.fillStone800.withValues(alpha: 0.9), foreground: Colors.white, size: 9.5),
                      if (dish.popular) const Pill('POPULAR', background: Color(0xE62B1609), foreground: Color(0xFFFBF3EA), size: 9.5),
                      if (dish.isPreorder) const Pill('PRE-ORDER', background: Color(0xFFDDAE7E), foreground: K.brown950, size: 9.5),
                    ]),
                  ),
                ]),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 10, 2, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(dish.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: kText(14.5, weight: w900, height: 1.25, spacing: -0.2)),
                      if (dish.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(dish.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: kText(11.5, color: K.stone500, height: 1.35)),
                      ],
                      const Spacer(),
                      Row(children: [
                        Expanded(child: Text(formatRwf(dish.price), maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14.5, weight: w900, color: K.brown750).copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
                        Tooltip(
                          message: dish.isAvailable ? 'Add ${dish.name}' : 'Sold out',
                          child: Material(
                            color: dish.isAvailable ? K.fillBrown700 : K.stone200,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: dish.isAvailable
                                  ? () {
                                      HapticFeedback.lightImpact();
                                      addDishToCart(context, dish, kitchen);
                                    }
                                  : null,
                              child: SizedBox(width: 34, height: 34, child: Icon(Icons.add_rounded, size: 19, color: dish.isAvailable ? Colors.white : K.stone400)),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// The heart over a dish: save it for later or remove it.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.dish, required this.kitchen, required this.saved});

  final MenuDish dish;
  final KitchenRef kitchen;
  final bool saved;

  @override
  Widget build(BuildContext context) => Material(
        color: K.photoChip,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            final now = context.read<Wishlist>().toggle(dish, kitchen);
            showMarketSnack(context, now ? '${dish.name} saved for later' : '${dish.name} removed from your wishlist');
          },
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 17, color: saved ? K.rose600 : K.stone700, semanticLabel: saved ? 'Remove from wishlist' : 'Save to wishlist'),
          ),
        ),
      );
}

/// Dish details (the website's FoodItemModal): photo, price, description,
/// quantity, save, and "Add". [showKitchenLink] adds a link to the kitchen.
Future<void> showDishSheet(BuildContext context, MenuDish dish, KitchenRef kitchen, {bool showKitchenLink = false}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _DishSheet(dish: dish, kitchen: kitchen, showKitchenLink: showKitchenLink),
    );

class _DishSheet extends StatefulWidget {
  const _DishSheet({required this.dish, required this.kitchen, required this.showKitchenLink});

  final MenuDish dish;
  final KitchenRef kitchen;
  final bool showKitchenLink;

  @override
  State<_DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<_DishSheet> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final media = context.read<CustomerApi>().media;
    final saved = context.watch<Wishlist>().contains(dish.id);
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(children: [
          NetImage(url: media(dish.image), aspect: 16 / 10),
          Positioned(
            top: 10,
            right: 10,
            child: Row(children: [
              SaveButton(dish: dish, kitchen: widget.kitchen, saved: saved),
              const SizedBox(width: 8),
              Material(
                color: Colors.white.withValues(alpha: 0.95),
                shape: const CircleBorder(),
                child: IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
              ),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (dish.category.isNotEmpty) Text(dish.category.toUpperCase(), style: kText(11, weight: FontWeight.w700, color: K.brown500, spacing: 0.6)),
            Text(dish.name, style: kDisplay(28)),
            const SizedBox(height: 6),
            Row(children: [
              Text(formatRwf(dish.price), style: kText(18, weight: w900, color: K.brown750)),
              const SizedBox(width: 10),
              Expanded(child: Text('from ${widget.kitchen.name} · ${vendorTypeOf(widget.kitchen.typeCode).label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(12, color: K.stone500))),
            ]),
            if (dish.prepTime.isNotEmpty && dish.prepTime != '—') ...[
              const SizedBox(height: 6),
              Row(children: [Icon(Icons.schedule, size: 14, color: K.brown500), const SizedBox(width: 4), Text(dish.prepTime, style: kText(12, weight: FontWeight.w600, color: K.stone600))]),
            ],
            if (dish.description.isNotEmpty) ...[const SizedBox(height: 12), Text(dish.description, style: kText(13.5, color: K.stone600, height: 1.6))],
            if (dish.isPreorder) ...[
              const SizedBox(height: 12),
              Notice('Scheduled Pre-Order Special: ${dish.preorderCutoff.isEmpty ? 'Prepared specially for tomorrow' : dish.preorderCutoff}', tone: NoticeTone.brand, icon: Icons.auto_awesome),
            ],
            if (widget.showKitchenLink && widget.kitchen.id.isNotEmpty) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.storefront_outlined, color: K.brown700),
                title: Text('See all dishes from ${widget.kitchen.name}', style: kText(13, weight: FontWeight.w700)),
                subtitle: Text('Optional — you can add this dish right here', style: kText(11, color: K.stone500)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  MarketNav.kitchen(context, widget.kitchen.id);
                },
              ),
            ],
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.paddingOf(context).bottom),
          child: Row(children: [
            QuantityStepper(value: _quantity, min: 1, onChanged: (q) => setState(() => _quantity = q)),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: dish.isAvailable ? 'Add · ${formatRwf(dish.price * _quantity)}' : 'Sold out',
                icon: Icons.shopping_bag_outlined,
                onTap: dish.isAvailable
                    ? () async {
                        final navigator = Navigator.of(context);
                        final added = await addDishToCart(context, dish, widget.kitchen, quantity: _quantity);
                        if (added) navigator.pop();
                      }
                    : null,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
