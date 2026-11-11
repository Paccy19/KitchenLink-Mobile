import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/motion.dart';
import '../client_theme.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_state.dart';
import '../models.dart';
import '../screens/cart_sheet.dart';
import 'cards.dart';

/// The home page's phone pieces: a frosted top bar with the delivery
/// address, the espresso hero carousel, the last order, popular dishes with a
/// quick "+", an offer banner and a floating bottom bar with the basket.

/// Tailwind breakpoints the website's layout switches at.
const smWidth = 640.0;
const lgWidth = 1024.0;

/// Side margin: 20 on a phone, wider on tablets.
double pagePadding(double width) => width >= lgWidth ? 32 : (width >= smWidth ? 24 : 20);

/// Height of [HomeTopBar] below the status bar.
const homeTopBarHeight = 58.0;

// ---- Top bar -----------------------------------------------------------------

/// "Deliver to · Kimironko, Kigali ⌄" on the left, the light/dark switch and
/// the notifications bell on the right. Frosted, with a hairline once the
/// page scrolls under it.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.location,
    required this.onLocation,
    required this.onTheme,
    this.scrolled = false,
    this.unreadNotifications,
    this.onNotifications,
  });

  final ClientLocation location;
  final VoidCallback onLocation;
  final VoidCallback onTheme;
  final bool scrolled;

  /// Null when signed out (no bell).
  final int? unreadNotifications;
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final pad = pagePadding(width);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.fromLTRB(pad - 8, top, pad - 8, 0),
          height: top + homeTopBarHeight,
          decoration: BoxDecoration(
            color: scrolled ? K.header : K.page,
            border: Border(bottom: BorderSide(color: scrolled ? K.stone200 : K.page.withValues(alpha: 0), width: 0.6)),
          ),
          child: Row(
            children: [
              Expanded(child: _location()),
              _iconButton(K.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, K.dark ? 'Switch to light mode' : 'Switch to dark mode', onTheme),
              if (unreadNotifications != null) _bell(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _location() => Semantics(
        button: true,
        label: '${location.isGps ? 'Delivering to your location' : 'Deliver to'} ${location.label}. Change location',
        excludeSemantics: true,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              onLocation();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(location.isGps ? Icons.near_me_rounded : Icons.location_on_rounded, size: 13, color: K.brown500),
                      const SizedBox(width: 4),
                      Text(location.isGps ? 'Delivering to you' : 'Deliver to', style: kText(12, weight: FontWeight.w600, color: K.stone500)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(location.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(16, weight: w900, spacing: -0.3))),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: K.stone700),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: K.surface, minimumSize: const Size(40, 40), fixedSize: const Size(40, 40), shape: CircleBorder(side: BorderSide(color: K.stone200, width: 0.6))),
        icon: Icon(icon, size: 20, color: K.stone800),
      );

  Widget _bell() {
    final count = unreadNotifications ?? 0;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _iconButton(Icons.notifications_none_rounded, 'Notifications', onNotifications ?? () {}),
          if (count > 0)
            Positioned(
              right: 4,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: K.red500, borderRadius: BorderRadius.circular(99), border: Border.all(color: K.page, width: 2)),
                child: Text(count > 9 ? '9+' : '$count', textAlign: TextAlign.center, style: kText(10, weight: w900, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The large serif greeting at the top of the feed.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({super.key, this.firstName, this.now});

  final String? firstName;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final hour = (now ?? DateTime.now()).hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final name = (firstName ?? '').trim();
    return Semantics(
      header: true,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: name.isEmpty ? '$part.\n' : '$part, $name.\n'),
          TextSpan(text: 'What are we eating?', style: kDisplay(30, color: K.brown500)),
        ]),
        style: kDisplay(30),
      ),
    );
  }
}

// ---- Hero carousel ---------------------------------------------------------------

class PromoSlide {
  const PromoSlide({required this.tag, required this.title, required this.text, required this.action, required this.icon, required this.onTap, this.imageUrl});

  final String tag;
  final String title;
  final String text;
  final String action;

