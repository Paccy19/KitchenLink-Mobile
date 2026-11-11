import 'package:flutter/material.dart';

import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../models.dart';

/// Turns an API image path into a loadable URL (see CustomerApi.media).
typedef MediaResolver = String? Function(String url);

/// The website's LazyImage: a fixed-aspect picture with a grey placeholder,
/// and a utensils icon (or [fallback]) when there is no picture.
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
      child: fallback ?? Icon(Icons.restaurant, size: 32, color: K.stone300),
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
                errorBuilder: (_, _, _) => empty,
                loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: K.stone200),
              ),
      ),
    );
  }
}

/// A rounded "pill" label over a picture.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.background, required this.foreground, this.icon, this.size = 11, this.shadow = true});

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

/// White `rounded-3xl border-stone-200/80 shadow-sm` card that can be tapped.
class TapCard extends StatelessWidget {
  const TapCard({super.key, required this.child, required this.onTap, this.width, this.borderColor, this.label});

  final Widget child;
  final VoidCallback onTap;
  final double? width;
  final Color? borderColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: K.surface,
          borderRadius: radius,
          border: Border.all(color: borderColor ?? K.stone200.withValues(alpha: 0.8)),
          boxShadow: K.shadowSm,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
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
      decoration: BoxDecoration(
        color: K.brown100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.brown200),
      ),
      child: Text(
        (vendor.name.isEmpty ? 'K' : vendor.name[0]).toUpperCase(),
        style: kText(14, weight: w900, color: K.brown700),
      ),
    );
    if (url == null) return letter;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.stone200),
        color: K.stone100,
      ),
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

/// The website's VendorCard: banner with type / rating / delivery badges,
/// then name, neighbourhood, description and the prep time row.
class VendorCard extends StatelessWidget {
  const VendorCard({super.key, required this.vendor, required this.media, required this.onTap, this.tile = false, this.showDistance = false});

  final Vendor vendor;
  final MediaResolver media;
  final VoidCallback onTap;

