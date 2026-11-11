import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../client_theme.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_state.dart';
import '../models.dart';
import '../screens/cart_sheet.dart';
import 'cards.dart';

/// The home page's app-style pieces: a compact top bar with the delivery
/// address, a promo carousel, the last order, a two-column dish grid and a
/// bottom bar with a raised basket button. All in the KitchenLink browns.

/// Tailwind breakpoints the website's layout switches at.
const smWidth = 640.0;
const lgWidth = 1024.0;

/// `px-4 sm:px-6 lg:px-8`.
double pagePadding(double width) => width >= lgWidth ? 32 : (width >= smWidth ? 24 : 16);

// ---- Top bar -----------------------------------------------------------------

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.location,
    required this.onLocation,
    required this.onTheme,
    required this.onMap,
    this.unreadNotifications,
    this.onNotifications,
  });

  final ClientLocation location;
  final VoidCallback onLocation;
  final VoidCallback onTheme;
  final VoidCallback onMap;

  /// Null when signed out (no bell).
  final int? unreadNotifications;
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 10, 8, 6),
      color: K.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(gradient: K.logoGradient, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.local_dining, size: 18, color: K.light(() => K.brown100)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Kitchen', style: kText(19, weight: w900, color: K.brown700, spacing: -0.4)),
                    TextSpan(text: 'Link', style: kText(19, weight: w900, color: K.brown500, spacing: -0.4)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _iconButton(Icons.map_outlined, 'Nearby Map', onMap),
              _iconButton(K.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, K.dark ? 'Switch to light mode' : 'Switch to dark mode', onTheme),
              if (unreadNotifications != null) _bell(),
            ],
          ),
          const SizedBox(height: 10),
          // "📍 Deliver to · Kimironko, Kigali  ›" (the reference's address row).
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onLocation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: K.brown700, shape: BoxShape.circle),
                        child: Icon(location.isGps ? Icons.my_location : Icons.location_on, size: 18, color: K.dark ? K.brown950 : Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(location.isGps ? 'Delivering to your location' : 'Deliver to', style: kText(11, color: K.stone500)),
                            Text(location.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14, weight: w900)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: K.stone600),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 21, color: K.stone700),
      );

  Widget _bell() {
    final count = unreadNotifications ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _iconButton(Icons.notifications_none, 'Notifications', onNotifications ?? () {}),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: K.red500, borderRadius: BorderRadius.circular(99)),
              child: Text(count > 9 ? '9+' : '$count', style: kText(9.5, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

// ---- Promo carousel -------------------------------------------------------------

class PromoSlide {
  const PromoSlide({required this.tag, required this.title, required this.text, required this.action, required this.emoji, required this.onTap});

  final String tag;
  final String title;
  final String text;
  final String action;
  final String emoji;
  final VoidCallback onTap;
}

/// The reference's "Happy Weekend · 25% OFF" banner: swipeable brown cards.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.slides});

  final List<PromoSlide> slides;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Turns by itself every 5 seconds, like a store banner.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pages.hasClients || widget.slides.length < 2) return;
      _pages.animateToPage((_index + 1) % widget.slides.length, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 172,
          child: PageView.builder(
            controller: _pages,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: _slide(slides[i])),
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _index ? K.brown700 : K.stone300, borderRadius: BorderRadius.circular(99)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _slide(PromoSlide slide) => K.light(
        () => Material(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(gradient: K.logoGradient),
            child: InkWell(
              onTap: slide.onTap,
              child: Stack(
                children: [
                  // A soft caramel glow behind the picture.
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle, color: K.brown500.withValues(alpha: 0.35))),
                  ),
                  Positioned(right: 22, top: 0, bottom: 0, child: Center(child: Text(slide.emoji, style: const TextStyle(fontSize: 64)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 120, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(slide.tag.toUpperCase(), style: kText(10, weight: w900, color: K.amber400, spacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(slide.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: kText(18, weight: w900, color: Colors.white, height: 1.15)),
                        const SizedBox(height: 4),
                        Text(slide.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11.5, color: K.brown200, height: 1.3)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                          child: Text(slide.action, style: kText(11.5, weight: w900, color: K.brown900)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ---- Previous order -------------------------------------------------------------

/// "Previous Order": the latest order with its dishes, total and "Order again",
/// and its status on a ribbon down the right edge.
class PreviousOrderCard extends StatelessWidget {
  const PreviousOrderCard({super.key, required this.order, required this.media, required this.onOpen, required this.onReorder});

  final CustomerOrder order;
  final MediaResolver media;
  final VoidCallback onOpen;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    final date = order.createdAt;
    final delivered = order.status == 'delivered';
    final cancelled = order.status == 'cancelled';
    final ribbon = cancelled ? K.red500 : (delivered ? K.forest600 : K.fillBrown700);
    return Material(
      color: K.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(border: Border.all(color: K.stone200), borderRadius: BorderRadius.circular(18)),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(orderStatusLabel(order.status), style: kText(11, weight: w900, color: K.tone(cancelled ? const Color(0xFFB91C1C) : const Color(0xFF047857)))),
                        if (date != null) Text('On ${DateFormat('EEE, d MMM yyyy').format(date.toLocal())}', style: kText(11, color: K.stone500)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final item in items.take(3)) ...[
                              SizedBox(
                                width: 40,
                                child: NetImage(url: item.image.isEmpty ? null : media(item.image), aspect: 1, radius: BorderRadius.circular(10), fallback: Icon(Icons.restaurant, size: 16, color: K.stone400)),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (items.length > 3)
                              Text('+${items.length - 3}\nmore', style: kText(10.5, weight: FontWeight.w700, color: K.stone500, height: 1.2)),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('${order.vendorName} · ${order.orderNumber}', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11, color: K.stone500)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(child: Text('Final total: ${rwf(order.total)}', style: kText(14, weight: w900))),
                            Material(
                              color: K.fillBrown700,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: onReorder,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  child: Text('Order again', style: kText(12, weight: w900, color: Colors.white)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // The status ribbon.
                Container(
                  width: 26,
                  color: ribbon,
                  alignment: Alignment.center,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      order.isLive ? 'On its way to you' : orderStatusLabel(order.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kText(10.5, weight: w900, color: Colors.white, spacing: 0.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Dish grid card --------------------------------------------------------------

/// The reference's "Popular Deals" card: picture with a heart, name, price and
/// rating, then "Add to basket" or − qty + once it is in the basket.
class DishGridCard extends StatelessWidget {
  const DishGridCard({super.key, required this.dish, required this.media, required this.onTap});

  final Dish dish;
  final MediaResolver media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final saved = context.watch<Wishlist>().contains(dish.id);
    final menuDish = MenuDish.fromDish(dish);
    final kitchen = KitchenRef(id: dish.vendorId, name: dish.vendorName.isEmpty ? 'Kitchen' : dish.vendorName);
    final quantity = cart.lines.where((l) => l.dishId == dish.id).firstOrNull?.quantity ?? 0;
    final url = dish.image.isEmpty ? null : media(dish.image);

    return Material(
      color: K.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(border: Border.all(color: K.stone200), borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    NetImage(url: url, aspect: 1.15, radius: BorderRadius.circular(14)),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Material(
                        color: K.surface,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.read<Wishlist>().toggle(menuDish, kitchen),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(saved ? Icons.favorite : Icons.favorite_border, size: 16, color: K.rose600, semanticLabel: saved ? 'Remove from saved' : 'Save dish'),
                          ),
                        ),
                      ),
                    ),
                    if (!dish.isAvailable)
                      Positioned(right: 6, top: 6, child: Pill('Sold out', size: 10, background: K.fillStone800.withValues(alpha: 0.9), foreground: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(dish.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(13.5, weight: w900)),
                Text(kitchen.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11, color: K.stone500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: Text(rwf(dish.price), maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(13, weight: w900, color: K.brown700))),
                    if (dish.rating > 0) ...[
                      Icon(Icons.star_rounded, size: 14, color: K.amber400),
                      Text(numText(dish.rating), style: kText(11.5, weight: FontWeight.w700, color: K.stone600)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (quantity > 0)
                  Row(
                    children: [
                      _round(Icons.remove, 'One less', K.stone200, K.gray900, () => cart.setQuantity(dish.id, quantity - 1)),
                      Expanded(child: Text('$quantity', textAlign: TextAlign.center, style: kText(14, weight: w900))),
                      _round(Icons.add, 'One more', K.fillBrown700, Colors.white, () => cart.setQuantity(dish.id, quantity + 1)),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: dish.isAvailable && dish.vendorId.isNotEmpty ? () => addDishToCart(context, menuDish, kitchen) : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: K.brown700,
                        backgroundColor: K.surface,
                        side: BorderSide(color: K.brown300),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(dish.isAvailable ? 'Add to basket' : 'Sold out', style: kText(12, weight: w900, color: dish.isAvailable ? K.brown700 : K.stone400)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, String tooltip, Color background, Color foreground, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18, color: foreground)),
          ),
        ),
      );
}

// ---- Bottom bar -------------------------------------------------------------------

/// Home · Kitchens · (basket) · Saved · Account, with the basket raised in the
/// middle like the reference.
class MarketBottomBar extends StatelessWidget {
  const MarketBottomBar({
    super.key,
    required this.cartCount,
    required this.onHome,
    required this.onKitchens,
    required this.onCart,
    required this.onSaved,
    required this.onAccount,
    this.accountLabel = 'Account',
  });

  final int cartCount;
  final VoidCallback onHome;
  final VoidCallback onKitchens;
  final VoidCallback onCart;
  final VoidCallback onSaved;
  final VoidCallback onAccount;
  final String accountLabel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 66 + bottom + 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 66 + bottom,
            padding: EdgeInsets.only(bottom: bottom),
            decoration: BoxDecoration(
              color: K.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: K.stone200)),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
            ),
            child: Row(
              children: [
                _item(Icons.home_rounded, 'Home', onHome, active: true),
                _item(Icons.grid_view_rounded, 'Kitchens', onKitchens),
                const Expanded(child: SizedBox()),
                _item(Icons.favorite_border, 'Saved', onSaved),
                _item(Icons.person_outline, accountLabel, onAccount),
              ],
            ),
          ),
          // The raised basket button.
          Positioned(
            bottom: 66 + bottom - 44,
            child: Semantics(
              button: true,
              label: 'Basket, $cartCount dishes',
              child: GestureDetector(
                onTap: onCart,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: K.buttonGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: K.page, width: 4),
                    boxShadow: K.brownShadow,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.shopping_bag_outlined, color: K.light(() => K.brown100), size: 24),
                      if (cartCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: K.amber400, borderRadius: BorderRadius.circular(99)),
                            child: Text(cartCount > 99 ? '99+' : '$cartCount', style: kText(10, weight: w900, color: K.brown950)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap, {bool active = false}) => Expanded(
        child: InkResponse(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 23, color: active ? K.brown700 : K.stone400),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(10.5, weight: active ? w900 : FontWeight.w600, color: active ? K.brown700 : K.stone400)),
            ],
          ),
        ),
      );
}