  /// Shown in the round frame when there is no [imageUrl].
  final IconData icon;

  /// A real photo (the kitchen's banner), framed in a circle on the right.
  final String? imageUrl;
  final VoidCallback onTap;
}

/// The espresso hero: swipeable cards with an eyebrow, a serif title, one
/// line of detail, a caramel action and the kitchen's photo in a circle.
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
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    // Turns by itself every 6 seconds, but never while a finger is on it or
    // when the phone asks for less motion.
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _touching || !_pages.hasClients || widget.slides.length < 2 || reduceMotion(context)) return;
      _pages.animateToPage((_index + 1) % widget.slides.length, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
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
        Listener(
          onPointerDown: (_) => _touching = true,
          onPointerUp: (_) => _touching = false,
          onPointerCancel: (_) => _touching = false,
          child: SizedBox(
            height: 184,
            child: PageView.builder(
              controller: _pages,
              itemCount: slides.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _HeroCard(slide: slides[i])),
            ),
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Slide ${_index + 1} of ${slides.length}',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: i == _index ? K.brown700 : K.stone300.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(99)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.slide});

  final PromoSlide slide;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFBF3EA);
    const caramel = Color(0xFFDDAE7E);
    return Semantics(
      button: true,
      label: '${slide.tag}. ${slide.title}. ${slide.text}. ${slide.action}',
      excludeSemantics: true,
      child: PressScale(
        pressedScale: 0.98,
        child: Material(
          color: const Color(0xFF2B1609),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: slide.onTap,
            splashColor: Colors.white10,
            child: Stack(
              children: [
                // A faint warm light from the top right, where the photo sits.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(0.9, -0.6), radius: 1.1, colors: [Color(0x40B07A48), Color(0x002B1609)]),
                    ),
                  ),
                ),
                Positioned(right: -40, top: 0, bottom: 0, child: Center(child: _photo())),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 124, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(slide.tag.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(10.5, weight: w900, color: caramel, spacing: 1.2)),
                      const SizedBox(height: 8),
                      Text(slide.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: kDisplay(23, color: cream, height: 1.08)),
                      const SizedBox(height: 6),
                      Flexible(child: Text(slide.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(12, color: cream.withValues(alpha: 0.72), height: 1.35))),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                        decoration: BoxDecoration(color: caramel, borderRadius: BorderRadius.circular(99)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(slide.action, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(12.5, weight: w900, color: const Color(0xFF2B1206)))),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, size: 15, color: Color(0xFF2B1206)),
                          ],
                        ),
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

  Widget _photo() {
    const size = 156.0;
    final ring = BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x33DDAE7E), width: 6));
    final icon = Container(
      width: size,
      height: size,
      decoration: ring.copyWith(color: const Color(0xFF3A2011)),
      padding: const EdgeInsets.only(right: 40),
      child: Icon(slide.icon, size: 52, color: const Color(0xFFDDAE7E)),
    );
    final url = slide.imageUrl;
    if (url == null) return icon;
    return Container(
      width: size,
      height: size,
      decoration: ring.copyWith(boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))]),
      child: ClipOval(child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon)),
    );
  }
}

// ---- Offer banner -------------------------------------------------------------

/// The latte banner for a kitchen's offer day ("20% off brochettes").
class OfferBanner extends StatelessWidget {
  const OfferBanner({super.key, required this.offer, required this.media, required this.onTap});

  final OfferDay offer;
  final MediaResolver media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = media(offer.vendor.bannerUrl.isNotEmpty ? offer.vendor.bannerUrl : offer.vendor.avatarUrl);
    final date = DateTime.tryParse(offer.offerDate);
    return Semantics(
      button: true,
      label: 'Offer day: ${offer.title} at ${offer.vendor.name}',
      excludeSemantics: true,
      child: PressScale(
        pressedScale: 0.98,
        child: Material(
          color: K.brown100,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 128,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            (date == null ? 'Offer day' : 'Offer · ${DateFormat('EEEE d MMM').format(date)}').toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kText(10.5, weight: w900, color: K.brown500, spacing: 1.1),
                          ),
                          const SizedBox(height: 6),
                          Text(offer.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: kDisplay(22, color: K.brown850, height: 1.05)),
                          const SizedBox(height: 6),
                          Text(offer.vendor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(12, weight: FontWeight.w600, color: K.stone600)),
                        ],
                      ),
                    ),
                  ),
                  if (url != null)
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Previous order -------------------------------------------------------------

