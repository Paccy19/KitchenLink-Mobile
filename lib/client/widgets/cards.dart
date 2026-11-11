import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../models.dart';

/// Turns an API image path into a loadable URL (see CustomerApi.media).
typedef MediaResolver = String? Function(String url);

/// A fixed-aspect photo that fades in once loaded, on a warm placeholder,
/// with a utensils icon (or [fallback]) when there is no picture or it fails.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, required this.aspect, this.fallback, this.radius = BorderRadius.zero});

  final String? url;
  final double aspect;
  final Widget? fallback;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final empty = Container(
      color: K.stone100,
      alignment: Alignment.center,
      child: fallback ?? Icon(Icons.restaurant_rounded, size: 30, color: K.stone300),
    );
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: aspect,
        child: url == null
            ? empty
            : Image.network(
                url!,
                fit: BoxFit.cover,
                // Decode near the size it is drawn, not the full upload.
                cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round().clamp(200, 1400),
                errorBuilder: (_, _, _) => empty,
                frameBuilder: (context, child, frame, synchronous) => synchronous
                    ? child
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: K.stone100),
                          AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: child),
                        ],
                      ),
              ),
      ),
    );
  }
}

/// A rounded "pill" label over a picture.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.background, required this.foreground, this.icon, this.size = 11, this.shadow = false});

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size >= 11 ? 10 : 8, vertical: size >= 11 ? 4 : 2),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99), boxShadow: shadow ? K.shadowMd : null),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
        Text(
          text,
          style: kText(size, weight: w900, color: foreground),
        ),
      ],
    ),
  );
}

/// A card that can be tapped: surface, soft shadow, a faint hairline, and a
/// press that starts on touch-down.
class TapCard extends StatelessWidget {
  const TapCard({super.key, required this.child, required this.onTap, this.width, this.borderColor, this.label});

  final Widget child;
  final VoidCallback onTap;
  final double? width;
  final Color? borderColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        pressedScale: 0.98,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: K.surface,
            borderRadius: radius,
            border: Border.all(color: borderColor ?? K.stone200.withValues(alpha: 0.6)),
            boxShadow: K.dark ? null : K.shadowSm,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: child),
          ),
        ),
      ),
    );
  }
}

/// The kitchen's logo, or its first letter.
class VendorAvatar extends StatelessWidget {
  const VendorAvatar({super.key, required this.vendor, required this.media, this.size = 36});

  final Vendor vendor;
  final MediaResolver media;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = media(vendor.avatarUrl);
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: K.brown100, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Text(
        (vendor.name.isEmpty ? 'K' : vendor.name[0]).toUpperCase(),
        style: kText(14, weight: w900, color: K.brown700),
      ),
    );
    if (url == null) return letter;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.32), color: K.stone100),
      clipBehavior: Clip.antiAlias,
      child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => letter),
    );
  }
}

Widget _shade(List<double> stops, List<Color> colors) => Positioned.fill(
  child: IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: colors, stops: stops),
      ),
    ),
  ),
);

/// A kitchen: its photo (rating, delivery and "near you" over it, a veil
/// when closed), then name, type and area, and prep time and delivery fee.
class VendorCard extends StatelessWidget {
  const VendorCard({super.key, required this.vendor, required this.media, required this.onTap, this.tile = false, this.showDistance = false});

  final Vendor vendor;
  final MediaResolver media;
  final VoidCallback onTap;

