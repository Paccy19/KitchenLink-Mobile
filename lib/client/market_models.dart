/// The customer flows beyond the homepage (kitchen page, basket, checkout,
/// orders, support…), mirroring the website's normalize.js, data/vendorTypes.js,
/// utils/schedule.js and checkout/paymentMethods.js.
library;

import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../ui/vendor_types.dart';
import 'models.dart';

num _num(dynamic value, [num fallback = 0]) {
  if (value is num && value.isFinite) return value;
  if (value is String) return num.tryParse(value.trim()) ?? fallback;
  return fallback;
}

num? _numOrNull(dynamic value) => value == null ? null : _num(value);

String _str(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

Json _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Json> _list(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : <Json>[];

final _thousands = NumberFormat.decimalPattern('en_US');

/// `2,500 RWF` (the order pages' format; the cards use `RWF 2,500`).
String rwf(num amount) => '${_thousands.format(amount.round())} RWF';

DateTime? parseIso(dynamic iso) =>
    iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();

// ---- Ordering rules (data/vendorTypes.js) ----------------------------------

class OrderingRules {
  const OrderingRules({
    required this.vendorType,
    required this.orderNow,
    required this.minLeadMinutes,
    required this.maxDaysAhead,
    this.dailyOrderLimit,
    this.minOrderRwf = 0,
    this.maxItemsPerOrder,
    this.fullyBookedToday = false,
  });

  final String vendorType;
  final bool orderNow;
  final int minLeadMinutes;
  final int maxDaysAhead;
  final int? dailyOrderLimit;
  final int minOrderRwf;
  final int? maxItemsPerOrder;
  final bool fullyBookedToday;

  OrderingRules copyWith({bool? orderNow}) => OrderingRules(
    vendorType: vendorType,
    orderNow: orderNow ?? this.orderNow,
    minLeadMinutes: minLeadMinutes,
    maxDaysAhead: maxDaysAhead,
    dailyOrderLimit: dailyOrderLimit,
    minOrderRwf: minOrderRwf,
    maxItemsPerOrder: maxItemsPerOrder,
    fullyBookedToday: fullyBookedToday,
  );

  /// Each type's defaults (keep in sync with the backend's config/vendorTypes.js RULES).
  static const _defaults = {
    'home_cook': OrderingRules(
      vendorType: 'home_cook',
      orderNow: true,
      minLeadMinutes: 45,
      maxDaysAhead: 3,
      dailyOrderLimit: 20,
      maxItemsPerOrder: 10,
    ),
    'restaurant': OrderingRules(
      vendorType: 'restaurant',
      orderNow: true,
      minLeadMinutes: 45,
      maxDaysAhead: 7,
    ),
    'cafe': OrderingRules(
      vendorType: 'cafe',
      orderNow: true,
      minLeadMinutes: 30,
      maxDaysAhead: 2,
      maxItemsPerOrder: 15,
    ),
    'bakery': OrderingRules(
      vendorType: 'bakery',
      orderNow: true,
      minLeadMinutes: 45,
      maxDaysAhead: 14,
    ),
    'caterer': OrderingRules(
      vendorType: 'caterer',
      orderNow: false,
      minLeadMinutes: 1440,
      maxDaysAhead: 30,
      minOrderRwf: 20000,
    ),
    'food_truck': OrderingRules(
      vendorType: 'food_truck',
      orderNow: true,
      minLeadMinutes: 30,
      maxDaysAhead: 1,
      maxItemsPerOrder: 15,
    ),
    'chef': OrderingRules(
      vendorType: 'chef',
      orderNow: false,
      minLeadMinutes: 240,
      maxDaysAhead: 14,
      dailyOrderLimit: 8,
      minOrderRwf: 10000,
    ),
    'meal_prep': OrderingRules(
      vendorType: 'meal_prep',
      orderNow: false,
      minLeadMinutes: 720,
      maxDaysAhead: 14,
    ),
    'juice_drinks': OrderingRules(
      vendorType: 'juice_drinks',
      orderNow: true,
      minLeadMinutes: 30,
      maxDaysAhead: 2,
    ),
    'other': OrderingRules(
      vendorType: 'other',
      orderNow: true,
      minLeadMinutes: 45,
      maxDaysAhead: 7,
    ),
  };

  /// The API's `ordering` object when present, otherwise the type's defaults.
  factory OrderingRules.from(dynamic raw, dynamic typeValue) {
    final json = _map(raw);
    final code = vendorTypeOf(json['vendor_type'] ?? typeValue).code;
    final base = _defaults[code] ?? _defaults['other']!;
    if (json.isEmpty) return base;
    int? optInt(String key, int? fallback) =>
        json.containsKey(key) ? _numOrNull(json[key])?.toInt() : fallback;
    return OrderingRules(
      vendorType: code,
      orderNow: json['order_now'] is bool
          ? json['order_now'] as bool
          : base.orderNow,
      minLeadMinutes:
          optInt('min_lead_minutes', base.minLeadMinutes) ??
          base.minLeadMinutes,
      maxDaysAhead:
          optInt('max_days_ahead', base.maxDaysAhead) ?? base.maxDaysAhead,
      dailyOrderLimit: optInt('daily_order_limit', base.dailyOrderLimit),
      minOrderRwf: optInt('min_order_rwf', base.minOrderRwf) ?? 0,
      maxItemsPerOrder: optInt('max_items_per_order', base.maxItemsPerOrder),
      fullyBookedToday: json['fully_booked_today'] == true,
    );
  }

  /// Short customer-facing lines describing how a kitchen takes orders.
  List<String> get lines => [
    orderNow
        ? 'Orders for now or later'
        : 'Advance orders only · at least ${formatLead(minLeadMinutes)} ahead',
    maxDaysAhead == 1
        ? 'Book for today or tomorrow'
        : 'Book up to $maxDaysAhead days ahead',
    if (minOrderRwf > 0) 'Minimum order ${_thousands.format(minOrderRwf)} RWF',
    if (maxItemsPerOrder != null) 'Up to $maxItemsPerOrder dishes per order',
    if (dailyOrderLimit != null) 'Only $dailyOrderLimit orders a day',
  ];

  /// Why a basket can't be checked out under these rules (null when fine).
  String? basketProblem({required num subtotal, required int itemCount}) {
    if (minOrderRwf > 0 && subtotal < minOrderRwf) {
      return 'This kitchen takes orders from ${_thousands.format(minOrderRwf)} RWF — add ${_thousands.format(minOrderRwf - subtotal)} RWF more.';
    }
    if (maxItemsPerOrder != null && itemCount > maxItemsPerOrder!) {
      return 'This kitchen takes up to $maxItemsPerOrder dishes per order — remove ${itemCount - maxItemsPerOrder!}.';
    }
    return null;
  }
}

/// "45 minutes", "4 hours", "1 day".
String formatLead(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) {
    return '${minutes ~/ 1440} day${minutes == 1440 ? '' : 's'}';
  }
  if (minutes >= 60 && minutes % 60 == 0) {
    return '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}';
  }
  return '$minutes minutes';
}

// ---- Schedule slots (utils/schedule.js) ------------------------------------

const scheduleTimeSlots = [
  '08:30 AM',
  '09:30 AM',
  '11:30 AM',
  '12:30 PM',
  '01:30 PM',
  '02:30 PM',
  '06:30 PM',
  '07:30 PM',
];

/// Local midnight of "Today", "Tomorrow" or "YYYY-MM-DD".
DateTime _dayStart(String value) {
  final now = DateTime.now();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match != null) {
    return DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }
  return DateTime(
    now.year,
    now.month,
    now.day + (value.toLowerCase() == 'tomorrow' ? 1 : 0),
  );
}

