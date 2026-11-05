import '../../../core/network/json.dart';

/// Kitchen-side order statuses (`config.vendor.orderStatuses`).
enum OrderStatus {
  newOrder('new', 'New'),
  accepted('accepted', 'Accepted'),
  preparing('preparing', 'Preparing'),
  ready('ready', 'Ready'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const OrderStatus(this.code, this.label);

  /// The value the API uses.
  final String code;
  final String label;

  static OrderStatus? tryParse(Object? value) {
    final text = str(value).toLowerCase();
    for (final status in OrderStatus.values) {
      if (status.code == text) return status;
    }
    return null;
  }

  bool get isFinal => this == completed || this == cancelled;
}

class OrderItemOption {
  const OrderItemOption({required this.groupName, required this.name, this.additionalPriceRwf = 0});

  factory OrderItemOption.fromJson(Json json) => OrderItemOption(
        groupName: str(json['group_name'], 'Options'),
        name: str(json['name']),
        additionalPriceRwf: intOf(json['additional_price_rwf']),
      );

  final String groupName;
  final String name;
  final int additionalPriceRwf;
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.priceRwf,
    required this.quantity,
    required this.subtotalRwf,
    this.imageUrl,
    this.options = const [],
  });

  factory OrderItem.fromJson(Json json) => OrderItem(
        name: str(json['name']),
        priceRwf: intOf(json['price_rwf']),
        quantity: intOf(json['quantity'], 1),
        subtotalRwf: intOf(json['subtotal_rwf'], intOf(json['price_rwf']) * intOf(json['quantity'], 1)),
        imageUrl: strOrNull(json['image_url']),
        options: [for (final option in asJsonList(json['options'])) OrderItemOption.fromJson(option)],
      );

  final String name;
  final int priceRwf;
  final int quantity;
  final int subtotalRwf;
  final String? imageUrl;
  final List<OrderItemOption> options;
}

class OrderCustomer {
  const OrderCustomer({required this.name, this.phone = ''});

  factory OrderCustomer.fromJson(Json json) =>
      OrderCustomer(name: str(json['name'], 'Customer'), phone: str(json['phone_number']));

  final String name;
  final String phone;
}

class DeliveryLocation {
  const DeliveryLocation({this.address = '', this.neighborhood = '', this.note = ''});

  factory DeliveryLocation.fromJson(Json json) => DeliveryLocation(
        address: str(json['address']),
        neighborhood: str(json['neighborhood']),
        note: str(json['note']),
      );

  final String address;
  final String neighborhood;
  final String note;

  String get summary => [address, neighborhood].where((part) => part.isNotEmpty).join(', ');
}

/// Big events paid in two parts: a deposit and a balance due a day before.
class OrderDeposit {
  const OrderDeposit({
    required this.depositRwf,
    required this.balanceRwf,
    this.balanceDueAt,
    this.balancePaidAt,
    this.balanceUnpaid = false,
  });

  factory OrderDeposit.fromJson(Json json) => OrderDeposit(
        depositRwf: intOf(json['deposit_rwf']),
        balanceRwf: intOf(json['balance_rwf']),
        balanceDueAt: dateOrNull(json['balance_due_at']),
        balancePaidAt: dateOrNull(json['balance_paid_at']),
        balanceUnpaid: boolOf(json['balance_unpaid']),
      );

  final int depositRwf;
  final int balanceRwf;
  final DateTime? balanceDueAt;
  final DateTime? balancePaidAt;

  /// While true the backend refuses to mark the order ready or hand it over.
  final bool balanceUnpaid;
}

class OrderEvent {
  const OrderEvent({
    required this.packageName,
    required this.guests,
    required this.pricePerPlateRwf,
    this.menu = const [],
    this.portion = '',
    this.serviceStyleLabel = '',
    this.serviceDetails = '',
    this.deliveryDetails = '',
  });

  factory OrderEvent.fromJson(Json json) => OrderEvent(
        packageName: str(json['package_name']),
        guests: intOf(json['guests']),
        pricePerPlateRwf: intOf(json['price_per_plate_rwf']),
        menu: stringList(json['menu']),
        portion: str(json['portion']),
        serviceStyleLabel: str(json['service_style_label']),
        serviceDetails: str(json['service_details']),
        deliveryDetails: str(json['delivery_details']),
      );

  final String packageName;
  final int guests;
  final int pricePerPlateRwf;
  final List<String> menu;
  final String portion;
  final String serviceStyleLabel;
  final String serviceDetails;
  final String deliveryDetails;
}

class StatusHistoryEntry {
  const StatusHistoryEntry({required this.label, this.at, this.note = ''});

  factory StatusHistoryEntry.fromJson(Json json) => StatusHistoryEntry(
        label: str(json['label'], str(json['status'])),
        at: dateOrNull(json['at']),
        note: str(json['note']),
      );

  final String label;
  final DateTime? at;
  final String note;
}

