import '../../core/network/json.dart';

/// A latitude/longitude pair.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class RouteStep {
  const RouteStep({required this.instruction, this.name = '', this.distanceM = 0, this.durationS = 0});

  factory RouteStep.fromJson(Json json) => RouteStep(
        instruction: str(json['instruction']),
        name: str(json['name']),
        distanceM: doubleOrNull(json['distance_m']) ?? 0,
        durationS: doubleOrNull(json['duration_s']) ?? 0,
      );

  final String instruction;
  final String name;
  final double distanceM;
  final double durationS;
}

/// `GET /driver/deliveries/:id/navigation`: the road route to the kitchen,
/// then (after pickup) to the customer.
class TripNavigation {
  const TripNavigation({
    required this.active,
    this.phaseLabel = '',
    this.target = 'kitchen',
    this.driverPosition,
    this.positionStale = false,
    this.kitchen,
    this.destination,
    this.geometry = const [],
    this.distanceM,
    this.durationS,
    this.etaAt,
    this.steps = const [],
    this.refreshAfterSeconds = 10,
  });

  factory TripNavigation.fromJson(Json json) {
    final route = asJson(json['route']);
    final driverLocation = asJson(asJson(json['driver'])['location']);
    GeoPoint? point(Object? raw) {
      final map = asJson(raw);
      final lat = doubleOrNull(map['latitude']);
      final lng = doubleOrNull(map['longitude']);
      return lat == null || lng == null ? null : GeoPoint(lat, lng);
    }

    final geometry = <GeoPoint>[];
    final raw = route['geometry'];
    if (raw is List) {
      for (final pair in raw) {
        // OSRM order: [longitude, latitude].
        if (pair is List && pair.length >= 2) {
          final lng = doubleOrNull(pair[0]);
          final lat = doubleOrNull(pair[1]);
          if (lat != null && lng != null) geometry.add(GeoPoint(lat, lng));
        }
      }
    }

    return TripNavigation(
      active: boolOf(json['active'], true),
      phaseLabel: str(json['phase_label']),
      target: str(json['target'], 'kitchen'),
      driverPosition: point(driverLocation),
      positionStale: boolOf(driverLocation['stale']),
      kitchen: point(json['kitchen']),
      destination: point(json['destination']),
      geometry: geometry,
      distanceM: doubleOrNull(route['distance_m']),
      durationS: doubleOrNull(route['duration_s']),
      etaAt: dateOrNull(route['eta_at']),
      steps: [for (final step in asJsonList(route['steps'])) RouteStep.fromJson(step)],
      refreshAfterSeconds: intOf(json['refresh_after_s'], 10).clamp(4, 60),
    );
  }

  final bool active;
  final String phaseLabel;

  /// `kitchen` before pickup, `customer` after.
  final String target;
  final GeoPoint? driverPosition;
  final bool positionStale;
  final GeoPoint? kitchen;
  final GeoPoint? destination;
  final List<GeoPoint> geometry;
  final double? distanceM;
  final double? durationS;
  final DateTime? etaAt;
  final List<RouteStep> steps;
  final int refreshAfterSeconds;

  bool get headingToKitchen => target != 'customer';
  GeoPoint? get targetPoint => headingToKitchen ? kitchen : destination;
  RouteStep? get nextStep => steps.isEmpty ? null : steps.first;
}