/// The instant for a day + "12:30 PM".
DateTime buildScheduledFor(String day, String time) {
  final start = _dayStart(day);
  final parts = time.split(' ');
  final hm = parts.first.split(':');
  final h = int.tryParse(hm.first) ?? 12;
  final m = hm.length > 1 ? int.tryParse(hm[1]) ?? 0 : 0;
  final pm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
  return DateTime(
    start.year,
    start.month,
    start.day,
    (h % 12) + (pm ? 12 : 0),
    m,
  );
}

/// "Today", "Tomorrow" or "Fri 30 Oct".
String scheduleDayLabel(String day) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)
    ? DateFormat('EEE d MMM').format(_dayStart(day))
    : day;

/// Slots on a day that meet the kitchen's notice and how far ahead it books.
List<String> slotsFor(String day, OrderingRules? rules) {
  final now = DateTime.now();
  final lead = Duration(minutes: rules?.minLeadMinutes ?? 45);
  final ahead = Duration(days: rules?.maxDaysAhead ?? 7);
  return scheduleTimeSlots.where((slot) {
    final at = buildScheduledFor(day, slot);
    return !at.isBefore(now.add(lead)) && !at.isAfter(now.add(ahead));
  }).toList();
}

/// The days a customer may pick (only days with a free slot): value and label.
List<({String value, String label})> scheduleDays(OrderingRules? rules) {
  final days = <({String value, String label})>[];
  final max = rules?.maxDaysAhead ?? 7;
  final now = DateTime.now();
  for (var offset = 0; offset <= max; offset++) {
    final date = DateTime(now.year, now.month, now.day + offset);
    final value = offset == 0
        ? 'Today'
        : offset == 1
        ? 'Tomorrow'
        : DateFormat('yyyy-MM-dd').format(date);
    if (slotsFor(value, rules).isNotEmpty) {
      days.add((value: value, label: scheduleDayLabel(value)));
    }
  }
  return days;
}