  /// `variant="tile"`: 268 wide, 16:9 banner, no description.
  final bool tile;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final distance = showDistance && vendor.hasDistance;
    return TapCard(
      width: tile ? 268 : null,
      onTap: onTap,
      label: '${vendor.name}, ${vendor.typeLabel}, rated ${numText(vendor.rating)}${distance ? ', ${numText(vendor.distanceKm)} kilometres away' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              NetImage(url: media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl), aspect: tile ? 16 / 9 : 16 / 10),
              _shade(const [0, 0.5, 1], const [Color(0x99000000), Color(0x1A000000), Color(0x33000000)]),
              Positioned(top: 12, left: 12, child: VendorTypeBadge(vendor.typeCode)),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(99), boxShadow: K.shadowMd),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: K.amber400),
                      const SizedBox(width: 3),
                      Text(numText(vendor.rating), style: kText(12, weight: w900)),
                      if (vendor.reviewsCount > 0) ...[const SizedBox(width: 3), Text('(${vendor.reviewsCount})', style: kText(10, color: K.stone500))],
                    ],
                  ),
                ),
              ),
              if (vendor.nationwide)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Pill('Events nationwide', icon: Icons.public, background: K.violet700.withValues(alpha: 0.95), foreground: Colors.white),
                )
              else if (vendor.deliveryAvailable)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Pill('Delivery available', icon: Icons.pedal_bike, background: K.forest600.withValues(alpha: 0.95), foreground: Colors.white),
                ),
              if (vendor.isNearby)
                const Positioned(
                  bottom: 12,
                  right: 12,
                  child: Pill('Near you', icon: Icons.near_me_outlined, background: K.amber400, foreground: K.fillBrown850),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    VendorAvatar(vendor: vendor, media: media),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vendor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(tile ? 16 : 17, weight: w900),
                      ),
                    ),
                    if (!vendor.isOpen) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: K.stone100, borderRadius: BorderRadius.circular(99)),
                        child: Text(
                          'CLOSED',
                          style: kText(10, weight: w900, color: K.stone500),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: K.brown500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        vendor.neighborhood,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(12, color: K.stone500),
                      ),
                    ),
                  ],
                ),
                if (!tile && vendor.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    vendor.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: kText(12, weight: FontWeight.w400, color: K.stone500, height: 1.6),
                  ),
                ],
                const SizedBox(height: 12),
                Divider(height: 1, color: K.stone100),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (distance) ...[
                      Icon(Icons.location_on_outlined, size: 14, color: K.brown500),
                      const SizedBox(width: 4),
                      Text(
                        '${numText(vendor.distanceKm)} km',
                        style: kText(12, weight: FontWeight.w600, color: K.stone600),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.schedule, size: 14, color: K.stone400),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        vendor.prepTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(12, weight: FontWeight.w600, color: K.stone600),
                      ),
                    ),
                    const Spacer(),
                    if (vendor.deliveryFee > 0) ...[
                      Icon(Icons.pedal_bike, size: 14, color: K.brown500),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          formatRwf(vendor.deliveryFee),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kText(12, weight: FontWeight.w700, color: K.stone800),
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
          Stack(
            children: [
              NetImage(url: media(dish.image), aspect: 4 / 3),
              Positioned(
                top: 10,
                left: 10,
                child: dish.isAvailable
                    ? Pill('Available', size: 10, background: K.forest600.withValues(alpha: 0.95), foreground: Colors.white)
                    : Pill('Sold out', size: 10, background: K.fillStone800.withValues(alpha: 0.9), foreground: Colors.white),
              ),
            ],
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
      borderColor: K.tone(const Color(0xFFD9DCC0)),
      label: '${vendor.name} special: ${special.text}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bannerWithName(
            vendor,
            media(vendor.bannerUrl),
            topLeft: const Pill("Tomorrow's Special", background: Color(0xFFC9CDA2), foreground: Color(0xFF2B3317)),
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
                GradientButton(label: 'Pre-order now', onTap: onPreorder, height: 38, fontSize: 12, radius: 12),
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

Widget _bannerWithName(Vendor vendor, String? url, {required Widget topLeft, Widget? topRight}) => Stack(
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
      borderColor: K.amber200,
      label: '${vendor.name} offer on ${formatOfferDay(offer.offerDate)}: ${offer.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bannerWithName(
            vendor,
            media(vendor.bannerUrl.isNotEmpty ? vendor.bannerUrl : vendor.avatarUrl),
            topLeft: const Pill('Offer Day', icon: Icons.card_giftcard, background: K.amber400, foreground: K.fillBrown850),
            topRight: Pill(offerCountdown(offer.offerDate), background: Colors.white.withValues(alpha: 0.95), foreground: K.fillBrown850),
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
                Text(
                  'View kitchen →',
                  style: kText(12, weight: w900, color: K.brown700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The brown gradient button (`bg-gradient-to-r from-[#2b1206] via-[#481f0d] to-[#200d05]`).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.height = 48,
    this.fontSize = 14,
    this.radius = 16,
    this.expand = true,
    this.padding = 16,
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
    return Opacity(
      opacity: onTap == null ? 0.7 : 1,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(gradient: K.buttonGradient, borderRadius: r, boxShadow: K.brownShadow),
        child: Material(
          color: Colors.transparent,
          borderRadius: r,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              // A long label scales down instead of overflowing on a narrow phone.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, size: fontSize + 2, color: iconColor ?? K.brown300), const SizedBox(width: 6)],
                    Text(
                      label,
                      style: kText(fontSize, weight: w900, color: Colors.white),
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
    opacity: Tween(begin: 1.0, end: 0.5).animate(_pulse),
    child: Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(color: K.gray200.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(widget.radius)),
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
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: K.tone(const Color(0xFFF3F4F6))),
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
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    decoration: BoxDecoration(
      color: K.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: K.stone200.withValues(alpha: 0.8)),
      boxShadow: K.shadowSm,
    ),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: K.brown50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: K.brown200),
            boxShadow: K.shadowSm,
          ),
          child: Icon(icon, size: 32, color: K.brown700),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: kText(18, weight: w900),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: kText(14, weight: FontWeight.w400, color: K.stone500),
          ),
        ],
        if (child != null) ...[const SizedBox(height: 12), child!],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          GradientButton(label: actionLabel!, onTap: onAction, expand: false, height: 42, radius: 12, padding: 20),
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
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
    decoration: BoxDecoration(
      color: K.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: K.red100),
      boxShadow: K.shadowSm,
    ),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: K.red50, borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.warning_amber_rounded, size: 32, color: K.red500),
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
            backgroundColor: K.stone900,
            foregroundColor: Colors.white,
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
