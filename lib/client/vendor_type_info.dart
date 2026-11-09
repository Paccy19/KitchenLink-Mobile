/// What the sign-up page says about each kitchen type: the card text, the
/// "Great for / Less suited for" profile, how the type takes orders, and the
/// food categories that suit it. Same as the website's data/vendorTypes.js
/// (keep in sync with it and the backend's config/vendorTypes.js).
library;

import 'package:intl/intl.dart';

class VendorTypeInfo {
  const VendorTypeInfo({
    required this.description,
    required this.strengths,
    required this.lessSuited,
    required this.note,
    required this.rules,
    required this.categoryKeywords,
    this.title,
    this.examples = const [],
  });

  /// Longer name on sign-up cards ("Other food business"); null = the label.
  final String? title;
  final String description;
  final List<String> strengths;
  final List<String> lessSuited;
  final String note;
  final OrderingRules rules;
  final List<String> categoryKeywords;

  /// "Other is for kitchens like:".
  final List<String> examples;
}

class OrderingRules {
  const OrderingRules({
    required this.orderNow,
    required this.minLeadMinutes,
    required this.maxDaysAhead,
    this.dailyOrderLimit,
    this.minOrderRwf = 0,
    this.maxItemsPerOrder,
  });

  final bool orderNow;
  final int minLeadMinutes;
  final int maxDaysAhead;
  final int? dailyOrderLimit;
  final int minOrderRwf;
  final int? maxItemsPerOrder;

  /// The website's orderingRuleLines.
  List<String> get lines {
    final n = NumberFormat.decimalPattern('en');
    return [
      orderNow ? 'Orders for now or later' : 'Advance orders only · at least ${formatLead(minLeadMinutes)} ahead',
      maxDaysAhead == 1 ? 'Book for today or tomorrow' : 'Book up to $maxDaysAhead days ahead',
      if (minOrderRwf > 0) 'Minimum order ${n.format(minOrderRwf)} RWF',
      if (maxItemsPerOrder != null) 'Up to $maxItemsPerOrder dishes per order',
      if (dailyOrderLimit != null) 'Only $dailyOrderLimit orders a day',
    ];
  }
}

/// "45 minutes", "4 hours", "1 day".
String formatLead(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) return '${minutes ~/ 1440} day${minutes == 1440 ? '' : 's'}';
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}';
  return '$minutes minutes';
}