// ---- Kitchen page (GET /vendors/{id}) --------------------------------------

class MenuDish {
  MenuDish({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.image,
    required this.category,
    required this.isAvailable,
    required this.isPreorder,
    required this.preorderCutoff,
    required this.popular,
    required this.prepTime,
  });

  final String id;
  final String name;
  final String description;
  final num price;
  final String image;
  final String category;
  final bool isAvailable;
  final bool isPreorder;
  final String preorderCutoff;
  final bool popular;
  final String prepTime;

  factory MenuDish.fromJson(Json raw, {String category = 'Menu'}) {
    final prep = raw['estimated_prep_time'] ?? raw['prep_time'];
    return MenuDish(
      id: _str(raw['id'] ?? raw['menu_item_id']),
      name: _str(raw['name'], 'Dish'),
      description: _str(raw['description']),
      price: _num(raw['price_rwf'] ?? raw['price']),
      image: _str(raw['image_url'] ?? raw['image']),
      category: _str(
        raw['category'] is String ? raw['category'] : null,
        category,
      ),
      isAvailable: raw['is_available'] is bool
          ? raw['is_available'] as bool
          : true,
      isPreorder: raw['is_preorder'] == true,
      preorderCutoff: _str(raw['preorder_cutoff']),
      popular: raw['popular'] == true || raw['is_popular'] == true,
      prepTime: prep == null
          ? ''
          : (prep is num ? '${numText(prep)} min' : _str(prep)),
    );
  }

  /// A dish from a search or the homepage (only what the card knows).
  factory MenuDish.fromDish(Dish dish) => MenuDish(
    id: dish.id,
    name: dish.name,
    description: '',
    price: dish.price,
    image: dish.image,
    category: dish.category,
    isAvailable: dish.isAvailable,
    isPreorder: false,
    preorderCutoff: '',
    popular: false,
    prepTime: dish.hasPrep ? dish.prepTime : '',
  );
}

/// The kitchen a basket line or saved dish belongs to.
class KitchenRef {
  const KitchenRef({
    required this.id,
    required this.name,
    this.typeCode = 'other',
    this.neighborhood = '',
    this.ordering,
  });

  final String id;
  final String name;
  final String typeCode;
  final String neighborhood;
  final OrderingRules? ordering;

  Json toJson() => {
    'id': id,
    'name': name,
    'type': typeCode,
    'neighborhood': neighborhood,
  };

