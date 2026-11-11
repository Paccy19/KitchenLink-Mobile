import 'package:flutter/material.dart';

import 'theme.dart';

/// Kitchen business types. `code` is what the API stores and filters by; keep
/// in sync with the website's data/vendorTypes.js and the backend. The badge
/// colours are the website's (`bg-X-100 text-X-800 border-X-200`).
class VendorType {
  const VendorType(this.code, this.label, this.icon, this.background, this.foreground, this.border);

  final String code;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color border;
}

const vendorTypes = [
  VendorType('home_cook', 'Home Cook', Icons.home_outlined, Color(0xFFFEF3C7), Color(0xFF78350F), Color(0xFFFDE68A)),
  VendorType('restaurant', 'Restaurant', Icons.restaurant, Color(0xFFF5EBE1), Color(0xFF3D1B0C), Color(0xFFEBD7C5)),
  VendorType('cafe', 'Café', Icons.coffee_outlined, Color(0xFFFFEDD5), Color(0xFF9A3412), Color(0xFFFED7AA)),
  VendorType('bakery', 'Bakery', Icons.cake_outlined, Color(0xFFFFE4E6), Color(0xFF9F1239), Color(0xFFFECDD3)),
  VendorType('caterer', 'Caterer', Icons.celebration_outlined, Color(0xFFEDE9FE), Color(0xFF5B21B6), Color(0xFFDDD6FE)),
  VendorType('food_truck', 'Food Truck', Icons.local_shipping_outlined, Color(0xFFE0F2FE), Color(0xFF075985), Color(0xFFBAE6FD)),
  VendorType('chef', 'Chef', Icons.soup_kitchen_outlined, Color(0xFF292524), Colors.white, Color(0xFF292524)),
  VendorType('meal_prep', 'Meal Prep', Icons.rice_bowl_outlined, Color(0xFFD1FAE5), Color(0xFF065F46), Color(0xFFA7F3D0)),
  VendorType('juice_drinks', 'Juice & Drinks', Icons.local_drink_outlined, Color(0xFFECFCCB), Color(0xFF3F6212), Color(0xFFD9F99D)),
  VendorType('other', 'Other', Icons.storefront_outlined, Color(0xFFF5F5F4), Color(0xFF44403C), Color(0xFFE7E5E4)),
];

// Labels the API returned before types became codes.
const _legacy = {
  'home cook': 'home_cook',
  'café': 'cafe',
  'cafe': 'cafe',
  'food truck': 'food_truck',
  'meal-prep business': 'meal_prep',
  'meal prep': 'meal_prep',
  'juice/drinks vendor': 'juice_drinks',
  'juice & drinks': 'juice_drinks',
  'other food business': 'other',
  'bar & grill': 'restaurant',
};

/// A code or label → its type ('Other' when unknown).
VendorType vendorTypeOf(dynamic value) {
  final raw = (value ?? '').toString().trim();
  final lower = raw.toLowerCase();
  final code = vendorTypes.any((t) => t.code == raw)
      ? raw
      : vendorTypes.any((t) => t.code == lower)
      ? lower
      : _legacy[lower] ?? vendorTypes.where((t) => t.label.toLowerCase() == lower).firstOrNull?.code ?? 'other';
  return vendorTypes.firstWhere((t) => t.code == code);
}

/// The website's VendorTypeBadge: `rounded-full border font-black`, `xs` is
/// `px-2 py-0.5 text-[10px]`, `sm` is `px-2.5 py-0.5 text-[11px]`. In dark mode
/// it is re-tinted from its text colour, as in index.css.
class VendorTypeBadge extends StatelessWidget {
  const VendorTypeBadge(this.type, {super.key, this.small = false});

  final dynamic type;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = vendorTypeOf(type);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = Palette.of(context);
    final fg = dark && t.code == 'chef'
        ? Colors.white
        : dark
        ? Color.lerp(t.foreground, Colors.white, 0.55)!
        : t.foreground;
    final bg = dark ? Color.alphaBlend(fg.withValues(alpha: 0.22), p.card) : t.background;
    final border = dark ? fg.withValues(alpha: 0.4) : t.border;
    // IntrinsicWidth: the badge never wraps, so its minimum width is its full width.
    return IntrinsicWidth(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              t.label,
              softWrap: false,
              style: TextStyle(fontSize: small ? 10 : 11, height: 1.5, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one or more kitchen types as pills that scroll sideways (an empty list
/// means all types), like the website's VendorTypeFilter.
class VendorTypeFilter extends StatefulWidget {
  const VendorTypeFilter({super.key, required this.value, required this.onChanged, this.counts});

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final Map<String, int>? counts;

  @override
  State<VendorTypeFilter> createState() => _VendorTypeFilterState();
}

class _VendorTypeFilterState extends State<VendorTypeFilter> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value.toSet();
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(999),
      thumbColor: const Color(0xFFD8C3B3),
      trackVisibility: true,
      trackColor: const Color(0xFFF5F0EB),
      trackRadius: const Radius.circular(999),
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            _Pill(label: 'All types', active: selected.isEmpty, onTap: () => widget.onChanged([])),
            for (final type in vendorTypes) ...[
              const SizedBox(width: 8),
              _Pill(
                icon: type.icon,
                label: type.label,
                count: widget.counts == null ? null : widget.counts![type.code] ?? 0,
                active: selected.contains(type.code),
                onTap: () {
                  final next = {...selected};
                  next.contains(type.code) ? next.remove(type.code) : next.add(type.code);
                  widget.onChanged([
                    for (final t in vendorTypes)
                      if (next.contains(t.code)) t.code,
                  ]);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `px-3 py-2 rounded-2xl text-xs font-bold border`; selected pills use the
/// brown gradient with a ×.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap, this.icon, this.count});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // The admin console's chips are solid near-black (white on dark); the
    // marketplace keeps its brown gradient.
    final admin = identical(p, Palette.adminLight) || identical(p, Palette.adminDark);
    final adminDark = identical(p, Palette.adminDark);
    final fg = active ? (adminDark ? AppColors.ink : Colors.white) : p.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: active && !admin ? AppColors.buttonGradient : null,
        color: active ? (admin ? (adminDark ? const Color(0xFFF5F5F4) : AppColors.ink) : null) : p.card,
        borderRadius: BorderRadius.circular(admin ? 999 : 16),
        border: Border.all(color: active ? Colors.transparent : p.border),
        boxShadow: active && !admin ? AppColors.shadowMd : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
                Text(
                  label,
                  style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w700, color: fg),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: active ? Colors.white70 : p.faint),
                  ),
                ],
                if (active && icon != null) ...[const SizedBox(width: 6), Icon(Icons.close, size: 12, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