/// The latest order: status, kitchen, dish photos, total and "Order again".
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
    final cancelled = order.status == 'cancelled';
    final live = order.isLive;
    final (statusFg, statusBg) = cancelled
        ? (K.rose600, K.red50)
        : live
            ? (K.amber800, K.amber200)
            : (K.forest700, K.forest100);
    return PressScale(
      pressedScale: 0.98,
      child: Material(
        color: K.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Ink(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: K.stone200.withValues(alpha: 0.7))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.vendorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(15, weight: w900, spacing: -0.2)),
                            const SizedBox(height: 2),
                            Text(
                              [order.orderNumber, if (date != null) DateFormat('EEE d MMM').format(date.toLocal())].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: kText(12, color: K.stone500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(99)),
                        child: Text(live ? 'On its way' : orderStatusLabel(order.status), style: kText(11.5, weight: w900, color: statusFg)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final item in items.take(3)) ...[
                        SizedBox(
                          width: 44,
                          child: NetImage(url: item.image.isEmpty ? null : media(item.image), aspect: 1, radius: BorderRadius.circular(12), fallback: Icon(Icons.restaurant, size: 16, color: K.stone400)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (items.length > 3)
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: K.stone100, borderRadius: BorderRadius.circular(12)),
                          child: Text('+${items.length - 3}', style: kText(12, weight: w900, color: K.stone600)),
                        ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total', style: kText(11, color: K.stone500)),
                          Text(rwf(order.total), style: kText(15, weight: w900).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onReorder,
                      style: FilledButton.styleFrom(
                        backgroundColor: K.brown100,
                        foregroundColor: K.brown850,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: kText(13.5, weight: w900),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 17),
                      label: const Text('Order again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Popular dish card --------------------------------------------------------------

/// A dish in "Popular picks": the photo with a heart, name, kitchen, rating
/// and price, and a round "+" that becomes − qty + once it is in the basket.
class DishGridCard extends StatelessWidget {
  const DishGridCard({super.key, required this.dish, required this.media, required this.onTap, this.width});

  final Dish dish;
  final MediaResolver media;
  final VoidCallback onTap;

  /// Fixed width in a sideways row; null fills a grid cell.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final saved = context.watch<Wishlist>().contains(dish.id);
    final menuDish = MenuDish.fromDish(dish);
    final kitchen = KitchenRef(id: dish.vendorId, name: dish.vendorName.isEmpty ? 'Kitchen' : dish.vendorName);
    final quantity = cart.lines.where((l) => l.dishId == dish.id).firstOrNull?.quantity ?? 0;
    final url = dish.image.isEmpty ? null : media(dish.image);
    final canAdd = dish.isAvailable && dish.vendorId.isNotEmpty;

    return SizedBox(
      width: width,
      child: PressScale(
        child: Material(
          color: K.surface,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: K.stone200.withValues(alpha: 0.6)), boxShadow: K.dark ? null : K.shadowSm),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        NetImage(url: url, aspect: 1.08, radius: BorderRadius.circular(16)),
                        if (!dish.isAvailable)
                          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(16)))),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: dish.isAvailable
                              ? (dish.rating >= 4.5 ? _tag('Top rated') : const SizedBox.shrink())
                              : _tag('Sold out', dark: true),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Material(
                            color: K.photoChip,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.read<Wishlist>().toggle(menuDish, kitchen);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 17, color: saved ? K.rose600 : K.stone700, semanticLabel: saved ? 'Remove from saved' : 'Save dish'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 4, 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dish.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14.5, weight: w900, spacing: -0.2)),
                          const SizedBox(height: 2),
                          Text(kitchen.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11.5, color: K.stone500)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (dish.rating > 0)
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded, size: 13, color: K.amber400),
                                          const SizedBox(width: 2),
                                          Text(numText(dish.rating), style: kText(11, weight: FontWeight.w700, color: K.stone600)),
                                        ],
                                      ),
                                    Text(
                                      rwf(dish.price),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: kText(14, weight: w900, color: K.brown700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                                    ),
                                  ],
                                ),
                              ),
                              if (quantity == 0)
                                _round(Icons.add_rounded, canAdd ? 'Add ${dish.name} to basket' : 'Sold out', filled: true, onTap: canAdd ? () => addDishToCart(context, menuDish, kitchen) : null),
                            ],
                          ),
                          if (quantity > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(color: K.stone100, borderRadius: BorderRadius.circular(99)),
                              child: Row(
                                children: [
                                  _round(Icons.remove_rounded, 'One less', onTap: () => cart.setQuantity(dish.id, quantity - 1)),
                                  Expanded(
                                    child: Text('$quantity', textAlign: TextAlign.center, style: kText(14, weight: w900).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                                  ),
                                  _round(Icons.add_rounded, 'One more', filled: true, onTap: () => cart.setQuantity(dish.id, quantity + 1)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, {bool dark = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: dark ? K.fillStone800.withValues(alpha: 0.9) : const Color(0xE62B1609), borderRadius: BorderRadius.circular(99)),
        child: Text(text.toUpperCase(), style: kText(9, weight: w900, color: const Color(0xFFFBF3EA), spacing: 0.8)),
      );

  Widget _round(IconData icon, String tooltip, {bool filled = false, VoidCallback? onTap}) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          excludeSemantics: true,
          child: Material(
            color: filled ? (onTap == null ? K.stone200 : K.fillBrown700) : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onTap();
                    },
              child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 19, color: filled ? (onTap == null ? K.stone400 : Colors.white) : K.stone800)),
            ),
          ),
        ),
      );
}