  factory KitchenRef.fromJson(Json raw) => KitchenRef(
    id: _str(raw['id']),
    name: _str(raw['name'], 'Kitchen'),
    typeCode: vendorTypeOf(raw['type'] ?? raw['vendor_type']).code,
    neighborhood: _str(raw['neighborhood']),
    ordering: raw['ordering'] is Map
        ? OrderingRules.from(raw['ordering'], raw['vendor_type'])
        : null,
  );
}

class Storefront {
  Storefront({
    required this.vendor,
    required this.menu,
    required this.categories,
    required this.ordering,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.specialOrderable,
  });

  final Vendor vendor;
  final List<MenuDish> menu;
  final List<String> categories;
  final OrderingRules ordering;
  final String address;
  final double? latitude;
  final double? longitude;
  final bool specialOrderable;

  KitchenRef get ref => KitchenRef(
    id: vendor.id,
    name: vendor.name,
    typeCode: vendor.typeCode,
    neighborhood: vendor.neighborhood,
    ordering: ordering,
  );

  factory Storefront.fromJson(dynamic data) {
    final raw = _map(data);
    final menu = <MenuDish>[];
    for (final group in _list(raw['menu'])) {
      final items = group['items'];
      if (items is List) {
        final category = _str(group['category'], 'Menu');
        menu.addAll(
          _list(
            items,
          ).map((item) => MenuDish.fromJson(item, category: category)),
        );
      } else {
        menu.add(MenuDish.fromJson(group));
      }
    }
    final categories =
        raw['menu_categories'] is List &&
            (raw['menu_categories'] as List).isNotEmpty
        ? (raw['menu_categories'] as List).map((c) => '$c').toList()
        : menu.map((d) => d.category).toSet().toList();
    final location = _map(raw['location']);
    final special = _map(raw['special']);
    return Storefront(
      vendor: Vendor.fromJson(raw),
      menu: menu,
      categories: categories,
      ordering: OrderingRules.from(raw['ordering'], raw['vendor_type']),
      address: _str(location['address']),
      latitude: _numOrNull(location['latitude'])?.toDouble(),
      longitude: _numOrNull(location['longitude'])?.toDouble(),
      specialOrderable: special['is_orderable'] == true,
    );
  }
}

/// The basket's pre-order target: a kitchen's "Tomorrow's Special".
class PreorderSpecial {
  const PreorderSpecial({
    required this.vendorId,
    required this.vendorName,
    required this.text,
    required this.cutoffAt,
    required this.deliveryAt,
  });

  final String vendorId;
  final String vendorName;
  final String text;
  final String cutoffAt;
  final String deliveryAt;
}

// ---- Basket ----------------------------------------------------------------

class CartLine {
  CartLine({
    required this.dishId,
    required this.name,
    required this.price,
    required this.image,
    required this.quantity,
    required this.vendorId,
    required this.vendorName,
    this.isAvailable = true,
  });

  final String dishId;
  final String name;
  final num price;
  final String image;
  int quantity;
  final String vendorId;
  final String vendorName;
  final bool isAvailable;

  Json toJson() => {
    'id': dishId,
    'name': name,
    'price': price,
    'image': image,
    'quantity': quantity,
    'vendorId': vendorId,
    'vendorName': vendorName,
  };

  factory CartLine.fromJson(Json raw) => CartLine(
    dishId: _str(raw['id']),
    name: _str(raw['name'], 'Dish'),
    price: _num(raw['price']),
    image: _str(raw['image']),
    quantity: _num(raw['quantity'], 1).toInt(),
    vendorId: _str(raw['vendorId']),
    vendorName: _str(raw['vendorName']),
  );

  /// One line of the account basket (GET /cart).
  factory CartLine.fromApi(Json raw, String vendorName) => CartLine(
    dishId: _str(raw['menu_item_id']),
    name: _str(raw['name'], 'Dish'),
    price: _num(raw['price_rwf']),
    image: _str(raw['image_url']),
    quantity: _num(raw['quantity'], 1).toInt(),
    vendorId: _str(raw['vendor_id']),
    vendorName: _str(raw['vendor_name'], vendorName),
    isAvailable: raw['is_available'] != false,
  );
}

