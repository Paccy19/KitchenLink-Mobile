import '../../../core/network/json.dart';

/// The admin's verification decision about a kitchen.
enum VerificationStatus {
  pending,
  approved,
  rejected,
  suspended;

  static VerificationStatus parse(Object? value) {
    switch (str(value).toLowerCase()) {
      case 'approved':
        return approved;
      case 'rejected':
        return rejected;
      case 'suspended':
        return suspended;
      default:
        return pending;
    }
  }

  String get label => switch (this) {
        pending => 'Under review',
        approved => 'Approved',
        rejected => 'Rejected',
        suspended => 'Suspended',
      };
}

const List<String> weekDays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

class OperatingHour {
  const OperatingHour({
    required this.day,
    this.openTime = '08:00',
    this.closeTime = '21:00',
    this.isClosed = false,
  });

  factory OperatingHour.fromJson(Json json) => OperatingHour(
        day: str(json['day']).toLowerCase(),
        openTime: str(json['open_time']),
        closeTime: str(json['close_time']),
        isClosed: boolOf(json['is_closed']),
      );

  final String day;
  final String openTime;
  final String closeTime;
  final bool isClosed;

  OperatingHour copyWith({String? openTime, String? closeTime, bool? isClosed}) => OperatingHour(
        day: day,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        isClosed: isClosed ?? this.isClosed,
      );

  Json toJson() => {
        'day': day,
        'open_time': isClosed ? '' : openTime,
        'close_time': isClosed ? '' : closeTime,
        'is_closed': isClosed,
      };

  /// A full week, every day open 08:00–21:00.
  static List<OperatingHour> defaultWeek() => [for (final day in weekDays) OperatingHour(day: day)];

  /// [hours] ordered Monday→Sunday, adding any missing day as open.
  static List<OperatingHour> completeWeek(List<OperatingHour> hours) => [
        for (final day in weekDays)
          hours.firstWhere((entry) => entry.day == day, orElse: () => OperatingHour(day: day)),
      ];
}

class PaymentInformation {
  const PaymentInformation({
    this.payoutMethod = '',
    this.accountName = '',
    this.accountNumber = '',
    this.bankName = '',
    this.mobileMoneyNumber = '',
  });

  factory PaymentInformation.fromJson(Json json) => PaymentInformation(
        payoutMethod: str(json['payout_method']),
        accountName: str(json['account_name']),
        accountNumber: str(json['account_number']),
        bankName: str(json['bank_name']),
        mobileMoneyNumber: str(json['mobile_money_number']),
      );

  final String payoutMethod;
  final String accountName;
  final String accountNumber;
  final String bankName;
  final String mobileMoneyNumber;

  bool get isBank => payoutMethod == 'bank_transfer';

  Json toJson() => {
        'payout_method': payoutMethod,
        'account_name': accountName,
        if (accountNumber.isNotEmpty) 'account_number': accountNumber,
        if (bankName.isNotEmpty) 'bank_name': bankName,
        if (mobileMoneyNumber.isNotEmpty) 'mobile_money_number': mobileMoneyNumber,
      };
}

class VendorLocation {
  const VendorLocation({
    this.neighborhood = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.updatedAt,
  });

  factory VendorLocation.fromJson(Json json) => VendorLocation(
        neighborhood: str(json['neighborhood']),
        address: str(json['address']),
        latitude: doubleOrNull(json['latitude']),
        longitude: doubleOrNull(json['longitude']),
        updatedAt: dateOrNull(json['updated_at']),
      );

  final String neighborhood;
  final String address;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get summary => [address, neighborhood].where((part) => part.isNotEmpty).join(', ');
}

class VendorTypeRequest {
  const VendorTypeRequest({
    required this.vendorType,
    required this.label,
    this.reason = '',
    this.requestedAt,
  });

  factory VendorTypeRequest.fromJson(Json json) => VendorTypeRequest(
        vendorType: str(json['vendor_type']),
        label: str(json['vendor_type_label']),
        reason: str(json['reason']),
        requestedAt: dateOrNull(json['requested_at']),
      );

  final String vendorType;
  final String label;
  final String reason;
  final DateTime? requestedAt;
}

class VerificationDocument {
  const VerificationDocument({required this.label, required this.fileType, this.uploadedAt});

  factory VerificationDocument.fromJson(Json json) => VerificationDocument(
        label: str(json['label']),
        fileType: str(json['file_type'], 'other'),
        uploadedAt: dateOrNull(json['uploaded_at']),
      );

  final String label;

