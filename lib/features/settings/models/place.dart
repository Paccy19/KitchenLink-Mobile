import '../../../core/network/json.dart';

/// A suggestion while typing a place (`GET /geo/places/autocomplete`).
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.name,
    this.secondary = '',
    this.kind = 'place',
    this.lat,
    this.lng,
  });

  factory PlaceSuggestion.fromJson(Json json) => PlaceSuggestion(
        id: str(json['id']),
        name: str(json['name']),
        secondary: str(json['secondary']),
        kind: str(json['kind'], 'place'),
        lat: doubleOrNull(json['lat']),
        lng: doubleOrNull(json['lng']),
      );

  final String id;
  final String name;
  final String secondary;

  /// `area`, `street` or `place`.
  final String kind;
  final double? lat;
  final double? lng;
}

/// A picked place with its position (`GET /geo/places/details` → `place`).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.secondary = '',
    this.kind = 'place',
  });

  factory Place.fromJson(Json json) => Place(
        id: str(json['id']),
        name: str(json['name']),
        secondary: str(json['secondary']),
        kind: str(json['kind'], 'place'),
        lat: doubleOrNull(json['lat']) ?? 0,
        lng: doubleOrNull(json['lng']) ?? 0,
      );

  final String id;
  final String name;
  final String secondary;
  final String kind;
  final double lat;
  final double lng;
}
