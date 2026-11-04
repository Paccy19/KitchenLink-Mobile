import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Kitchen business types. `code` is what the API stores and filters by; keep
/// in sync with the website's data/vendorTypes.js and the backend.
class VendorType {
  const VendorType(this.code, this.label, this.icon, this.tone);

  final String code;
  final String label;
  final IconData icon;
  final Tone tone;
}

const vendorTypes = [
  VendorType('home_cook', 'Home Cook', Icons.home_outlined, Tone.amber),
  VendorType('restaurant', 'Restaurant', Icons.restaurant_outlined, Tone.orange),
  VendorType('cafe', 'Café', Icons.coffee_outlined, Tone.orange),
  VendorType('bakery', 'Bakery', Icons.cake_outlined, Tone.red),
  VendorType('caterer', 'Caterer', Icons.celebration_outlined, Tone.violet),
  VendorType('food_truck', 'Food Truck', Icons.local_shipping_outlined, Tone.blue),
  VendorType('chef', 'Chef', Icons.soup_kitchen_outlined, Tone.slate),
  VendorType('meal_prep', 'Meal Prep', Icons.lunch_dining_outlined, Tone.green),
  VendorType('juice_drinks', 'Juice & Drinks', Icons.local_drink_outlined, Tone.green),
  VendorType('other', 'Other', Icons.storefront_outlined, Tone.slate),
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

class VendorTypeBadge extends StatelessWidget {
  const VendorTypeBadge(this.type, {super.key});

  final dynamic type;

  @override
  Widget build(BuildContext context) {
    final value = vendorTypeOf(type);
    return ToneBadge(value.label, tone: value.tone, icon: value.icon);
  }
}

/// Pick one or more kitchen types as chips (an empty list means all types).
class VendorTypeFilter extends StatelessWidget {
  const VendorTypeFilter({super.key, required this.value, required this.onChanged, this.counts});

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final Map<String, int>? counts;

  @override
  Widget build(BuildContext context) {
    final selected = value.toSet();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        FilterChip(label: const Text('All types'), selected: selected.isEmpty, onSelected: (_) => onChanged([])),
        for (final type in vendorTypes) ...[
          const SizedBox(width: 6),
          FilterChip(
            avatar: Icon(type.icon, size: 15),
            label: Text(counts == null ? type.label : '${type.label} ${counts![type.code] ?? 0}'),
            selected: selected.contains(type.code),
            onSelected: (on) {
              final next = {...selected};
              on ? next.add(type.code) : next.remove(type.code);
              onChanged([for (final t in vendorTypes) if (next.contains(t.code)) t.code]);
            },
          ),
        ],
      ]),
    );
  }
}
