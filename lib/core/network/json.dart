/// Small, forgiving helpers for reading the backend's JSON.
///
/// The API sometimes returns a bare array and sometimes an object wrapping it,
/// and number fields can arrive as numbers or strings, so every model reads
/// through these instead of casting.
typedef Json = Map<String, dynamic>;

Json asJson(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Json> asJsonList(Object? value) => value is List
    ? [for (final item in value) if (item is Map) Map<String, dynamic>.from(item)]
    : <Json>[];

String str(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

String? strOrNull(Object? value) {
  final text = str(value).trim();
  return text.isEmpty ? null : text;
}

int? intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.round();
  return null;
}

int intOf(Object? value, [int fallback = 0]) => intOrNull(value) ?? fallback;

double? doubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool boolOf(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  if (value is num) return value != 0;
  return fallback;
}

DateTime? dateOrNull(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value)?.toLocal();
  return null;
}

List<String> stringList(Object? value) =>
    value is List ? [for (final item in value) if (item != null) str(item)] : <String>[];

/// The list inside a response that may be a bare array or an object holding
/// it under one of [keys] (`{ orders: [...] }`, `{ items: [...] }`…).
List<Json> unwrapList(Object? payload, List<String> keys) {
  if (payload is List) return asJsonList(payload);
  if (payload is Map) {
    for (final key in keys) {
      final inner = payload[key];
      if (inner is List) return asJsonList(inner);
    }
  }
  return <Json>[];
}

/// `meta: { page, limit, total }` of a paged list.
class PageMeta {
  const PageMeta({this.page = 1, this.limit = 0, this.total = 0});

  factory PageMeta.fromJson(Object? json) {
    final map = asJson(json);
    return PageMeta(
      page: intOf(map['page'], 1),
      limit: intOf(map['limit']),
      total: intOf(map['total']),
    );
  }

  final int page;
  final int limit;
  final int total;

  /// The website asks for the next page while `page × limit < total`.
  bool get hasMore => limit > 0 && page * limit < total;
}