/// GET /vendors/{id}/delivery-quote.
class DeliveryQuote {
  DeliveryQuote({
    required this.fee,
    required this.distanceKm,
    required this.kitchenDelivers,
    required this.unavailableReason,
  });

  final num? fee;
  final num? distanceKm;
  final bool kitchenDelivers;
  final String? unavailableReason;

  factory DeliveryQuote.fromJson(dynamic data) {
    final raw = _map(data);
    final reason = _str(raw['unavailable_reason']);
    return DeliveryQuote(
      fee: _numOrNull(raw['delivery_fee_rwf']),
      distanceKm: _numOrNull(raw['distance_km']),
      kitchenDelivers: raw['fulfillment'] == 'vendor_delivery',
      unavailableReason: reason.isEmpty ? null : reason,
    );
  }
}

// ---- Saved delivery addresses (kept on the device, like the website) -------

class SavedAddress {
  SavedAddress({
    required this.id,
    required this.title,
    required this.street,
    required this.district,
    this.instructions = '',
    this.isDefault = false,
  });

  final String id;
  final String title;
  final String street;
  final String district;
  final String instructions;
  bool isDefault;

  Json toJson() => {
    'id': id,
    'title': title,
    'street': street,
    'district': district,
    'instructions': instructions,
    'isDefault': isDefault,
  };

  factory SavedAddress.fromJson(Json raw) => SavedAddress(
    id: _str(raw['id']),
    title: _str(raw['title'], 'Home'),
    street: _str(raw['street']),
    district: _str(raw['district']),
    instructions: _str(raw['instructions']),
    isDefault: raw['isDefault'] == true,
  );
}

// ---- Payment (components/checkout/paymentMethods.js) -----------------------

class PaymentMethod {
  const PaymentMethod(this.code, this.label, this.hint);

  final String code;
  final String label;
  final String hint;
}

const paymentMethods = [
  PaymentMethod(
    'mobile_money',
    'Mobile Money',
    'MTN or Airtel — +25078, +25079 or +25073',
  ),
  PaymentMethod('card', 'Cards', 'Visa or Mastercard via secure checkout'),
  PaymentMethod('ekash', 'eKash', 'Pay instantly from your eKash wallet'),
  PaymentMethod('wallet', 'Wallet', 'Pay from the wallet linked to your phone'),
];

/// "+250 788 123 456" → "0788123456".
String localPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('250')) digits = digits.substring(3);
  if (digits.isNotEmpty && !digits.startsWith('0')) digits = '0$digits';
  return digits;
}

bool isMomoPhone(String raw) =>
    RegExp(r'^0(78|79|73)\d{7}$').hasMatch(localPhone(raw));
bool isRwandaPhone(String raw) =>
    RegExp(r'^0(72|73|78|79)\d{7}$').hasMatch(localPhone(raw));