  /// `image`, `pdf` or `other`.
  final String fileType;
  final DateTime? uploadedAt;
}

/// How this kitchen's type takes orders (`ordering` in the vendor payloads).
class OrderingRules {
  const OrderingRules({
    required this.vendorType,
    this.vendorTypeLabel = '',
    this.orderNow = true,
    this.minLeadMinutes = 0,
    this.maxDaysAhead = 0,
    this.dailyOrderLimit,
    this.minOrderRwf = 0,
    this.maxItemsPerOrder,
    this.limitRange,
    this.minOrderRange = const [0, 0],
    this.ordersToday,
    this.fullyBookedToday = false,
  });

  factory OrderingRules.fromJson(Json json) {
    List<int>? range(Object? value) =>
        value is List && value.length == 2 ? [intOf(value[0]), intOf(value[1])] : null;
    return OrderingRules(
      vendorType: str(json['vendor_type']),
      vendorTypeLabel: str(json['vendor_type_label']),
      orderNow: boolOf(json['order_now'], true),
      minLeadMinutes: intOf(json['min_lead_minutes']),
      maxDaysAhead: intOf(json['max_days_ahead']),
      dailyOrderLimit: intOrNull(json['daily_order_limit']),
      minOrderRwf: intOf(json['min_order_rwf']),
      maxItemsPerOrder: intOrNull(json['max_items_per_order']),
      limitRange: range(json['limit_range']),
      minOrderRange: range(json['min_order_range']) ?? const [0, 0],
      ordersToday: intOrNull(json['orders_today']),
      fullyBookedToday: boolOf(json['fully_booked_today']),
    );
  }

  final String vendorType;
  final String vendorTypeLabel;

  /// Can customers order for right now? Caterers, chefs and meal-prep work ahead.
  final bool orderNow;
  final int minLeadMinutes;
  final int maxDaysAhead;

  /// Null = this kitchen type has no daily limit.
  final int? dailyOrderLimit;
  final int minOrderRwf;
  final int? maxItemsPerOrder;

  /// `[min, max]` the kitchen may set its daily limit within; null = not adjustable.
  final List<int>? limitRange;
  final List<int> minOrderRange;
  final int? ordersToday;
  final bool fullyBookedToday;

  bool get hasDailyLimit => limitRange != null;

  /// `45 minutes`, `4 hours`, `1 day`.
  String get leadTimeLabel {
    final minutes = minLeadMinutes;
    if (minutes >= 1440 && minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return '$days day${days == 1 ? '' : 's'}';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return '$hours hour${hours == 1 ? '' : 's'}';
    }
    return '$minutes minutes';
  }
}

class NationwideInfo {
  const NationwideInfo({
    this.enabled = false,
    this.source = 'type',
    this.byType = false,
    this.travelBaseFeeRwf = 0,
    this.travelPerKmRwf = 0,
    this.platformDeliveryMaxKm,
    this.baseFeeRange = const [0, 0],
    this.perKmRange = const [0, 0],
  });

  factory NationwideInfo.fromJson(Json json) {
    final ranges = asJson(json['ranges']);
    List<int> range(Object? value) =>
        value is List && value.length == 2 ? [intOf(value[0]), intOf(value[1])] : const [0, 0];
    return NationwideInfo(
      enabled: boolOf(json['enabled']),
      source: str(json['source'], 'type'),
      byType: boolOf(json['by_type']),
      travelBaseFeeRwf: intOf(json['travel_base_fee_rwf']),
      travelPerKmRwf: intOf(json['travel_per_km_rwf']),
      platformDeliveryMaxKm: doubleOrNull(json['platform_delivery_max_km']),
      baseFeeRange: range(ranges['base_fee_rwf']),
      perKmRange: range(ranges['per_km_rwf']),
    );
  }

  final bool enabled;

  /// `type` (default for the kitchen type) or `admin` (switched by an admin).
  final String source;
  final bool byType;
  final int travelBaseFeeRwf;
  final int travelPerKmRwf;
  final double? platformDeliveryMaxKm;
  final List<int> baseFeeRange;
  final List<int> perKmRange;
}

