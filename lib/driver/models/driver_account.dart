import '../../core/network/json.dart';

/// Ways a delivery worker can travel (`models/Driver.js` VEHICLE_TYPES).
enum VehicleType {
  motorcycle('motorcycle', 'Motorcycle'),
  scooter('scooter', 'Scooter'),
  bicycle('bicycle', 'Bicycle'),
  car('car', 'Car'),
  foot('foot', 'On foot');

  const VehicleType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Motorised vehicles carry a plate number.
  bool get hasPlate => this == motorcycle || this == scooter || this == car;

  static VehicleType? parse(String? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

/// The signed-in delivery worker (`serializeDriverAccount`).
class DriverAccount {
  const DriverAccount({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.vehicleTypeRaw = 'motorcycle',
    this.plateNumber = '',
    this.rating = 5,
    this.ratingCount = 0,
    this.isOnline = false,
    this.status = 'offline',
    this.activeDeliveries = 0,
    this.maxActiveDeliveries = 3,
    this.completedDeliveries = 0,
    this.totalEarningsRwf = 0,
    this.availableBalanceRwf = 0,
    this.profileImageUrl,
    this.verificationStatus = 'approved',
    this.latitude,
    this.longitude,
    this.locationUpdatedAt,
  });

  factory DriverAccount.fromJson(Json json) {
    final location = asJson(json['current_location']);
    return DriverAccount(
      id: str(json['id']),
      name: str(json['name']),
      phone: str(json['phone']),
      email: strOrNull(json['email']),
      vehicleTypeRaw: str(json['vehicle_type'], 'motorcycle'),
      plateNumber: str(json['plate_number']),
      rating: doubleOrNull(json['rating']) ?? 5,
      ratingCount: intOf(json['rating_count']),
      isOnline: boolOf(json['is_online']),
      status: str(json['status'], 'offline'),
      activeDeliveries: intOf(json['active_deliveries_count']),
      maxActiveDeliveries: intOf(json['max_active_deliveries'], 3),
      completedDeliveries: intOf(json['completed_deliveries']),
      totalEarningsRwf: intOf(json['total_earnings_rwf']),
      availableBalanceRwf: intOf(json['available_balance_rwf']),
      profileImageUrl: strOrNull(json['profile_image_url']),
      verificationStatus: str(json['verification_status'], 'approved'),
      latitude: doubleOrNull(location['latitude']),
      longitude: doubleOrNull(location['longitude']),
      locationUpdatedAt: dateOrNull(location['updated_at']),
    );
  }

  final String id;
  final String name;
  final String phone;
  final String? email;
  final String vehicleTypeRaw;
  final String plateNumber;
  final double rating;
  final int ratingCount;
  final bool isOnline;

  /// `offline`, `online` or `busy`.
  final String status;
  final int activeDeliveries;
  final int maxActiveDeliveries;
  final int completedDeliveries;
  final int totalEarningsRwf;
  final int availableBalanceRwf;
  final String? profileImageUrl;
  final String verificationStatus;
  final double? latitude;
  final double? longitude;

  /// When the server last received this worker's position (null = never).
  final DateTime? locationUpdatedAt;

  VehicleType? get vehicleType => VehicleType.parse(vehicleTypeRaw);

  String get vehicleLabel {
    final label = vehicleType?.label ?? vehicleTypeRaw;
    return plateNumber.isEmpty ? label : '$label · $plateNumber';
  }

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }

  DriverAccount copyWith({bool? isOnline, String? status, int? activeDeliveries}) => DriverAccount(
        id: id,
        name: name,
        phone: phone,
        email: email,
        vehicleTypeRaw: vehicleTypeRaw,
        plateNumber: plateNumber,
        rating: rating,
        ratingCount: ratingCount,
        isOnline: isOnline ?? this.isOnline,
        status: status ?? this.status,
        activeDeliveries: activeDeliveries ?? this.activeDeliveries,
        maxActiveDeliveries: maxActiveDeliveries,
        completedDeliveries: completedDeliveries,
        totalEarningsRwf: totalEarningsRwf,
        availableBalanceRwf: availableBalanceRwf,
        profileImageUrl: profileImageUrl,
        verificationStatus: verificationStatus,
        latitude: latitude,
        longitude: longitude,
        locationUpdatedAt: locationUpdatedAt,
      );
}

/// `POST /driver/auth/send-otp`.
class DriverOtpChallenge {
  const DriverOtpChallenge({required this.phone, this.expiresInSeconds = 300, this.devOtp});

  factory DriverOtpChallenge.fromJson(Json json) => DriverOtpChallenge(
        phone: str(json['phone_number']),
        expiresInSeconds: intOf(json['expires_in_seconds'], 300),
        devOtp: strOrNull(json['dev_otp']),
      );

  final String phone;
  final int expiresInSeconds;

  /// Only on a development server.
  final String? devOtp;
}

/// `GET /driver/stats`: the numbers on the home screen.
class DriverStats {
  const DriverStats({
    this.activeDeliveries = 0,
    this.completedToday = 0,
    this.earningsTodayRwf = 0,
    this.completedTotal = 0,
    this.earningsTotalRwf = 0,
    this.rating = 5,
    this.isOnline = false,
    this.status = 'offline',
  });

  factory DriverStats.fromJson(Json json) => DriverStats(
        activeDeliveries: intOf(json['active_deliveries']),
        completedToday: intOf(json['completed_today']),
        earningsTodayRwf: intOf(json['earnings_today_rwf']),
        completedTotal: intOf(json['completed_total']),
        earningsTotalRwf: intOf(json['earnings_total_rwf']),
        rating: doubleOrNull(json['rating']) ?? 5,
        isOnline: boolOf(json['is_online']),
        status: str(json['status'], 'offline'),
      );

  final int activeDeliveries;
  final int completedToday;
  final int earningsTodayRwf;
  final int completedTotal;
  final int earningsTotalRwf;
  final double rating;
  final bool isOnline;
  final String status;
}

/// The worker's registration form (`POST /driver/auth/register`).
class DriverRegistration {
  const DriverRegistration({
    required this.name,
    required this.phone,
    required this.vehicleType,
    this.plateNumber = '',
    this.email,
  });

  final String name;
  final String phone;
  final VehicleType vehicleType;
  final String plateNumber;
  final String? email;

  Json toJson() => {
        'name': name.trim(),
        'phone': phone,
        'vehicle_type': vehicleType.apiValue,
        'plate_number': vehicleType.hasPlate ? plateNumber.trim().toUpperCase() : '',
        if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
      };
}