bool _passesLuhn(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var digit = int.parse(digits[digits.length - 1 - i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 == 0;
}

bool _expiryNotPast(String expiry) {
  final parts = expiry.split('/');
  final month = int.parse(parts[0]);
  final year = int.parse(parts[1]);
  final now = DateTime.now();
  return year * 12 + month >= (now.year % 100) * 12 + now.month;
}

/// Checks the inputs for [method] and returns the `payment_details` to send,
/// or the error to show. The CVV is checked but never sent.
({String? error, Json? details}) buildPaymentDetails(
  String method, {
  String phone = '',
  String cardNumber = '',
  String cardExpiry = '',
  String cardCvv = '',
}) {
  if (method == 'card') {
    final number = cardNumber.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{13,19}$').hasMatch(number) || !_passesLuhn(number)) {
      return (error: 'Enter a valid card number.', details: null);
    }
    if (!RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(cardExpiry.trim())) {
      return (error: 'Enter the card expiry as MM/YY.', details: null);
    }
    if (!_expiryNotPast(cardExpiry.trim())) {
      return (error: 'This card has expired.', details: null);
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(cardCvv.trim())) {
      return (error: 'Enter the card CVV (3–4 digits).', details: null);
    }
    return (
      error: null,
      details: {'card_number': number, 'card_expiry': cardExpiry.trim()},
    );
  }
  final ok = method == 'mobile_money'
      ? isMomoPhone(phone)
      : isRwandaPhone(phone);
  if (!ok) {
    return (
      error: method == 'mobile_money'
          ? 'Enter a valid MTN or Airtel number (+25078, +25079 or +25073).'
          : 'Enter a valid Rwandan mobile number (e.g. 0788123456).',
      details: null,
    );
  }
  return (error: null, details: {'phone': localPhone(phone)});
}

/// "1234567890123" → "1234 5678 9012 3".
String formatCardNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final cut = digits.length > 19 ? digits.substring(0, 19) : digits;
  return cut.replaceAllMapped(RegExp(r'(\d{4})(?=\d)'), (m) => '${m[1]} ');
}

/// "1227" → "12/27".
String formatCardExpiry(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 4) digits = digits.substring(0, 4);
  return digits.length >= 3
      ? '${digits.substring(0, 2)}/${digits.substring(2)}'
      : digits;
}

// ---- Orders (normalizeOrder) -----------------------------------------------

