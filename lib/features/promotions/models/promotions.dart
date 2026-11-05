import '../../../core/network/json.dart';

/// "Tomorrow's Special" (`GET /vendor/special` → `special`, null when none).
class Special {
  const Special({
    required this.text,
    this.cutoffAt,
    this.deliveryAt,
    this.isActive = false,
    this.isOrderable = false,
    this.updatedAt,
  });

  static Special? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final map = asJson(json);
    if (str(map['text']).isEmpty && map['delivery_at'] == null) return null;
    return Special(
      text: str(map['text']),
      cutoffAt: dateOrNull(map['cutoff_at']),
      deliveryAt: dateOrNull(map['delivery_at']),
      isActive: boolOf(map['is_active']),
      isOrderable: boolOf(map['is_orderable']),
      updatedAt: dateOrNull(map['updated_at']),
    );
  }

  final String text;
  final DateTime? cutoffAt;
  final DateTime? deliveryAt;
  final bool isActive;
  final bool isOrderable;
  final DateTime? updatedAt;

  static const int textMax = 160;
}

/// An "Offer Day": a deal announced for a chosen future day.
class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.offerDate,
    this.details = '',
    this.status = '',
    this.createdAt,
  });

  factory Offer.fromJson(Json json) => Offer(
        id: str(json['id']),
        title: str(json['title']),
        details: str(json['details']),
        offerDate: str(json['offer_date']),
        status: str(json['status']),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;
  final String title;
  final String details;

  /// `YYYY-MM-DD` (a Kigali calendar day).
  final String offerDate;
  final String status;
  final DateTime? createdAt;

  static const int titleMax = 80;
  static const int detailsMax = 300;

  /// The backend allows this many upcoming offers per kitchen.
  static const int maxUpcoming = 3;

  /// The furthest day an offer may be announced (days from today).
  static const int maxDaysAhead = 60;
}
