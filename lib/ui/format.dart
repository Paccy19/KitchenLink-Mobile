import 'package:intl/intl.dart';

import '../api/api_client.dart';

// ---- Reading raw JSON (the API's snake_case payloads) ----------------------

Json jmap(dynamic value) => value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Json> jlist(dynamic value) =>
    value is List ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];

String jstr(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

num jnum(dynamic value, [num fallback = 0]) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? fallback;
  return fallback;
}

int jint(dynamic value, [int fallback = 0]) => jnum(value, fallback).toInt();

// ---- Formatting, as the website's admin ui.jsx ----------------------------

final _thousands = NumberFormat.decimalPattern('en_US');

String formatNumber(dynamic value) => _thousands.format(jnum(value));

String formatRwf(dynamic value) => '${formatNumber(value)} RWF';

DateTime? parseDate(dynamic iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso.toString())?.toLocal();
}

String formatDate(dynamic iso, {bool withTime = true}) {
  final date = parseDate(iso);
  if (date == null) return '—';
  return DateFormat(withTime ? 'dd MMM yyyy, HH:mm' : 'dd MMM yyyy').format(date);
}

String formatTime(DateTime date) => DateFormat('HH:mm').format(date);

String formatRelative(dynamic iso) {
  final date = parseDate(iso);
  if (date == null) return '';
  final seconds = DateTime.now().difference(date).inSeconds.clamp(0, 1 << 31);
  if (seconds < 60) return 'just now';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '${minutes}m ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '${hours}h ago';
  return '${(hours / 24).round()}d ago';
}

String toTitle(dynamic value) => jstr(value)
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'\b\w'), (match) => match.group(0)!.toUpperCase());

/// "1.2 km" / "350 m" (route distances in metres).
String formatDistance(num metres) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(metres >= 10000 ? 0 : 1)} km'
    : '${((metres / 10).round() * 10).clamp(0, 1 << 31)} m';

/// "12 min" / "1 h 5 min" (route durations in seconds).
String formatMinutes(num seconds) {
  final min = (seconds / 60).round().clamp(1, 1 << 31);
  return min >= 60 ? '${min ~/ 60} h ${min % 60} min' : '$min min';
}

/// `YYYY-MM-DD` for date filters.
String isoDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
