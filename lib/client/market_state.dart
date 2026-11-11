import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import 'customer_api.dart';
import 'customer_session.dart';
import 'location.dart';
import 'market_models.dart';

const _storage = FlutterSecureStorage();

Future<dynamic> _readJson(String key) async {
  try {
    final text = await _storage
        .read(key: key)
        .timeout(const Duration(seconds: 2));
    return text == null || text.isEmpty ? null : jsonDecode(text);
  } catch (_) {
    return null;
  }
}

Future<void> _writeJson(String key, Object? value) async {
  try {
    await _storage.write(key: key, value: jsonEncode(value));
  } catch (_) {}
}

/// Runs account changes one at a time, in tap order, like the website's
/// remoteQueue: the screen updates first, the server catches up.
class _Queue {
  Future<void> _tail = Future.value();
  int pending = 0;

  Future<T?> run<T>(
    Future<T> Function() task, {
    required void Function(Object error) onError,
  }) {
    pending++;
    final done = Completer<T?>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await task());
      } catch (error) {
        onError(error);
        done.complete(null);
      } finally {
        pending--;
      }
    });
    return done.future;
  }

  Future<void> get idle => _tail;
}

enum AddResult { added, conflict }

/// The basket (the website's CartContext): kept on the device for guests and
/// in the account once signed in, one kitchen at a time, with when and how
/// the order comes (now / scheduled / pre-order, delivery / pickup) and the
/// distance-priced delivery fee.
class Cart extends ChangeNotifier {
  Cart(this.api, this.session, this.location) {
    session.addListener(_onSession);
    location.addListener(_onLocation);
  }

  static const _key = 'ofk_cart';
  static const maxQuantity = 99;

  final CustomerApi api;
  final CustomerSession session;
  final ClientLocation location;
  final _queue = _Queue();

  List<CartLine> lines = [];
  KitchenRef? vendor;
  String? error;
  bool syncing = false;
  bool _syncFailed = false;
  String? _syncedToken;

  String orderType = 'immediate'; // 'immediate' | 'scheduled' | 'preorder'
  String fulfillment = 'delivery'; // 'delivery' | 'pickup'
  String scheduledDate = 'Tomorrow';
  String scheduledTime = '12:30 PM';
  PreorderSpecial? preorder;

  DeliveryQuote? quote;
  bool quoteLoading = false;
  bool quoteFailed = false;
  String _quoteKey = '';

  /// Shown by the screen as a snackbar (a failed basket change).
  void Function(String message)? onError;