const vendorTypeInfo = <String, VendorTypeInfo>{
  'home_cook': VendorTypeInfo(
    description: 'Home-made meals cooked in a family kitchen.',
    strengths: ['Sell any food', 'Scheduled orders & pre-orders', "Tomorrow's Special", 'Small daily capacity', 'Personal touch'],
    lessSuited: ['High-volume immediate orders', 'Large catering', 'Formal dine-in feel'],
    note: 'Best for homemade food with limited daily slots.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 45, maxDaysAhead: 3, dailyOrderLimit: 20, maxItemsPerOrder: 10),
    categoryKeywords: ['local', 'african', 'rwandan', 'breakfast', 'lunch', 'dinner', 'healthy'],
  ),
  'restaurant': VendorTypeInfo(
    description: 'A sit-down or takeaway restaurant with a full menu.',
    strengths: ['Full menu', 'High volume', 'Immediate & scheduled orders', 'Delivery & pick-up'],
    lessSuited: ['Very small home-style batches'],
    note: 'Classic full-service kitchen.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 45, maxDaysAhead: 7),
    categoryKeywords: [
      'local',
      'african',
      'rwandan',
      'fastfood',
      'lunch',
      'dinner',
      'seafood',
      'grill',
      'pizza',
      'burger',
      'dessert',
      'drink',
    ],
  ),
  'cafe': VendorTypeInfo(
    description: 'Coffee, tea, light meals and snacks.',
    strengths: ['Coffee', 'Light meals', 'Breakfast', 'Snacks', 'Quick orders'],
    lessSuited: ['Heavy main meals', 'Large catering', 'Late-night heavy food'],
    note: 'Casual and daytime-focused.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 30, maxDaysAhead: 2, maxItemsPerOrder: 15),
    categoryKeywords: ['breakfast', 'bakery', 'dessert', 'drink', 'juice', 'healthy'],
  ),
  'bakery': VendorTypeInfo(
    description: 'Bread, cakes, pastries and baked goods.',
    strengths: ['Bread', 'Cakes', 'Pastries', 'Desserts', 'Pre-orders'],
    lessSuited: ['Full savoury meals', 'Hot cooked dishes as the main business'],
    note: 'Can still sell savoury items.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 45, maxDaysAhead: 14),
    categoryKeywords: ['bakery', 'bread', 'pastr', 'cake', 'cookie', 'dessert', 'breakfast'],
  ),
  'caterer': VendorTypeInfo(
    description: 'Food for events, offices and large groups.',
    strengths: ['Bulk orders', 'Events', 'Advance & scheduled orders', 'Large quantities'],
    lessSuited: ['Small single-portion immediate orders'],
    note: 'Strong with Offer Days and pre-orders.',
    rules: OrderingRules(orderNow: false, minLeadMinutes: 1440, maxDaysAhead: 30, minOrderRwf: 20000),
    categoryKeywords: ['local', 'african', 'rwandan', 'lunch', 'dinner', 'grill', 'dessert', 'drink'],
  ),
  'food_truck': VendorTypeInfo(
    description: 'Street food from a mobile kitchen.',
    strengths: ['Mobile location', 'Street-style food', 'Quick service'],
    lessSuited: ['Fixed-address fine dining', 'Large advance catering'],
    note: 'Location can change.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 30, maxDaysAhead: 1, maxItemsPerOrder: 15),
    categoryKeywords: ['fastfood', 'burger', 'pizza', 'grill', 'drink'],
  ),
  'chef': VendorTypeInfo(
    description: 'A professional chef cooking signature dishes.',
    strengths: ['Custom menus', 'Private dining', 'Premium & specialty dishes', 'Scheduled orders'],
    lessSuited: ['High-volume standard delivery', 'Cheap daily meals'],
    note: 'More personalised and higher-end.',
    rules: OrderingRules(orderNow: false, minLeadMinutes: 240, maxDaysAhead: 14, dailyOrderLimit: 8, minOrderRwf: 10000),
    categoryKeywords: ['african', 'local', 'seafood', 'lunch', 'dinner', 'dessert', 'healthy'],
  ),
  'meal_prep': VendorTypeInfo(
    description: 'Ready-made meals prepared in advance for the week.',
    strengths: ['Weekly plans', 'Portioned meals', 'Subscriptions', 'Scheduled orders'],
    lessSuited: ['On-demand single hot meals', 'Café-style snacks'],
    note: 'Best with recurring orders.',
    rules: OrderingRules(orderNow: false, minLeadMinutes: 720, maxDaysAhead: 14),
    categoryKeywords: ['healthy', 'breakfast', 'lunch', 'dinner'],
  ),
  'juice_drinks': VendorTypeInfo(
    description: 'Fresh juices, smoothies and other drinks.',
    strengths: ['Juices', 'Smoothies', 'Beverages', 'Light add-ons'],
    lessSuited: ['Full solid meals as the main offering'],
    note: 'Can still sell light food.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 30, maxDaysAhead: 2),
    categoryKeywords: ['drink', 'juice', 'healthy'],
  ),
  'other': VendorTypeInfo(
    title: 'Other food business',
    description: 'Any food business that does not fit the types above (specialty, niche, or unique concept).',
    strengths: ["Any specialty or niche concept that doesn't fit the types above"],
    lessSuited: [],
    note: 'Catch-all for unique businesses — fully open.',
    rules: OrderingRules(orderNow: true, minLeadMinutes: 45, maxDaysAhead: 7),
    categoryKeywords: [],
    examples: [
      'Snack or street-food kiosks',
      'Single-cuisine or cultural kitchens',
      'Diet-specific kitchens (vegan, keto, diabetic-friendly)',
      'Dessert-only or ice-cream shops',
      'Hybrid concepts that mix categories',
      'Niche sellers (only grilled fish, party snacks, breakfast packages)',
      'Pop-up or cloud kitchens',
    ],
  ),
};

/// The category names that suit a type; [] when every one does. A category
/// the admin tagged for the type (its `vendor_types`) always counts.
List<String> suggestedCategories(String typeCode, List<({String name, List<String> vendorTypes})> categories) {
  final keywords = vendorTypeInfo[typeCode]?.categoryKeywords ?? const [];
  if (keywords.isEmpty) return const [];
  return [
    for (final c in categories)
      if (c.vendorTypes.contains(typeCode) || keywords.any(c.name.toLowerCase().replaceAll(RegExp('[^a-z]'), '').contains)) c.name,
  ];
}
