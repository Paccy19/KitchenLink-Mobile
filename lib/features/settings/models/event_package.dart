import '../../../core/network/json.dart';

class ServiceStyle {
  const ServiceStyle({required this.code, required this.label});

  factory ServiceStyle.fromJson(Json json) =>
      ServiceStyle(code: str(json['code']), label: str(json['label']));

  final String code;
  final String label;
}

/// A guest range with the price per plate that applies to it.
class GuestTier {
  const GuestTier({required this.minGuests, required this.maxGuests, required this.pricePerPlateRwf});

  factory GuestTier.fromJson(Json json) => GuestTier(
        minGuests: intOf(json['min_guests']),
        maxGuests: intOf(json['max_guests']),
        pricePerPlateRwf: intOf(json['price_per_plate_rwf']),
      );

  final int minGuests;
  final int maxGuests;
  final int pricePerPlateRwf;

  Json toJson() => {
        'min_guests': minGuests,
        'max_guests': maxGuests,
        'price_per_plate_rwf': pricePerPlateRwf,
      };
}

/// A delivery fee for a distance range `[fromKm, toKm)`; the last has no end.
class FeeRange {
  const FeeRange({required this.fromKm, this.toKm, required this.feeRwf});

  factory FeeRange.fromJson(Json json) => FeeRange(
        fromKm: doubleOrNull(json['from_km']) ?? 0,
        toKm: doubleOrNull(json['to_km']),
        feeRwf: intOf(json['fee_rwf']),
      );

  final double fromKm;
  final double? toKm;
  final int feeRwf;

  Json toJson() => {'from_km': fromKm, 'to_km': toKm, 'fee_rwf': feeRwf};
}

class EventPackage {
  const EventPackage({
    this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.tiers = const [],
    this.menu = const [],
    this.portion = '',
    this.serviceStyle = 'buffet',
    this.serviceDetails = '',
  });

  factory EventPackage.fromJson(Json json) => EventPackage(
        id: strOrNull(json['id']),
        name: str(json['name']),
        description: str(json['description']),
        enabled: boolOf(json['enabled'], true),
        tiers: [for (final tier in asJsonList(json['tiers'])) GuestTier.fromJson(tier)],
        menu: stringList(json['menu']),
        portion: str(json['portion']),
        serviceStyle: str(json['service_style'], 'buffet'),
        serviceDetails: str(json['service_details']),
      );

  /// Null for a package that has not been saved yet (the server assigns one).
  final String? id;
  final String name;
  final String description;
  final bool enabled;
  final List<GuestTier> tiers;
  final List<String> menu;
  final String portion;
  final String serviceStyle;
  final String serviceDetails;

  EventPackage copyWith({
    String? name,
    String? description,
    bool? enabled,
    List<GuestTier>? tiers,
    List<String>? menu,
    String? portion,
    String? serviceStyle,
    String? serviceDetails,
  }) =>
      EventPackage(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        enabled: enabled ?? this.enabled,
        tiers: tiers ?? this.tiers,
        menu: menu ?? this.menu,
        portion: portion ?? this.portion,
        serviceStyle: serviceStyle ?? this.serviceStyle,
        serviceDetails: serviceDetails ?? this.serviceDetails,
      );

  Json toJson() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'description': description.trim(),
        'enabled': enabled,
        'tiers': [for (final tier in tiers) tier.toJson()],
        'menu': [for (final item in menu) item.trim()].where((item) => item.isNotEmpty).toList(),
        'portion': portion.trim(),
        'service_style': serviceStyle,
        'service_details': serviceDetails.trim(),
      };
}

/// A kitchen's whole big-event offer (`GET /vendor/event-package`).
class EventPackageSettings {
  const EventPackageSettings({
    this.enabled = false,
    this.packages = const [],
    this.deliveryFeeRanges = const [],
    this.deliveryDetails = '',
    this.serviceStyles = const [],
    this.limits = const EventLimits(),
  });