  /// In a sideways row: 280 wide, no description.
  final bool tile;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final distance = showDistance && vendor.hasDistance;
    final meta = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: K.stone600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TapCard(
      width: tile ? 280 : null,
      onTap: onTap,
      label:
          '${vendor.name}, ${vendor.typeLabel}, rated ${numText(vendor.rating)}${distance ? ', ${numText(vendor.distanceKm)} kilometres away' : ''}${vendor.isOpen ? '' : ', closed now'}',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                NetImage(
                  url: media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl),
                  aspect: tile ? 16 / 9.5 : 16 / 9,
                  radius: BorderRadius.circular(16),
                ),
                if (!vendor.isOpen)
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(16)),
                      child: Text(
                        'Closed now',
                        style: kText(14, weight: w900, color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: K.photoChip, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: K.amber400),
                        const SizedBox(width: 3),
                        Text(vendor.rating > 0 ? numText(vendor.rating) : 'New', style: kText(12, weight: w900)),
                        if (vendor.reviewsCount > 0) ...[const SizedBox(width: 3), Text('(${vendor.reviewsCount})', style: kText(10.5, color: K.stone500))],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      if (vendor.nationwide)
                        Pill('Events nationwide', icon: Icons.public, size: 10.5, background: K.violet700.withValues(alpha: 0.92), foreground: Colors.white)
                      else if (vendor.deliveryAvailable)
                        Pill('Delivery', icon: Icons.delivery_dining_rounded, size: 10.5, background: K.photoChip, foreground: K.forest700),
                      if (vendor.isNearby) ...[
                        const SizedBox(width: 6),
                        Pill('Near you', icon: Icons.near_me_rounded, size: 10.5, background: const Color(0xFFDDAE7E), foreground: K.brown950),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      VendorAvatar(vendor: vendor, media: media, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kText(16, weight: w900, spacing: -0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [vendor.typeLabel, vendor.neighborhood].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kText(12.5, color: K.stone500),
                  ),
                  if (!tile && vendor.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      vendor.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: kText(13, weight: FontWeight.w500, color: K.stone600, height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (distance) _meta(Icons.near_me_outlined, '${numText(vendor.distanceKm)} km', meta),
                      _meta(Icons.schedule_rounded, vendor.prepTime, meta),
                      if (vendor.deliveryFee > 0) _meta(Icons.delivery_dining_outlined, formatRwf(vendor.deliveryFee), meta),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, TextStyle style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: K.brown500),
      const SizedBox(width: 4),
      Text(text, style: style),
    ],
  );
}

/// The website's DishCard tile (190 wide) for "Popular Dishes Near You".
class DishCard extends StatelessWidget {
  const DishCard({super.key, required this.dish, required this.media, required this.onTap});

  final Dish dish;
  final MediaResolver media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapCard(
      width: 190,
      onTap: onTap,
      label: '${dish.name}, ${formatRwf(dish.price)}, from ${dish.vendorName.isEmpty ? 'kitchen' : dish.vendorName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Stack(
              children: [
                NetImage(url: media(dish.image), aspect: 4 / 3, radius: BorderRadius.circular(16)),
                if (!dish.isAvailable)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Pill('Sold out', size: 10, background: K.fillStone800.withValues(alpha: 0.9), foreground: Colors.white),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dish.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kText(10, weight: FontWeight.w700, color: K.stone400, spacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  dish.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kText(14, weight: w900, height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  dish.vendorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kText(11, color: K.stone500),
                ),
                const SizedBox(height: 10),
                Divider(height: 1, color: K.stone100),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        formatRwf(dish.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(14, weight: w900, color: K.brown750),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Spacer(),
                    if (dish.rating > 0) ...[
                      const Icon(Icons.star_rounded, size: 13, color: K.amber400),
                      const SizedBox(width: 2),
                      Text(
                        numText(dish.rating),
                        style: kText(11, weight: FontWeight.w600, color: K.stone400),
                      ),
                      if (dish.hasPrep)
                        Text(
                          ' · ',
                          style: kText(11, weight: FontWeight.w600, color: K.stone400),
                        ),
                    ],
                    if (dish.hasPrep) ...[
                      Icon(Icons.schedule, size: 12, color: K.brown500),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          dish.prepTime,
                          overflow: TextOverflow.ellipsis,
                          style: kText(11, weight: FontWeight.w600, color: K.stone400),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row-style dish card (search results).
class DishRow extends StatelessWidget {
  const DishRow({super.key, required this.dish, required this.media, required this.onTap});

  final Dish dish;
  final MediaResolver media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapCard(
      onTap: onTap,
      label: '${dish.name}, ${formatRwf(dish.price)}',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: NetImage(url: media(dish.image), aspect: 1, radius: BorderRadius.circular(16)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      Pill(dish.category.toUpperCase(), size: 10, shadow: false, background: K.stone100, foreground: K.stone600),
                      if (!dish.isAvailable) Pill('SOLD OUT', size: 10, shadow: false, background: K.stone100, foreground: K.stone500),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dish.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kText(14, weight: w900),
                  ),
                  Text(
                    dish.vendorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kText(12, color: K.stone500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRwf(dish.price),
                  style: kText(14, weight: w900, color: K.brown750),
                ),
                if (dish.hasPrep)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 12, color: K.brown500),
                        const SizedBox(width: 3),
                        Text(
                          dish.prepTime,
                          style: kText(11, weight: FontWeight.w600, color: K.stone400),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A kitchen's "Tomorrow's Special" card (300 wide) with "Pre-order now".
class SpecialCard extends StatelessWidget {
  const SpecialCard({super.key, required this.entry, required this.media, required this.onTap, required this.onPreorder});

  final SpecialEntry entry;
  final MediaResolver media;
  final VoidCallback onTap;
  final VoidCallback onPreorder;

  @override
  Widget build(BuildContext context) {
    final vendor = entry.vendor;
    final special = entry.special;
    return TapCard(
      width: 300,
      onTap: onTap,
      label: '${vendor.name} special: ${special.text}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bannerWithName(
            vendor,
            media(vendor.bannerUrl),
            topLeft: const Pill("Tomorrow's special", icon: Icons.schedule_rounded, size: 10.5, background: Color(0xFFDDAE7E), foreground: K.brown950),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  special.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kText(14, weight: w900, height: 1.35),
                ),
                const SizedBox(height: 12),
                _iconLine(Icons.schedule, 'Order before ${formatScheduledFor(special.cutoffAt)}'),
                const SizedBox(height: 6),
                _iconLine(Icons.event_available_outlined, 'Arrives ${formatScheduledFor(special.deliveryAt)}'),
                const SizedBox(height: 16),
                GradientButton(label: 'Pre-order now', onTap: onPreorder, height: 44, fontSize: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _iconLine(IconData icon, String text) => Row(
  children: [
    Icon(icon, size: 14, color: K.brown500),
    const SizedBox(width: 6),
    Expanded(
      child: Text(
        text,
        style: kText(11, weight: FontWeight.w600, color: K.stone600),
      ),
    ),
  ],
);

Widget _bannerWithName(Vendor vendor, String? url, {required Widget topLeft, Widget? topRight}) => Padding(
  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Stack(
      children: [
        NetImage(url: url, aspect: 16 / 9),
        _shade(const [0, 0.5, 1], const [Color(0xB3000000), Color(0x33000000), Color(0x00000000)]),
        Positioned(top: 12, left: 12, child: topLeft),
        if (topRight != null) Positioned(top: 12, right: 12, child: topRight),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vendor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kText(14, weight: w900, color: Colors.white),
              ),
              const SizedBox(height: 4),
              VendorTypeBadge(vendor.typeCode, small: true),
            ],
          ),
        ),
      ],
    ),
  ),
);

/// A kitchen's "Offer Day" card, shown next to Tomorrow's Specials.
class OfferDayCard extends StatelessWidget {
  const OfferDayCard({super.key, required this.offer, required this.media, required this.onTap});

  final OfferDay offer;
  final MediaResolver media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vendor = offer.vendor;
    return TapCard(
      width: 300,
      onTap: onTap,
      label: '${vendor.name} offer on ${formatOfferDay(offer.offerDate)}: ${offer.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bannerWithName(
            vendor,
            media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl),
            topLeft: const Pill('Offer day', icon: Icons.local_offer_outlined, size: 10.5, background: Color(0xFFDDAE7E), foreground: K.brown950),
            topRight: Pill(offerCountdown(offer.offerDate), size: 10.5, background: K.photoChip, foreground: K.gray900),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 14, color: K.amber800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        formatOfferDay(offer.offerDate).toUpperCase(),
                        style: kText(11, weight: w900, color: K.amber800, spacing: 0.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  offer.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kText(14, weight: w900, height: 1.35),
                ),
                if (offer.details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    offer.details,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: kText(12, weight: FontWeight.w400, color: K.stone500, height: 1.6),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'View kitchen',
                      style: kText(13, weight: w900, color: K.brown600),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: K.brown600),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The main action button: solid espresso (caramel in dark mode), a press
/// that starts on touch-down, and a label that scales down rather than
/// overflowing on a narrow phone.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.height = 50,
    this.fontSize = 15,
    this.radius = 14,
    this.expand = true,
    this.padding = 18,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? iconColor;
  final double height;
  final double fontSize;
  final double radius;
  final bool expand;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final bg = K.dark ? const Color(0xFFDDAE7E) : K.fillBrown700;
    final fg = K.dark ? K.brown950 : Colors.white;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: PressScale(
        enabled: onTap != null,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            decoration: BoxDecoration(color: bg, borderRadius: r, boxShadow: onTap == null || K.dark ? null : K.brownShadow),
            child: Material(
              color: Colors.transparent,
              borderRadius: r,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[Icon(icon, size: fontSize + 3, color: iconColor ?? fg), const SizedBox(width: 8)],
                        Text(
                          label,
                          style: kText(fontSize, weight: FontWeight.w800, color: fg, spacing: -0.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's Skeleton block (`animate-pulse rounded-xl bg-gray-200/80`).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 12});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 1.0, end: 0.55).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
    child: Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(color: K.stone100, borderRadius: BorderRadius.circular(widget.radius)),
    ),
  );
}

class VendorTileSkeleton extends StatelessWidget {
  const VendorTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => _skeletonCard(260, const SkeletonBox(height: 144, radius: 0), const [0.75, 0.5, 0.66]);
}

class DishCardSkeleton extends StatelessWidget {
  const DishCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => _skeletonCard(180, const AspectRatio(aspectRatio: 4 / 3, child: SkeletonBox(radius: 0)), const [0.83, 0.66, 0.55]);
}

Widget _skeletonCard(double width, Widget top, List<double> lines) => Container(
  width: width,
  decoration: BoxDecoration(
    color: K.surface,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: K.stone200.withValues(alpha: 0.6)),
  ),
  clipBehavior: Clip.antiAlias,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      top,
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              SkeletonBox(width: (width - 32) * lines[i], height: i == 0 ? 16 : 12),
            ],
          ],
        ),
      ),
    ],
  ),
);

/// The website's EmptyState: a white card with a brown icon tile.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction, this.child});

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(24)),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: K.brown100, shape: BoxShape.circle),
          child: Icon(icon, size: 28, color: K.brown700),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: kText(17, weight: w900, spacing: -0.3),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: kText(14, weight: FontWeight.w500, color: K.stone500, height: 1.45),
          ),
        ],
        if (child != null) ...[const SizedBox(height: 12), child!],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          GradientButton(label: actionLabel!, onTap: onAction, expand: false, height: 44, fontSize: 14, padding: 22),
        ],
      ],
    ),
  );
}

/// The website's ErrorState: red icon tile, message and "Try again".
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, this.title = 'Something went wrong', this.message, required this.onRetry, this.retrying = false});

  final String title;
  final String? message;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(24)),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: K.red50, shape: BoxShape.circle),
          child: Icon(Icons.wifi_off_rounded, size: 28, color: K.rose600),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: kText(18, weight: w900),
        ),
        const SizedBox(height: 16),
        Text(
          message ?? 'We could not load this section. Check your connection and try again.',
          textAlign: TextAlign.center,
          style: kText(14, weight: FontWeight.w400, color: K.stone500),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: retrying ? null : onRetry,
          style: FilledButton.styleFrom(
            // Dark on light; on dark the website's white button with dark text.
            backgroundColor: K.stone900,
            foregroundColor: K.dark ? K.brown950 : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: kText(14, weight: FontWeight.w700),
          ),
          icon: const Icon(Icons.replay, size: 16),
          label: Text(retrying ? 'Retrying…' : 'Try again'),
        ),
      ],
    ),
  );
}
