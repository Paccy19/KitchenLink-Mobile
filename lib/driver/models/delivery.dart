import '../../core/network/json.dart';

/// Delivery statuses (`config.delivery` on the backend). The worker moves a
/// delivery `assigned_to_driver → picked_up → out_for_delivery`, then the
/// customer's code completes it.
class DeliveryStatus {
  const DeliveryStatus._();

  static const pending = 'pending';
  static const readyForPickup = 'ready_for_pickup';
  static const assigned = 'assigned_to_driver';
  static const pickedUp = 'picked_up';
  static const outForDelivery = 'out_for_delivery';
  static const delivered = 'delivered';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const rejected = 'rejected';

  static bool isFinished(String status) =>
      status == delivered || status == completed || status == cancelled || status == rejected;
}

/// A place on the trip: the kitchen (pickup) or the customer (drop-off).
class TripPoint {
  const TripPoint({this.address = '', this.neighborhood = '', this.note = '', this.latitude, this.longitude});

  factory TripPoint.fromJson(Object? raw) {
    final json = asJson(raw);
    return TripPoint(
      address: str(json['address']),
      neighborhood: str(json['neighborhood']),
      note: str(json['note']),
      latitude: doubleOrNull(json['latitude']),
      longitude: doubleOrNull(json['longitude']),
    );
  }

  final String address;
  final String neighborhood;

  /// Directions the customer left (gate colour, floor…).
  final String note;
  final double? latitude;
  final double? longitude;

  bool get hasPosition => latitude != null && longitude != null;
}

class DeliveryParty {
  const DeliveryParty({this.id = '', required this.name, this.phone = ''});

  final String id;
  final String name;

  /// Empty until the worker accepts (customer) or when none is on file.
  final String phone;
}

class DeliveryItem {
  const DeliveryItem({required this.name, this.quantity = 1, this.priceRwf = 0, this.options = ''});

  factory DeliveryItem.fromJson(Json json) => DeliveryItem(
        name: str(json['name'], 'Item'),
        quantity: intOf(json['quantity'], 1),
        priceRwf: intOf(json['price_rwf']),
        options: [for (final option in asJsonList(json['options'])) str(option['name'])]
            .where((name) => name.isNotEmpty)
            .join(', '),
      );

  final String name;
  final int quantity;
  final int priceRwf;
  final String options;
}

/// The admin's pickup timing rules, shown before the worker accepts.
class PickupRules {
  const PickupRules({required this.warningMinutes, required this.chargeAfterMinutes, this.reassignAfterMinutes});

  static PickupRules? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = asJson(raw);
    return PickupRules(
      warningMinutes: intOf(json['warning_minutes']),
      chargeAfterMinutes: intOf(json['charge_after_minutes'], 15),
      reassignAfterMinutes: intOrNull(json['reassign_after_minutes']),
    );
  }

  final int warningMinutes;

  /// Minutes after the food is ready before the pickup counts as late.
  final int chargeAfterMinutes;

  /// Minutes after which the order goes to another worker (null = never).
  final int? reassignAfterMinutes;
}

class LatePickup {
  const LatePickup({this.minutesLate});

  static LatePickup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return LatePickup(minutesLate: intOrNull(asJson(raw)['minutes_late']));
  }

  final int? minutesLate;
}

class ProgressEntry {
  const ProgressEntry({required this.status, required this.label, this.at, this.note = ''});

  factory ProgressEntry.fromJson(Json json) => ProgressEntry(
        status: str(json['status']),
        label: str(json['label'], str(json['status'])),
        at: dateOrNull(json['at']),
        note: str(json['note']),
      );

  final String status;
  final String label;
  final DateTime? at;
  final String note;
}

/// One delivery: an offer on the board, the active trip, or a past one
/// (`serializeDelivery`).
class Delivery {
  const Delivery({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    this.allowedNextStatuses = const [],
    required this.vendor,
    required this.customer,
    this.pickup = const TripPoint(),
    this.dropoff = const TripPoint(),
    this.routeDistanceKm,
    this.distanceFromDriverKm,
    this.deliveryFeeRwf = 0,
    this.promisedEarningsRwf = 0,
    this.paidEarningsRwf,
    this.paymentMethod = '',
    this.otpRequired = true,
    this.devOtp,
    this.kitchenReady = true,
    this.expectedReadyAt,
    this.pickupDueAt,
    this.pickupReassignAt,
    this.pickupRules,
    this.latePickup,
    this.progressLabel,
    this.progress = const [],
    this.items = const [],
    this.assignedAt,
    this.pickedUpAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.createdAt,
  });