  factory EventPackageSettings.fromJson(Object? payload) {
    final map = asJson(payload);
    final offer = asJson(map['event_package']);
    final options = asJson(map['options']);
    return EventPackageSettings(
      enabled: boolOf(offer['enabled']),
      packages: [for (final pkg in asJsonList(offer['packages'])) EventPackage.fromJson(pkg)],
      deliveryFeeRanges: [for (final range in asJsonList(offer['delivery_fee_ranges'])) FeeRange.fromJson(range)],
      deliveryDetails: str(offer['delivery_details']),
      serviceStyles: [for (final style in asJsonList(options['service_styles'])) ServiceStyle.fromJson(style)],
      limits: EventLimits.fromJson(asJson(options['limits'])),
    );
  }

  final bool enabled;
  final List<EventPackage> packages;
  final List<FeeRange> deliveryFeeRanges;
  final String deliveryDetails;
  final List<ServiceStyle> serviceStyles;
  final EventLimits limits;

  EventPackageSettings copyWith({
    bool? enabled,
    List<EventPackage>? packages,
    List<FeeRange>? deliveryFeeRanges,
    String? deliveryDetails,
  }) =>
      EventPackageSettings(
        enabled: enabled ?? this.enabled,
        packages: packages ?? this.packages,
        deliveryFeeRanges: deliveryFeeRanges ?? this.deliveryFeeRanges,
        deliveryDetails: deliveryDetails ?? this.deliveryDetails,
        serviceStyles: serviceStyles,
        limits: limits,
      );

  /// The body of `PUT /vendor/event-package`.
  Json toJson() => {
        'enabled': enabled,
        'packages': [for (final pkg in packages) pkg.toJson()],
        'delivery_fee_ranges': [for (final range in deliveryFeeRanges) range.toJson()],
        'delivery_details': deliveryDetails.trim(),
      };
}

/// Limits the form must respect (`options.limits`).
class EventLimits {
  const EventLimits({
    this.guests = const [1, 100000],
    this.plateRwf = const [100, 1000000],
    this.deliveryFeeRwf = const [0, 1000000],
    this.deliveryKm = 500,
    this.packages = 10,
    this.tiers = 10,
    this.menuItems = 30,
  });

  factory EventLimits.fromJson(Json json) {
    List<int> range(Object? value, List<int> fallback) =>
        value is List && value.length == 2 ? [intOf(value[0]), intOf(value[1])] : fallback;
    const defaults = EventLimits();
    return EventLimits(
      guests: range(json['guests'], defaults.guests),
      plateRwf: range(json['plate_rwf'], defaults.plateRwf),
      deliveryFeeRwf: range(json['delivery_fee_rwf'], defaults.deliveryFeeRwf),
      deliveryKm: intOf(json['delivery_km'], defaults.deliveryKm),
      packages: intOf(json['packages'], defaults.packages),
      tiers: intOf(json['tiers'], defaults.tiers),
      menuItems: intOf(json['menu_items'], defaults.menuItems),
    );
  }

  final List<int> guests;
  final List<int> plateRwf;
  final List<int> deliveryFeeRwf;
  final int deliveryKm;
  final int packages;
  final int tiers;
  final int menuItems;
}

/// Client-side checks that mirror `eventPackages.js`, so the vendor sees the
/// problem before the request. The backend still has the final say.
class EventPackageValidator {
  const EventPackageValidator._();

