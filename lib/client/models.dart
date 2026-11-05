/// View-models for the marketplace, built from the API's snake_case payloads
/// the same way as the website's api/normalize.js.
library;

import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../ui/vendor_types.dart';

num _num(dynamic value, [num fallback = 0]) {
  if (value is num && value.isFinite) return value;
  if (value is String) {
    final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(value.replaceAll(',', '.'));
    if (match != null) return num.parse(match.group(0)!);
  }
  return fallback;
}

bool _bool(dynamic value, bool fallback) => value is bool ? value : fallback;

String _text(List<dynamic> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return '';
}

Json _map(dynamic value) => value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

/// The first list found under one of [keys] (or the payload itself).
List<Json> pickList(dynamic payload, List<String> keys) {
  dynamic list;
  if (payload is List) {
    list = payload;
  } else if (payload is Map) {
    for (final key in keys) {
      if (payload[key] is List) {
        list = payload[key];
        break;
      }
    }
  }
  return list is List ? list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];
}

final _thousands = NumberFormat.decimalPattern('en_US');

/// `RWF 2,500`, as the website.
String formatRwf(num amount) => 'RWF ${_thousands.format(amount)}';

/// 4.5 → "4.5", 4.0 → "4" (JavaScript number printing).
String numText(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _prepTime(dynamic value) {
  if (value is num) return '${numText(value)} min';
  final text = _text([value]);
  if (text.isEmpty) return '—';
  final hasDigit = RegExp(r'\d').hasMatch(text);
  final hasUnit = RegExp(r'min|hour|h\b', caseSensitive: false).hasMatch(text);
  return hasDigit && !hasUnit ? '$text min' : text;
}

class Category {
  Category({required this.id, required this.name, required this.iconUrl, required this.description});

  final String id;
  final String name;
  final String iconUrl;
  final String description;

  factory Category.fromJson(Json raw) {
    final name = _text([raw['name'], raw['title'], raw['label'], 'Category']);
    return Category(
      id: _text([raw['id'], raw['slug'], name.toLowerCase()]),
      name: name,
      iconUrl: _text([raw['icon_url'], raw['icon'], raw['image_url'], raw['emoji']]),
      description: _text([raw['description']]),
    );
  }
}

class Special {
  Special({required this.text, required this.cutoffAt, required this.deliveryAt});

  final String text;
  final String cutoffAt;
  final String deliveryAt;

  static Special? fromJson(dynamic value) {
    final raw = _map(value);
    if (raw.isEmpty || (raw['text'] == null && raw['delivery_at'] == null)) return null;
    return Special(text: _text([raw['text']]), cutoffAt: _text([raw['cutoff_at']]), deliveryAt: _text([raw['delivery_at']]));
  }
}

class Vendor {
  Vendor({
    required this.id,
    required this.name,
    required this.typeCode,
    required this.rating,
    required this.reviewsCount,
    required this.distanceKm,
    required this.hasDistance,
    required this.prepTime,
    required this.deliveryAvailable,
    required this.nationwide,
    required this.isOpen,
    required this.isNearby,
    required this.bannerUrl,
    required this.avatarUrl,
    required this.neighborhood,
    required this.description,
    required this.deliveryFee,
    this.special,
  });

  final String id;
  final String name;
  final String typeCode;
  final num rating;
  final int reviewsCount;
  final num distanceKm;
  final bool hasDistance;
  final String prepTime;
  final bool deliveryAvailable;
  final bool nationwide;
  final bool isOpen;
  final bool isNearby;
  final String bannerUrl;
  final String avatarUrl;
  final String neighborhood;
  final String description;
  final num deliveryFee;
  final Special? special;

  String get typeLabel => vendorTypeOf(typeCode).label;

  factory Vendor.fromJson(Json raw) {
    final location = raw['location'];
    final loc = _map(location);
    final distance = raw['distance_km'] ?? raw['distance'];
    return Vendor(
      id: _text([raw['id'], raw['vendor_id'], raw['slug']]),
      name: _text([raw['name'], raw['vendor_name'], raw['title'], 'Kitchen']),
      typeCode: vendorTypeOf(raw['vendor_type'] ?? raw['type'] ?? raw['kitchen_type']).code,
      rating: num.parse(_num(raw['rating'] ?? raw['average_rating']).toStringAsFixed(2)),
      reviewsCount: _num(raw['reviews_count'] ?? raw['rating_count']).toInt(),
      distanceKm: num.parse(_num(distance).toStringAsFixed(1)),
      hasDistance: distance != null,
      prepTime: _prepTime(raw['estimated_prep_time'] ?? raw['prep_time'] ?? raw['preparation_time']),
      deliveryAvailable: _bool(raw['delivery_available'] ?? raw['delivery'], true),
      nationwide: _bool(raw['nationwide'], false),
      isOpen: _bool(raw['is_open'] ?? raw['open'] ?? raw['is_open_now'], true),
      isNearby: _bool(raw['is_nearby'], false),
      bannerUrl: _text([raw['banner_image_url'], raw['banner_url'], raw['cover_image'], raw['image_url'], raw['banner']]),
      avatarUrl: _text([raw['avatar_url'], raw['logo_url'], raw['avatar']]),
      neighborhood: _text([raw['neighborhood'], loc['neighborhood'], location is String ? location : '', raw['area'], raw['address'], 'Kigali']),
      description: _text([raw['description'], raw['tagline'], raw['summary']]),
      deliveryFee: _num(raw['delivery_fee']),
      special: Special.fromJson(raw['special']),
    );
  }
}

class Dish {
  Dish({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
    required this.category,
    required this.isAvailable,
    required this.prepTime,
    required this.rating,
    required this.vendorId,
    required this.vendorName,
  });

  final String id;
  final String name;
  final num price;
  final String image;
  final String category;
  final bool isAvailable;
  final String prepTime;
  final num rating;
  final String vendorId;
  final String vendorName;

  bool get hasPrep => prepTime.isNotEmpty && prepTime != '—';

  factory Dish.fromJson(Json raw) {
    final vendor = raw['vendor'];
    final v = _map(vendor);
    return Dish(
      id: _text([raw['id'], raw['dish_id'], raw['item_id']]),
      name: _text([raw['name'], raw['title'], 'Dish']),
      price: _num(raw['price_rwf'] ?? raw['price'] ?? raw['amount']),
      image: _text([raw['image_url'], raw['image'], raw['photo_url'], raw['photo']]),
      category: _text([raw['category'], raw['category_name'], raw['menu_category'], raw['section'], 'Menu']),
      isAvailable: _bool(raw['is_available'] ?? raw['available'], true),
      prepTime: _prepTime(raw['estimated_prep_time'] ?? raw['prep_time']),
      rating: num.parse(_num(raw['rating']).toStringAsFixed(2)),
      vendorId: _text([v['id'], v['vendor_id'], vendor is String ? vendor : '', raw['vendor_id']]),
      vendorName: _text([v['name'], v['vendor_name'], raw['vendor_name']]),
    );
  }
}

class SpecialEntry {
  SpecialEntry(this.vendor, this.special);

  final Vendor vendor;
  final Special special;
}

class OfferDay {
  OfferDay({required this.id, required this.title, required this.details, required this.offerDate, required this.vendor});

  final String id;
  final String title;
  final String details;
  final String offerDate;
  final Vendor vendor;

  factory OfferDay.fromJson(Json raw) => OfferDay(
    id: _text([raw['id']]),
    title: _text([raw['title']]),
    details: _text([raw['details']]),
    offerDate: _text([raw['offer_date']]),
    vendor: Vendor.fromJson(_map(raw['vendor'])),
  );
}

class HomeFeed {
  HomeFeed({required this.categories, required this.featuredVendors, required this.popularDishes, this.updatedAt});

  final List<Category> categories;
  final List<Vendor> featuredVendors;
  final List<Dish> popularDishes;
  final DateTime? updatedAt;

  factory HomeFeed.fromJson(dynamic data) => HomeFeed(
    categories: pickList(data, ['categories']).map(Category.fromJson).toList(),
    featuredVendors: pickList(data, ['featured_vendors', 'featuredVendors', 'nearby_vendors', 'nearbyVendors', 'vendors']).map(Vendor.fromJson).toList(),
    popularDishes: pickList(data, ['popular_dishes', 'popularDishes', 'dishes']).map(Dish.fromJson).toList(),
    updatedAt: data is Map ? DateTime.tryParse('${data['updated_at'] ?? ''}')?.toLocal() : null,
  );
}

class VendorPage {
  VendorPage({required this.vendors, required this.total, required this.locationUsed});

  final List<Vendor> vendors;
  final int total;
  final bool locationUsed;

  factory VendorPage.fromJson(dynamic data) {
    final vendors = pickList(data, ['vendors']).map(Vendor.fromJson).toList();
    final meta = data is Map ? _map(data['meta']) : <String, dynamic>{};
    return VendorPage(vendors: vendors, total: _num(meta['total'], vendors.length).toInt(), locationUsed: meta['location_used'] == true);
  }
}

class SearchResult {
  SearchResult({required this.dishes, required this.vendors, required this.matchedTypes});

  final List<Dish> dishes;
  final List<Vendor> vendors;
  final List<String> matchedTypes;

  factory SearchResult.fromJson(dynamic data) {
    final meta = data is Map ? _map(data['meta']) : <String, dynamic>{};
    final types = meta['matched_vendor_types'];
    return SearchResult(
      dishes: pickList(data, ['dishes']).map(Dish.fromJson).toList(),
      vendors: pickList(data, ['vendors']).map(Vendor.fromJson).toList(),
      matchedTypes: types is List ? types.map((t) => t is Map ? '${t['code'] ?? ''}' : '$t').where((c) => c.isNotEmpty).toList() : const [],
    );
  }
}

// ---- Dates, as the website's utils/schedule.js and utils/offerDays.js ----

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Today at 6:00 PM", "Tomorrow at 9:30 AM", "Fri 24 Oct at 12:00 PM".
String formatScheduledFor(String iso) {
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) return '';
  final today = _day(DateTime.now());
  final days = _day(date).difference(today).inDays;
  final dayLabel = days == 0
      ? 'Today'
      : days == 1
      ? 'Tomorrow'
      : DateFormat('EEE d MMM').format(date);
  return '$dayLabel at ${DateFormat('h:mm a').format(date)}';
}

/// "Friday, 24 October" for an offer day ("YYYY-MM-DD").
String formatOfferDay(String day) {
  final date = DateTime.tryParse('${day}T12:00:00');
  if (date == null) return day;
  return DateFormat('EEEE, d MMMM').format(date);
}

/// "Today", "Tomorrow", "In 3 days".
String offerCountdown(String day) {
  final target = DateTime.tryParse('${day}T00:00:00');
  if (target == null) return '';
  final days = target.difference(_day(DateTime.now())).inHours ~/ 24;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}