  bool get isPickup => fulfillment == 'pickup';
  num get subtotal =>
      lines.fold<num>(0, (sum, line) => sum + line.price * line.quantity);
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);
  num? get deliveryFee => lines.isEmpty || isPickup ? 0 : quote?.fee;
  num get total => subtotal + (deliveryFee ?? 0);
  bool get kitchenDelivers => !isPickup && (quote?.kitchenDelivers ?? false);
  String? get unavailableReason => isPickup ? null : quote?.unavailableReason;

  /// The kitchen's ordering rules; a kitchen bringing food from far away needs it scheduled.
  OrderingRules? get rules {
    final v = vendor;
    if (v == null) return null;
    final base = v.ordering ?? OrderingRules.from(null, v.typeCode);
    return kitchenDelivers ? base.copyWith(orderNow: false) : base;
  }

  List<({String value, String label})> get days => scheduleDays(rules);
  List<String> get slots => slotsFor(scheduledDate, rules);
  String? get ruleProblem =>
      rules?.basketProblem(subtotal: subtotal, itemCount: itemCount);

  /// "Delivery fee (2.4 km)", "Kitchen's travel fee", "Delivery fee (you pick up)".
  String get feeLabel {
    if (isPickup) return 'Delivery fee (you pick up)';
    final name = kitchenDelivers ? "Kitchen's travel fee" : 'Delivery fee';
    final km = quote?.distanceKm;
    return km != null ? '$name (${numTextOf(km)} km)' : name;
  }

  String get feeValue {
    if (isPickup) return 'Free';
    if (quoteLoading) return 'Calculating…';
    if (unavailableReason != null) return 'Too far';
    final fee = deliveryFee;
    return fee == null ? 'Unavailable' : rwf(fee);
  }

  /// The scheduled instant sent with the order (null for "now").
  DateTime? get scheduledFor {
    if (orderType == 'scheduled') {
      return buildScheduledFor(scheduledDate, scheduledTime);
    }
    if (orderType == 'preorder' && preorder != null) {
      return parseIso(preorder!.deliveryAt);
    }
    return null;
  }

  Future<void> restore() async {
    final saved = await _readJson(_key);
    if (saved is Map && !session.isSignedIn) {
      lines = (saved['items'] is List ? saved['items'] as List : const [])
          .whereType<Map>()
          .map((e) => CartLine.fromJson(e.cast<String, dynamic>()))
          .where((l) => l.dishId.isNotEmpty)
          .toList();
      vendor = saved['vendor'] is Map && lines.isNotEmpty
          ? KitchenRef.fromJson(
              (saved['vendor'] as Map).cast<String, dynamic>(),
            )
          : null;
    }
    _onSession();
    _changed();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    location.removeListener(_onLocation);
    super.dispose();
  }

  void _changed() {
    _keepScheduleValid();
    _requote();
    if (!session.isSignedIn) {
      _writeJson(_key, {
        'vendor': vendor?.toJson(),
        'items': [for (final l in lines) l.toJson()],
      });
    }
    notifyListeners();
  }

  void _onLocation() => _requote();

  /// Signing in moves the guest basket into the account (when the account's
  /// is empty); signing out empties the basket on screen.
  Future<void> _onSession() async {
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (_syncedToken != null) {
        lines = [];
        vendor = null;
        _syncedToken = null;
        _changed();
      }
      return;
    }
    if (_syncedToken == token) return;
    _syncedToken = token;
    final guest = [...lines];
    syncing = true;
    notifyListeners();
    try {
      var payload = await api.cart();
      final remote = payload['items'];
      if ((remote is! List || remote.isEmpty) && guest.isNotEmpty) {
        payload = await api.replaceCart([
          for (final l in guest)
            {'menu_item_id': l.dishId, 'quantity': l.quantity},
        ]);
      }
      // Signed out (or another account signed in) while this was loading.
      if (session.token != token) return;
      _apply(payload);
      _storage.delete(key: _key).ignore();
    } catch (e) {
      error = e.toString();
    } finally {
      syncing = false;
      _changed();
    }
  }

  void _apply(Json payload) {
    final v = payload['vendor'];
    if (v is Map) {
      final raw = v.cast<String, dynamic>();
      vendor = KitchenRef(
        id: '${raw['id'] ?? ''}',
        name: '${raw['name'] ?? 'Kitchen'}',
        typeCode: KitchenRef.fromJson(raw).typeCode,
        neighborhood: vendor?.id == '${raw['id']}' ? vendor!.neighborhood : '',
        ordering: OrderingRules.from(raw['ordering'], raw['vendor_type']),
      );
    } else {
      vendor = null;
    }
    final items = payload['items'];
    lines = items is List
        ? items
              .whereType<Map>()
              .map(
                (e) => CartLine.fromApi(
                  e.cast<String, dynamic>(),
                  vendor?.name ?? '',
                ),
              )
              .toList()
        : [];
    if (lines.isEmpty) vendor = null;
  }

  /// Sends one change to the account basket; the server's basket replaces the
  /// one on screen once nothing else is waiting, and a failure brings it back.
  void _sync(Future<Json> Function() request) {
    if (!session.isSignedIn) return;
    if (_queue.pending == 0) _syncFailed = false;
    error = null;
    _queue
        .run<Json>(
          request,
          onError: (e) {
            _syncFailed = true;
            error = e.toString();
            onError?.call(error!);
          },
        )
        .then((payload) async {
          payload ??= await api.cart().catchError((_) => <String, dynamic>{});
          if (_queue.pending == 0 && payload.isNotEmpty) {
            _apply(payload);
            _changed();
          }
        });
  }

  /// Checkout waits for the basket to reach the account. False when a change failed.
  Future<bool> waitForSync() async {
    if (_queue.pending > 0) await _queue.idle;
    return !_syncFailed;
  }

  // Set by [add] when the dish is from another kitchen; the screen asks the
  // customer, then calls [replaceWith] or [cancelConflict].
  ({MenuDish dish, KitchenRef kitchen, int quantity})? conflict;

  AddResult add(MenuDish dish, KitchenRef kitchen, {int quantity = 1}) {
    final qty = quantity.clamp(1, maxQuantity);
    if (vendor != null && vendor!.id != kitchen.id && lines.isNotEmpty) {
      conflict = (dish: dish, kitchen: kitchen, quantity: qty);
      notifyListeners();
      return AddResult.conflict;
    }
    vendor ??= kitchen;
    // A pre-order only applies to its kitchen's dishes.
    if (orderType == 'preorder' && preorder?.vendorId != kitchen.id) {
      orderType = 'immediate';
      preorder = null;
    }
    final existing = lines.where((l) => l.dishId == dish.id).firstOrNull;
    if (existing != null) {
      existing.quantity = (existing.quantity + qty).clamp(1, maxQuantity);
    } else {
      lines = [
        ...lines,
        CartLine(
          dishId: dish.id,
          name: dish.name,
          price: dish.price,
          image: dish.image,
          quantity: qty,
          vendorId: kitchen.id,
          vendorName: kitchen.name,
          isAvailable: dish.isAvailable,
        ),
      ];
    }
    _sync(() => api.addToCart(dish.id, qty));
    _changed();
    return AddResult.added;
  }

  /// "Start new basket": empty it and add the waiting dish.
  void replaceWith() {
    final waiting = conflict;
    if (waiting == null) return;
    conflict = null;
    vendor = waiting.kitchen;
    if (orderType == 'preorder') {
      orderType = 'immediate';
      preorder = null;
    }
    final d = waiting.dish;
    lines = [
      CartLine(
        dishId: d.id,
        name: d.name,
        price: d.price,
        image: d.image,
        quantity: waiting.quantity,
        vendorId: waiting.kitchen.id,
        vendorName: waiting.kitchen.name,
        isAvailable: d.isAvailable,
      ),
    ];
    _sync(() async {
      await api.clearCart();
      return api.addToCart(d.id, waiting.quantity);
    });
    _changed();
  }

  void cancelConflict() {
    conflict = null;
    notifyListeners();
  }

  void setQuantity(String dishId, int quantity) {
    if (quantity <= 0) return remove(dishId);
    final line = lines.where((l) => l.dishId == dishId).firstOrNull;
    if (line == null) return;
    final qty = quantity.clamp(1, maxQuantity);
    line.quantity = qty;
    lines = [...lines];
    _sync(() => api.setCartQuantity(dishId, qty));
    _changed();
  }

  void remove(String dishId) {
    if (!lines.any((l) => l.dishId == dishId)) return;
    lines = lines.where((l) => l.dishId != dishId).toList();
    if (lines.isEmpty) vendor = null;
    _sync(() => api.removeFromCart(dishId));
    _changed();
  }

  void clear() {
    lines = [];
    vendor = null;
    _sync(api.clearCart);
    _changed();
  }

  /// After an order is placed (the server already emptied the account basket).
  void clearAfterCheckout() {
    lines = [];
    vendor = null;
    fulfillment = 'delivery';
    orderType = 'immediate';
    preorder = null;
    _changed();
  }

  void setOrderType(String value) {
    orderType = value;
    if (value != 'preorder') preorder = null;
    _changed();
  }

  void setFulfillment(String value) {
    fulfillment = value;
    _changed();
  }

  void setSchedule({String? day, String? time}) {
    if (day != null) scheduledDate = day;
    if (time != null) scheduledTime = time;
    _changed();
  }

  void startPreorder(PreorderSpecial special) {
    preorder = special;
    orderType = 'preorder';
    _changed();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Advance-only kitchens can't take "now" orders, and a picked day/time
  /// must stay inside the kitchen's window.
  void _keepScheduleValid() {
    final r = rules;
    if (r == null || lines.isEmpty) return;
    if (!r.orderNow && orderType == 'immediate') orderType = 'scheduled';
    if (orderType != 'scheduled') return;
    final d = days;
    if (d.isNotEmpty && !d.any((day) => day.value == scheduledDate)) {
      scheduledDate = d.first.value;
    }
    final s = slots;
    if (s.isNotEmpty && !s.contains(scheduledTime)) scheduledTime = s.first;
  }

  /// Re-prices delivery whenever the kitchen or the drop-off point changes.
  void _requote() {
    final v = vendor;
    if (v == null || lines.isEmpty) {
      _quoteKey = '';
      quote = null;
      return;
    }
    final key =
        '${v.id}|${location.lat.toStringAsFixed(5)}|${location.lng.toStringAsFixed(5)}';
    if (key == _quoteKey) return;
    _quoteKey = key;
    quoteLoading = true;
    quoteFailed = false;
    api
        .deliveryQuote(v.id, location.lat, location.lng)
        .then((result) {
          if (_quoteKey != key) return;
          quote = result;
        })
        .catchError((Object _) {
          if (_quoteKey != key) return;
          quote = null;
          quoteFailed = true;
        })
        .whenComplete(() {
          if (_quoteKey != key) return;
          quoteLoading = false;
          // Let the next basket or location change ask again after a failure.
          if (quoteFailed) _quoteKey = '';
          _keepScheduleValid();
          notifyListeners();
        });
  }
}