/// The signed-in kitchen (`GET /vendor/auth/me` → `vendor`).
class VendorAccount {
  const VendorAccount({
    required this.id,
    required this.name,
    required this.vendorType,
    required this.vendorTypeLabel,
    required this.verificationStatus,
    this.typeRequest,
    this.ordering,
    this.nationwide = const NationwideInfo(),
    this.ownerName = '',
    this.description = '',
    this.email,
    this.phone = '',
    this.rating = 0,
    this.isActive = false,
    this.isOpen = false,
    this.bannerImageUrl,
    this.profileImageUrl,
    this.foodCategoryIds = const [],
    this.foodCategories = const [],
    this.operatingHours = const [],
    this.paymentInformation = const PaymentInformation(),
    this.documents = const [],
    this.availableBalanceRwf = 0,
    this.totalSalesRwf = 0,
    this.commissionPercent = 0,
    this.location = const VendorLocation(),
    this.createdAt,
  });

  factory VendorAccount.fromJson(Json json) => VendorAccount(
        id: str(json['id']),
        name: str(json['name'], 'Your kitchen'),
        vendorType: str(json['vendor_type']),
        vendorTypeLabel: str(json['vendor_type_label']),
        verificationStatus: VerificationStatus.parse(json['verification_status']),
        typeRequest: json['vendor_type_request'] is Map
            ? VendorTypeRequest.fromJson(asJson(json['vendor_type_request']))
            : null,
        ordering: json['ordering'] is Map ? OrderingRules.fromJson(asJson(json['ordering'])) : null,
        nationwide: NationwideInfo.fromJson(asJson(json['nationwide'])),
        ownerName: str(json['owner_name']),
        description: str(json['description']),
        email: strOrNull(json['email']),
        phone: str(json['phone']),
        rating: doubleOrNull(json['rating']) ?? 0,
        isActive: boolOf(json['is_active']),
        isOpen: boolOf(json['is_open'], true),
        bannerImageUrl: strOrNull(json['banner_image_url']),
        profileImageUrl: strOrNull(json['profile_image_url']),
        foodCategoryIds: stringList(json['food_category_ids']),
        foodCategories: stringList(json['food_categories']),
        operatingHours: [for (final entry in asJsonList(json['operating_hours'])) OperatingHour.fromJson(entry)],
        paymentInformation: PaymentInformation.fromJson(asJson(json['payment_information'])),
        documents: [for (final doc in asJsonList(json['verification_documents'])) VerificationDocument.fromJson(doc)],
        availableBalanceRwf: intOf(json['available_balance_rwf']),
        totalSalesRwf: intOf(json['total_sales_rwf']),
        commissionPercent: doubleOrNull(json['commission_percent']) ?? 0,
        location: VendorLocation.fromJson(asJson(json['location'])),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;
  final String name;
  final String vendorType;
  final String vendorTypeLabel;
  final VerificationStatus verificationStatus;
  final VendorTypeRequest? typeRequest;
  final OrderingRules? ordering;
  final NationwideInfo nationwide;
  final String ownerName;
  final String description;
  final String? email;
  final String phone;
  final double rating;
  final bool isActive;
  final bool isOpen;
  final String? bannerImageUrl;
  final String? profileImageUrl;
  final List<String> foodCategoryIds;
  final List<String> foodCategories;
  final List<OperatingHour> operatingHours;
  final PaymentInformation paymentInformation;
  final List<VerificationDocument> documents;
  final int availableBalanceRwf;
  final int totalSalesRwf;
  final double commissionPercent;
  final VendorLocation location;
  final DateTime? createdAt;

  bool get isApproved => verificationStatus == VerificationStatus.approved;
  bool get isPending => verificationStatus == VerificationStatus.pending;

  /// Image shown for the kitchen: profile photo first, then the banner.
  String? get avatarUrl => profileImageUrl ?? bannerImageUrl;
}

/// Why an account cannot be used: the backend's reason and support contacts
/// (details of `VENDOR_SUSPENDED` / `VENDOR_REJECTED`).
class AccountBlock {
  const AccountBlock({
    required this.status,
    this.message = '',
    this.reason = '',
    this.supportPhone = '',
    this.supportEmail = '',
    this.suspendedAt,
  });

  factory AccountBlock.fromError({required String code, required String message, required Json details}) =>
      AccountBlock(
        status: code == 'VENDOR_SUSPENDED' || str(details['status']) == 'suspended'
            ? VerificationStatus.suspended
            : VerificationStatus.rejected,
        message: message,
        reason: str(details['reason']),
        supportPhone: str(details['support_phone']),
        supportEmail: str(details['support_email']),
        suspendedAt: dateOrNull(details['suspended_at']),
      );

  final VerificationStatus status;
  final String message;
  final String reason;
  final String supportPhone;
  final String supportEmail;
  final DateTime? suspendedAt;

  bool get isSuspended => status == VerificationStatus.suspended;
}
