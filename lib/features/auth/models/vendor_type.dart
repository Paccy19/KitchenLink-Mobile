import '../../../core/network/json.dart';

/// A kitchen type from `GET /vendors/types`.
class VendorType {
  const VendorType({
    required this.code,
    required this.label,
    this.description = '',
    this.strengths = const [],
    this.note = '',
  });

  factory VendorType.fromJson(Json json) => VendorType(
        code: str(json['code']),
        label: str(json['label']),
        description: str(json['description']),
        strengths: stringList(json['strengths']),
        note: str(json['note']),
      );

  final String code;
  final String label;
  final String description;
  final List<String> strengths;
  final String note;

  static List<VendorType> listFromPayload(Object? payload) => [
        for (final item in unwrapList(payload, ['vendor_types', 'types'])) VendorType.fromJson(item),
      ];
}