/// "2.4" / "3".
String numTextOf(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

// ---- Wishlist --------------------------------------------------------------

class SavedDish {
  SavedDish({required this.dish, required this.kitchen});

  final MenuDish dish;
  final KitchenRef kitchen;

  Json toJson() => {
    'dish': {
      'id': dish.id,
      'name': dish.name,
      'price_rwf': dish.price,
      'image_url': dish.image,
      'is_available': dish.isAvailable,
    },
    'vendor': kitchen.toJson(),
  };

  factory SavedDish.fromJson(Json raw) => SavedDish(
    dish: MenuDish.fromJson((raw['dish'] as Map).cast<String, dynamic>()),
    kitchen: KitchenRef.fromJson(
      (raw['vendor'] as Map).cast<String, dynamic>(),
    ),
  );

  /// One entry of GET /wishlist.
  factory SavedDish.fromApi(Json item) => SavedDish(
    dish: MenuDish.fromJson({
      'id': item['menu_item_id'],
      'name': item['name'],
      'price_rwf': item['price_rwf'],
      'image_url': item['image_url'],
      'is_available': item['is_available'],
    }),
    kitchen: KitchenRef(
      id: '${item['vendor_id'] ?? ''}',
      name: '${item['vendor_name'] ?? 'Kitchen'}',
      typeCode: KitchenRef.fromJson({'type': item['vendor_type']}).typeCode,
      neighborhood: '${item['vendor_neighborhood'] ?? ''}',
    ),
  );
}

/// Saved dishes (the website's WishlistContext): on the device for guests,
/// in the account once signed in.
class Wishlist extends ChangeNotifier {
  Wishlist(this.api, this.session) {
    session.addListener(_onSession);
  }

  static const _key = 'ofk_wishlist';

  final CustomerApi api;
  final CustomerSession session;
  final _queue = _Queue();
  List<SavedDish> items = [];
  String? error;
  String? _syncedToken;
  void Function(String message)? onError;

  bool contains(String dishId) => items.any((e) => e.dish.id == dishId);

  Future<void> restore() async {
    final saved = await _readJson(_key);
    if (saved is List && !session.isSignedIn) {
      items = saved
          .whereType<Map>()
          .map((e) {
            try {
              return SavedDish.fromJson(e.cast<String, dynamic>());
            } catch (_) {
              return null;
            }
          })
          .whereType<SavedDish>()
          .where((e) => e.dish.id.isNotEmpty && e.kitchen.id.isNotEmpty)
          .toList();
    }
    await _onSession();
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  void _persist() {
    if (!session.isSignedIn) {
      _writeJson(_key, [for (final e in items) e.toJson()]);
    }
  }

  static List<SavedDish> _fromPayload(Json payload) =>
      (payload['items'] is List ? payload['items'] as List : const [])
          .whereType<Map>()
          .map((e) => SavedDish.fromApi(e.cast<String, dynamic>()))
          .toList();

  Future<void> _onSession() async {
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (_syncedToken != null) {
        items = [];
        _syncedToken = null;
        notifyListeners();
      }
      return;
    }
    if (_syncedToken == token) return;
    _syncedToken = token;
    final guest = [...items];
    try {
      var payload = await api.wishlist();
      if (_fromPayload(payload).isEmpty && guest.isNotEmpty) {
        for (final entry in guest) {
          payload = await api.addToWishlist(entry.dish.id);
        }
      }
      if (session.token != token) return;
      items = _fromPayload(payload);
      error = null;
      _storage.delete(key: _key).ignore();
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void _sync(Future<Json> Function() request, VoidCallback undo) {
    if (!session.isSignedIn) return;
    _queue
        .run<Json>(
          request,
          onError: (e) {
            undo();
            error = e.toString();
            onError?.call(error!);
            notifyListeners();
          },
        )
        .then((payload) {
          if (payload != null && _queue.pending == 0) {
            items = _fromPayload(payload);
            notifyListeners();
          }
        });
  }

  void add(MenuDish dish, KitchenRef kitchen) {
    if (contains(dish.id)) return;
    final entry = SavedDish(dish: dish, kitchen: kitchen);
    items = [...items, entry];
    _persist();
    notifyListeners();
    _sync(
      () => api.addToWishlist(dish.id),
      () => items = items.where((e) => e != entry).toList(),
    );
  }

  void remove(String dishId) {
    final removed = items.where((e) => e.dish.id == dishId).firstOrNull;
    if (removed == null) return;
    items = items.where((e) => e.dish.id != dishId).toList();
    _persist();
    notifyListeners();
    _sync(() => api.removeFromWishlist(dishId), () {
      if (!contains(dishId)) items = [...items, removed];
    });
  }

  /// Saves or un-saves; returns true when it is now saved.
  bool toggle(MenuDish dish, KitchenRef kitchen) {
    if (contains(dish.id)) {
      remove(dish.id);
      return false;
    }
    add(dish, kitchen);
    return true;
  }
}

// ---- Orders ----------------------------------------------------------------

/// The signed-in customer's orders (the website's OrderContext), refreshed
/// every 10 seconds while the app is signed in so statuses follow the
/// kitchen and the delivery worker live.
class Orders extends ChangeNotifier {
  Orders(this.api, this.session) {
    session.addListener(_onSession);
    _onSession();
  }

  final CustomerApi api;
  final CustomerSession session;
  List<CustomerOrder> orders = [];
  String? error;
  bool loaded = false;
  Timer? _timer;
  String? _token;

  CustomerOrder? byId(String id) => orders.where((o) => o.id == id).firstOrNull;

  /// The customer's latest order with this kitchen (it unlocks messaging and calling it).
  CustomerOrder? withKitchen(String vendorId) =>
      orders.where((o) => o.vendorId == vendorId).firstOrNull;

  void _onSession() {
    if (session.token == _token) return;
    _token = session.token;
    _timer?.cancel();
    orders = [];
    loaded = false;
    error = null;
    if (session.isSignedIn) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!session.isSignedIn) return;
    final token = session.token;
    try {
      final fresh = await api.orders();
      // Signed out (or another account signed in) while this was loading.
      if (session.token != token) return;
      orders = fresh;
      error = null;
    } catch (e) {
      if (session.token != token) return;
      error = e.toString();
    }
    loaded = true;
    notifyListeners();
  }

  /// GET /orders/{id}, merged into the list.
  Future<CustomerOrder?> refreshOne(String id) async {
    try {
      final order = await api.order(id);
      _put(order);
      error = null;
      return order;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  void _put(CustomerOrder order) {
    orders = [order, ...orders.where((o) => o.id != order.id)];
    notifyListeners();
  }

  void put(CustomerOrder order) => _put(order);

  @override
  void dispose() {
    _timer?.cancel();
    session.removeListener(_onSession);
    super.dispose();
  }
}

// ---- Notifications ---------------------------------------------------------

class Notifications extends ChangeNotifier {
  Notifications(this.api, this.session) {
    session.addListener(_onSession);
    _onSession();
  }

  final CustomerApi api;
  final CustomerSession session;
  List<Json> items = [];
  int unread = 0;
  Timer? _timer;
  String? _token;

  void _onSession() {
    if (session.token == _token) return;
    _token = session.token;
    _timer?.cancel();
    items = [];
    unread = 0;
    if (session.isSignedIn) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!session.isSignedIn) return;
    final token = session.token;
    try {
      final data = await api.notifications();
      // Signed out (or another account signed in) while this was loading.
      if (session.token != token) return;
      items =
          (data['notifications'] is List
                  ? data['notifications'] as List
                  : const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
      unread =
          (data['unread_count'] as num?)?.toInt() ??
          items.where((n) => n['read'] != true).length;
      notifyListeners();
    } catch (_) {
      // Keep the last list; the next tick tries again.
    }
  }

  void markRead(String id) {
    final index = items.indexWhere((n) => '${n['id']}' == id);
    if (index < 0 || items[index]['read'] == true) return;
    items[index] = {...items[index], 'read': true};
    unread = (unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    api.markNotificationRead(id).ignore();
  }

  void markAllRead() {
    items = [
      for (final n in items) {...n, 'read': true},
    ];
    unread = 0;
    notifyListeners();
    api.markAllNotificationsRead().ignore();
  }

  @override
  void dispose() {
    _timer?.cancel();
    session.removeListener(_onSession);
    super.dispose();
  }
}