// ---- Bottom bar -------------------------------------------------------------------

/// Home · Kitchens · (basket) · Saved · Account on a frosted bar, with the
/// basket raised in the middle.
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
    const barHeight = 60.0;
    return SizedBox(
      height: barHeight + bottom + 20,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: barHeight + bottom,
                padding: EdgeInsets.only(bottom: bottom),
                decoration: BoxDecoration(
                  color: K.surface.withValues(alpha: K.dark ? 0.86 : 0.9),
                  border: Border(top: BorderSide(color: K.stone200, width: 0.6)),
                ),
                child: Row(
                  children: [
                    _item(Icons.home_rounded, 'Home', onHome, active: true),
                    _item(Icons.storefront_outlined, 'Kitchens', onKitchens),
                    const Expanded(child: SizedBox()),
                    _item(Icons.favorite_border_rounded, 'Saved', onSaved),
                    _item(Icons.person_outline_rounded, accountLabel, onAccount),
                  ],
                ),
              ),
            ),
          ),
          // The raised basket button.
          Positioned(
            bottom: barHeight + bottom - 42,
            child: Semantics(
              button: true,
              label: 'Basket, $cartCount dishes',
              excludeSemantics: true,
              child: PressScale(
                pressedScale: 0.92,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onCart();
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B1609),
                      shape: BoxShape.circle,
                      border: Border.all(color: K.page, width: 4),
                      boxShadow: K.brownShadow,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.shopping_bag_outlined, color: Color(0xFFFBF3EA), size: 24),
                        if (cartCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFFDDAE7E), borderRadius: BorderRadius.circular(99)),
                              child: Text(cartCount > 99 ? '99+' : '$cartCount', textAlign: TextAlign.center, style: kText(10, weight: w900, color: K.brown950)),
                            ),
                          ),
                      ],
                    ),
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
        child: Semantics(
          button: true,
          selected: active,
          child: InkResponse(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            radius: 32,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: active ? K.brown700 : K.stone400),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(10.5, weight: active ? w900 : FontWeight.w600, color: active ? K.brown700 : K.stone500)),
              ],
            ),
          ),
        ),
      );
}