  /// An error for [tiers] (sorted by start), or null when they are valid.
  static String? tiers(List<GuestTier> tiers, EventLimits limits, String packageName) {
    final sorted = [...tiers]..sort((a, b) => a.minGuests.compareTo(b.minGuests));
    for (final tier in sorted) {
      if (tier.minGuests < limits.guests[0] || tier.maxGuests > limits.guests[1]) {
        return '$packageName: guests must be between ${limits.guests[0]} and ${limits.guests[1]}.';
      }
      if (tier.maxGuests < tier.minGuests) {
        return '$packageName: in each guest range the most guests must not be fewer than the fewest.';
      }
      if (tier.pricePerPlateRwf < limits.plateRwf[0] || tier.pricePerPlateRwf > limits.plateRwf[1]) {
        return '$packageName: the price per plate must be between ${limits.plateRwf[0]} and ${limits.plateRwf[1]} RWF.';
      }
    }
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].minGuests <= sorted[i - 1].maxGuests) {
        return '$packageName: guest ranges must not overlap.';
      }
    }
    return null;
  }

  /// An error for the delivery [ranges], or null when they are valid.
  ///
  /// They must start at 0 km, follow each other with no gap or overlap, and
  /// the last one must have no end ("and more").
  static String? feeRanges(List<FeeRange> ranges, EventLimits limits) {
    if (ranges.isEmpty) return null;
    final sorted = [...ranges]..sort((a, b) => a.fromKm.compareTo(b.fromKm));
    if (sorted.first.fromKm != 0) return 'The first range must start at 0 km.';
    for (var i = 0; i < sorted.length; i++) {
      final range = sorted[i];
      if (range.feeRwf < limits.deliveryFeeRwf[0] || range.feeRwf > limits.deliveryFeeRwf[1]) {
        return 'Range ${i + 1}: the fee must be between ${limits.deliveryFeeRwf[0]} and ${limits.deliveryFeeRwf[1]} RWF.';
      }
      if (range.toKm != null && range.toKm! <= range.fromKm) {
        return 'Range ${i + 1}: the end must be more than the start (${range.fromKm} km).';
      }
      if (i < sorted.length - 1) {
        if (range.toKm == null) return 'Only the last range can be open-ended ("and more").';
        if (sorted[i + 1].fromKm != range.toKm) {
          return sorted[i + 1].fromKm > range.toKm!
              ? 'Gap between ${range.toKm} km and ${sorted[i + 1].fromKm} km: every distance needs a fee.'
              : 'Ranges overlap around ${sorted[i + 1].fromKm} km.';
        }
      }
    }
    if (sorted.last.toKm != null) {
      return 'The last range must have no end ("${sorted.last.fromKm} km and more").';
    }
    return null;
  }

  /// The first problem in [settings], or null when it can be saved.
  static String? settings(EventPackageSettings settings) {
    final limits = settings.limits;
    if (settings.packages.length > limits.packages) {
      return 'Add at most ${limits.packages} event packages.';
    }
    for (var i = 0; i < settings.packages.length; i++) {
      final pkg = settings.packages[i];
      final label = pkg.name.trim().isEmpty ? 'Package ${i + 1}' : '"${pkg.name.trim()}"';
      if (pkg.name.trim().length < 2) {
        return 'Give package ${i + 1} a name (e.g. "Wedding buffet").';
      }
      if (pkg.tiers.length > limits.tiers) return '$label: add at most ${limits.tiers} guest ranges.';
      final tierError = tiers(pkg.tiers, limits, label);
      if (tierError != null) return tierError;
      final menu = pkg.menu.where((item) => item.trim().isNotEmpty).toList();
      if (menu.length > limits.menuItems) return '$label: list at most ${limits.menuItems} menu items.';
      if (pkg.enabled && pkg.tiers.isEmpty) {
        return '$label: add at least one guest range with a plate price, or turn the package off.';
      }
      if (pkg.enabled && menu.isEmpty) {
        return '$label: list what is on the plate, or turn the package off.';
      }
    }
    final rangeError = feeRanges(settings.deliveryFeeRanges, limits);
    if (rangeError != null) return rangeError;
    if (settings.enabled && !settings.packages.any((pkg) => pkg.enabled)) {
      return 'Turn on at least one event package before turning big events on.';
    }
    if (settings.enabled && settings.deliveryFeeRanges.isEmpty) {
      return 'Set your delivery fee by distance before turning big events on.';
    }
    return null;
  }
}