  factory Delivery.fromJson(Json json) {
    final vendor = asJson(json['vendor']);
    final customer = asJson(json['customer']);
    final progress = asJson(json['order_progress']);
    return Delivery(
      id: str(json['id']),
      orderId: str(json['order_id']),
      orderNumber: str(json['order_number'], str(json['id'])),
      status: str(json['status']),
      statusLabel: str(json['status_label'], str(json['status'])),
      allowedNextStatuses: stringList(json['allowed_next_statuses']),
      vendor: DeliveryParty(
        id: str(vendor['id']),
        name: str(vendor['name'], 'Kitchen'),
        phone: str(vendor['phone']),
      ),
      customer: DeliveryParty(
        id: str(customer['id']),
        name: str(customer['name'], 'Customer'),
        phone: str(customer['phone_number']),
      ),
      pickup: TripPoint.fromJson(json['pickup_location']),
      dropoff: TripPoint.fromJson(json['delivery_location']),
      routeDistanceKm: doubleOrNull(json['route_distance_km']),
      distanceFromDriverKm: doubleOrNull(json['distance_from_driver_km']),
      deliveryFeeRwf: intOf(json['delivery_fee_rwf']),
      promisedEarningsRwf: intOf(json['promised_earnings_rwf']),
      paidEarningsRwf: intOrNull(json['paid_earnings_rwf']),
      paymentMethod: str(json['payment_method']),
      otpRequired: boolOf(json['otp_required'], true),
      devOtp: strOrNull(json['dev_otp']),
      // Offered at placement: the kitchen may still be cooking.
      kitchenReady: json['kitchen_ready'] != false,
      expectedReadyAt: dateOrNull(json['expected_ready_at']),
      pickupDueAt: dateOrNull(json['pickup_due_at']),
      pickupReassignAt: dateOrNull(json['pickup_reassign_at']),
      pickupRules: PickupRules.fromJson(json['pickup_rules']),
      latePickup: LatePickup.fromJson(json['late_pickup']),
      progressLabel: strOrNull(progress['label']),
      progress: [for (final entry in asJsonList(progress['history'])) ProgressEntry.fromJson(entry)],
      items: [for (final item in asJsonList(json['items'])) DeliveryItem.fromJson(item)],
      assignedAt: dateOrNull(json['assigned_at']),
      pickedUpAt: dateOrNull(json['picked_up_at']),
      completedAt: dateOrNull(json['completed_at']) ?? dateOrNull(json['delivered_at']),
      cancelledAt: dateOrNull(json['cancelled_at']),
      cancelReason: strOrNull(json['cancel_reason']),
      createdAt: dateOrNull(json['created_at']),
    );
  }

  final String id;
  final String orderId;
  final String orderNumber;
  final String status;
  final String statusLabel;

  /// What the server allows next. The app never offers anything else.
  final List<String> allowedNextStatuses;
  final DeliveryParty vendor;
  final DeliveryParty customer;
  final TripPoint pickup;
  final TripPoint dropoff;

  /// Kitchen → customer, by road.
  final double? routeDistanceKm;

  /// Worker → kitchen (offers only).
  final double? distanceFromDriverKm;
  final int deliveryFeeRwf;
  final int promisedEarningsRwf;

  /// What was actually paid (completed deliveries).
  final int? paidEarningsRwf;
  final String paymentMethod;
  final bool otpRequired;

  /// The customer's code, only on a development server.
  final String? devOtp;
  final bool kitchenReady;
  final DateTime? expectedReadyAt;
  final DateTime? pickupDueAt;
  final DateTime? pickupReassignAt;
  final PickupRules? pickupRules;
  final LatePickup? latePickup;
  final String? progressLabel;
  final List<ProgressEntry> progress;
  final List<DeliveryItem> items;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime? createdAt;

  int get earningsRwf => paidEarningsRwf ?? promisedEarningsRwf;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  bool get isFinished => DeliveryStatus.isFinished(status);
  bool get wasCancelled => status == DeliveryStatus.cancelled || status == DeliveryStatus.rejected;

  /// Assigned but the food is still cooking: the worker waits near the kitchen.
  bool get waitingForKitchen => status == DeliveryStatus.assigned && !kitchenReady;

  /// The one thing the worker does next on this trip, or null when nothing.
  TripAction? get nextAction => TripAction.forDelivery(this);
}