class OrderStep {
  const OrderStep(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

const deliverySteps = [
  OrderStep('placed', 'Order placed', 'Your order was sent to the kitchen.'),
  OrderStep(
    'confirmed',
    'Confirmed by kitchen',
    'The kitchen accepted your order.',
  ),
  OrderStep(
    'preparing',
    'Preparing your food',
    'Fresh ingredients are being cooked.',
  ),
  OrderStep(
    'ready',
    'Ready for pickup',
    'Food packed and waiting for delivery.',
  ),
  OrderStep(
    'assigned',
    'Assigned to a delivery worker',
    'A delivery worker is heading to the vendor to collect your order.',
  ),
  OrderStep(
    'picked_up',
    'Picked up',
    'Your order is with the delivery worker — on the way to you.',
  ),
  OrderStep(
    'out_for_delivery',
    'Out for delivery',
    'Your order is on the way.',
  ),
  OrderStep('delivered', 'Delivered', 'Enjoy your meal!'),
];

const pickupSteps = [
  OrderStep('placed', 'Order placed', 'Your order was sent to the kitchen.'),
  OrderStep(
    'confirmed',
    'Confirmed by kitchen',
    'The kitchen accepted your order.',
  ),
  OrderStep(
    'preparing',
    'Preparing your food',
    'Fresh ingredients are being cooked.',
  ),
  OrderStep(
    'ready',
    'Ready to collect',
    'Go to the kitchen and give them your pickup code.',
  ),
  OrderStep(
    'delivered',
    'Collected',
    'You collected your order. Enjoy your meal!',
  ),
];

const kitchenDeliverySteps = [
  OrderStep('placed', 'Order placed', 'Your order was sent to the kitchen.'),
  OrderStep(
    'confirmed',
    'Confirmed by kitchen',
    'The kitchen accepted your order.',
  ),
  OrderStep(
    'preparing',
    'Preparing your food',
    'Fresh ingredients are being cooked.',
  ),
  OrderStep(
    'ready',
    'On the way',
    'The kitchen is bringing your order. Give them your code when it arrives.',
  ),
  OrderStep(
    'delivered',
    'Delivered',
    'The kitchen delivered your order. Enjoy!',
  ),
];

/// "Order placed", "Preparing your food"… for any status.
String orderStatusLabel(String status) =>
    deliverySteps.where((s) => s.id == status).firstOrNull?.label ??
    (status == 'cancelled' ? 'Cancelled' : status.replaceAll('_', ' '));

class OrderLine {
  OrderLine({
    required this.dishId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.image,
  });

  final String dishId;
  final String name;
  final num price;
  final int quantity;
  final String image;
}

class CustomerOrder {
  CustomerOrder(this.raw);

  /// The API's order as is (the refund, deposit and event parts are read from it).
  final Json raw;

  Json get _vendor => _map(raw['vendor']);
  Json get _payment => _map(raw['payment']);
  Json get _delivery => _map(raw['delivery']);
  Json get pickup => _map(raw['pickup']);
  Json get deliveryLocation => _map(raw['delivery_location']);

  String get id => _str(raw['id'] ?? raw['order_id']);
  String get orderNumber => _str(raw['order_number'], id);
  DateTime? get createdAt => parseIso(raw['created_at'] ?? raw['placed_at']);
  String get orderType => _str(raw['order_type'], 'immediate');
  String get orderTypeLabel => _str(raw['order_type_label'], 'Immediate');
  String get fulfillment => _str(raw['fulfillment'], 'delivery');
  bool get isPickup => fulfillment == 'pickup';
  bool get kitchenDelivers => fulfillment == 'vendor_delivery';
  String get scheduledFor => _str(raw['scheduled_for']);
  String get status => _str(raw['status'], 'placed');
  String get vendorId => _str(_vendor['id']);
  String get vendorName => _str(_vendor['name'], 'Kitchen');
  String get vendorTypeCode => vendorTypeOf(_vendor['vendor_type']).code;
  String get vendorLocation =>
      _str(deliveryLocation['neighborhood'], _str(_vendor['neighborhood']));
  String get vendorPhone =>
      _str(_vendor['phone'], _str(pickup['vendor_phone']));
  String get cancelReason => _str(raw['cancel_reason']);
  num get subtotal => _num(raw['subtotal_rwf']);
  num get deliveryFee => _num(raw['delivery_fee_rwf']);
  num get total => _num(raw['total_rwf']);
  String get paymentMethod => _str(
    _payment['method_label'],
    _str(raw['payment_method_label'], _str(raw['payment_method'], 'Payment')),
  );
  String get paymentStatus =>
      _str(raw['payment_status'], _str(_payment['status'], 'pending'));
  Json get paymentDetails =>
      _map(raw['payment_details'] ?? _payment['details']);
  Json? get refund => raw['refund'] is Map ? _map(raw['refund']) : null;
  Json? get deposit => raw['deposit'] is Map ? _map(raw['deposit']) : null;
  String get deliveryCode => _str(_delivery['proof_of_delivery_code']);
  bool get deliveryConfirmed => _delivery['otp_verified'] == true;
  String get dropOff => _str(deliveryLocation['address']);
  Json? get rider =>
      raw['rider'] is Map && _str(_map(raw['rider'])['name']).isNotEmpty
      ? _map(raw['rider'])
      : null;

  bool get isLive => status != 'delivered' && status != 'cancelled';
  bool get canCancel =>
      const ['placed', 'confirmed', 'preparing', 'ready'].contains(status);

  List<OrderLine> get items => [
    for (final item in _list(raw['items']))
      OrderLine(
        dishId: _str(item['menu_item_id'] ?? item['id']),
        name: _str(item['name'], 'Dish'),
        price: _num(item['price_rwf'] ?? item['price']),
        quantity: _num(item['quantity'], 1).toInt(),
        image: _str(item['image_url']),
      ),
  ];

  List<OrderStep> get steps => isPickup
      ? pickupSteps
      : kitchenDelivers
      ? kitchenDeliverySteps
      : deliverySteps;

  /// "Scheduled · Fri 6:30 PM", "12:45" or "25 minutes".
  String get estimatedTime {
    final scheduled = parseIso(raw['scheduled_for']);
    if (orderType != 'immediate' && scheduled != null) {
      return 'Scheduled · ${DateFormat('EEE h:mm a').format(scheduled)}';
    }
    final eta = parseIso(raw['estimated_delivery_at']);
    if (eta != null) return DateFormat('HH:mm').format(eta);
    if (raw['eta_minutes'] != null) return '${raw['eta_minutes']} minutes';
    return 'Pending';
  }
}