/// An order as the kitchen sees it (`serializeVendorOrder`).
class VendorOrder {
  const VendorOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.allowedNextStatuses,
    required this.fulfillment,
    required this.customer,
    required this.items,
    required this.subtotalRwf,
    required this.deliveryFeeRwf,
    required this.totalRwf,
    required this.paymentStatus,
    this.paymentMethod = '',
    this.readyAvailableAt,
    this.fulfillmentLabel = '',
    this.event,
    this.deposit,
    this.kitchenDelivers = false,
    this.canConfirmPickup = false,
    this.pickupAttemptsLeft,
    this.collectedAt,
    this.createdAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.deliveryDistanceKm,
    this.commissionPercent = 0,
    this.commissionRwf = 0,
    this.vendorPayoutRwf = 0,
    this.settlementStatus = '',
    this.orderType = 'immediate',
    this.orderTypeLabel = '',
    this.scheduledFor,
    this.specialText = '',
    this.deliveryLocation = const DeliveryLocation(),
    this.etaMinutes,
    this.history = const [],
  });

  factory VendorOrder.fromJson(Json json) {
    final rawStatus = str(json['status']);
    final status = OrderStatus.tryParse(rawStatus) ?? OrderStatus.newOrder;
    return VendorOrder(
      id: str(json['id']),
      orderNumber: str(json['order_number']),
      status: status,
      statusLabel: str(json['status_label'], status.label),
      // Only transitions this app knows; whatever else the server may add is ignored.
      allowedNextStatuses: [
        for (final value in (json['allowed_next_statuses'] is List ? json['allowed_next_statuses'] as List : const []))
          if (OrderStatus.tryParse(value) != null) OrderStatus.tryParse(value)!,
      ],
      readyAvailableAt: dateOrNull(json['ready_available_at']),
      fulfillment: str(json['fulfillment'], 'delivery'),
      fulfillmentLabel: str(json['fulfillment_label']),
      event: json['event'] is Map ? OrderEvent.fromJson(asJson(json['event'])) : null,
      deposit: json['deposit'] is Map ? OrderDeposit.fromJson(asJson(json['deposit'])) : null,
      kitchenDelivers: boolOf(json['kitchen_delivers']),
      canConfirmPickup: boolOf(json['can_confirm_pickup']),
      pickupAttemptsLeft: intOrNull(json['pickup_attempts_left']),
      collectedAt: dateOrNull(json['collected_at']),
      createdAt: dateOrNull(json['created_at']),
      completedAt: dateOrNull(json['completed_at']),
      cancelledAt: dateOrNull(json['cancelled_at']),
      cancelReason: strOrNull(json['cancel_reason']),
      customer: OrderCustomer.fromJson(asJson(json['customer'])),
      items: [for (final item in asJsonList(json['items'])) OrderItem.fromJson(item)],
      subtotalRwf: intOf(json['subtotal_rwf']),
      deliveryFeeRwf: intOf(json['delivery_fee_rwf']),
      deliveryDistanceKm: doubleOrNull(json['delivery_distance_km']),
      totalRwf: intOf(json['total_amount_rwf'], intOf(json['total_rwf'])),
      commissionPercent: doubleOrNull(json['commission_percent']) ?? 0,
      commissionRwf: intOf(json['commission_rwf']),
      vendorPayoutRwf: intOf(json['vendor_payout_rwf']),
      settlementStatus: str(json['settlement_status']),
      paymentMethod: str(json['payment_method']),
      paymentStatus: str(json['payment_status'], 'pending'),
      orderType: str(json['order_type'], 'immediate'),
      orderTypeLabel: str(json['order_type_label']),
      scheduledFor: dateOrNull(json['scheduled_for']),
      specialText: str(json['special_text']),
      deliveryLocation: DeliveryLocation.fromJson(asJson(json['delivery_location'])),
      etaMinutes: intOrNull(json['eta_minutes']),
      history: [for (final entry in asJsonList(json['status_history'])) StatusHistoryEntry.fromJson(entry)],
    );
  }

  final String id;
  final String orderNumber;
  final OrderStatus status;
  final String statusLabel;

  /// What the backend allows the kitchen to do next, right now.
  final List<OrderStatus> allowedNextStatuses;

  /// Set while a scheduled order cannot yet be marked ready.
  final DateTime? readyAvailableAt;

  /// `delivery`, `pickup` or `vendor_delivery`.
  final String fulfillment;
  final String fulfillmentLabel;
  final OrderEvent? event;
  final OrderDeposit? deposit;
  final bool kitchenDelivers;
  final bool canConfirmPickup;
  final int? pickupAttemptsLeft;
  final DateTime? collectedAt;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final OrderCustomer customer;
  final List<OrderItem> items;
  final int subtotalRwf;
  final int deliveryFeeRwf;
  final double? deliveryDistanceKm;
  final int totalRwf;
  final double commissionPercent;
  final int commissionRwf;
  final int vendorPayoutRwf;
  final String settlementStatus;
  final String paymentMethod;
  final String paymentStatus;
  final String orderType;
  final String orderTypeLabel;
  final DateTime? scheduledFor;
  final String specialText;
  final DeliveryLocation deliveryLocation;
  final int? etaMinutes;
  final List<StatusHistoryEntry> history;

  bool get isPickup => fulfillment == 'pickup';

  /// Orders the kitchen finishes itself with the customer's code. Every other
  /// order is completed by the delivery worker, never by the kitchen.
  bool get usesHandoverCode => fulfillment == 'pickup' || fulfillment == 'vendor_delivery';

  bool get isPaid => paymentStatus == 'paid';
  bool get isScheduled => orderType != 'immediate';
  bool get isEvent => event != null;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// True while the customer still has to pay before the kitchen can act.
  bool get awaitingPayment => !status.isFinal && !isPaid;
}