/// The worker's next move on an active trip. Mirrors the website's
/// `CONTEXT_ACTIONS`, but each move is only offered when the server lists it
/// in `allowed_next_statuses`.
class TripAction {
  const TripAction._({
    required this.kind,
    required this.toStatus,
    required this.title,
    required this.hint,
    required this.slideLabel,
  });

  final TripActionKind kind;

  /// The status sent to `PATCH /status` (null: the code sheet completes it).
  final String? toStatus;
  final String title;
  final String hint;
  final String slideLabel;

  static const _pickUp = TripAction._(
    kind: TripActionKind.confirmPickup,
    toStatus: DeliveryStatus.pickedUp,
    title: 'Collect the order',
    hint: 'Check every item against the list, then confirm you have it.',
    slideLabel: 'Slide to confirm pickup',
  );
  static const _start = TripAction._(
    kind: TripActionKind.startDelivery,
    toStatus: DeliveryStatus.outForDelivery,
    title: 'Head to the customer',
    hint: 'Leave the kitchen. The customer can follow you on their map.',
    slideLabel: 'Slide to start the delivery',
  );
  static const _handOver = TripAction._(
    kind: TripActionKind.handOver,
    toStatus: null,
    title: 'Hand over the order',
    hint: 'Ask the customer for their 6-digit delivery code.',
    slideLabel: 'Slide to enter the delivery code',
  );

  static TripAction? forDelivery(Delivery delivery) {
    switch (delivery.status) {
      case DeliveryStatus.assigned:
        return delivery.allowedNextStatuses.contains(DeliveryStatus.pickedUp) ? _pickUp : null;
      case DeliveryStatus.pickedUp:
        return delivery.allowedNextStatuses.contains(DeliveryStatus.outForDelivery) ? _start : null;
      case DeliveryStatus.outForDelivery:
        return _handOver;
    }
    return null;
  }
}

enum TripActionKind { confirmPickup, startDelivery, handOver }

/// The four steps the worker sees on the trip screen.
enum TripStage {
  toKitchen('To kitchen'),
  collected('Collected'),
  onTheWay('On the way'),
  delivered('Delivered');

  const TripStage(this.label);
  final String label;

  static TripStage of(String status) {
    switch (status) {
      case DeliveryStatus.pickedUp:
        return collected;
      case DeliveryStatus.outForDelivery:
        return onTheWay;
      case DeliveryStatus.delivered:
      case DeliveryStatus.completed:
        return delivered;
    }
    return toKitchen;
  }
}

/// `POST /driver/deliveries/:id/confirm-delivery`.
class DeliveryCompletion {
  const DeliveryCompletion({required this.delivery, required this.earnedRwf, this.penaltyRwf = 0});

  factory DeliveryCompletion.fromJson(Json json) => DeliveryCompletion(
        delivery: Delivery.fromJson(asJson(json['delivery'])),
        earnedRwf: intOf(json['earned_rwf']),
        penaltyRwf: intOf(json['penalty_rwf']),
      );

  final Delivery delivery;
  final int earnedRwf;
  final int penaltyRwf;
}

/// A page of past deliveries.
class DeliveryPage {
  const DeliveryPage({required this.deliveries, required this.meta});

  factory DeliveryPage.fromJson(Object? payload) => DeliveryPage(
        deliveries: [for (final item in unwrapList(payload, const ['deliveries', 'items'])) Delivery.fromJson(item)],
        meta: PageMeta.fromJson(asJson(payload)['meta']),
      );

  final List<Delivery> deliveries;
  final PageMeta meta;
}

/// `GET /driver/deliveries/earnings`.
class DriverEarnings {
  const DriverEarnings({
    this.todayRwf = 0,
    this.todayDeliveries = 0,
    this.totalRwf = 0,
    this.totalDeliveries = 0,
    this.sharePercent = 100,
    this.rating = 5,
    this.deliveries = const [],
  });

  factory DriverEarnings.fromJson(Json json) => DriverEarnings(
        todayRwf: intOf(json['today_rwf']),
        todayDeliveries: intOf(json['today_deliveries']),
        totalRwf: intOf(json['total_rwf']),
        totalDeliveries: intOf(json['total_deliveries']),
        sharePercent: doubleOrNull(json['share_percent']) ?? 100,
        rating: doubleOrNull(json['rating']) ?? 5,
        deliveries: [for (final item in asJsonList(json['deliveries'])) Delivery.fromJson(item)],
      );

  final int todayRwf;
  final int todayDeliveries;
  final int totalRwf;
  final int totalDeliveries;

  /// Share of each delivery fee the worker keeps.
  final double sharePercent;
  final double rating;
  final List<Delivery> deliveries;
}
