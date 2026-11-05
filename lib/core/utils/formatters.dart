import 'package:intl/intl.dart';

/// Whole-franc money, the way the website writes it: `RWF 2,500`.
String formatRwf(num? amount) =>
    'RWF ${NumberFormat('#,##0').format(amount?.round() ?? 0)}';

String formatNumber(num? value) => NumberFormat('#,##0').format(value ?? 0);

/// `4 Nov 2026, 14:30` in the phone's time zone.
String formatDateTime(DateTime? value) =>
    value == null ? '—' : DateFormat('d MMM yyyy, HH:mm').format(value);

String formatDate(DateTime? value) =>
    value == null ? '—' : DateFormat('EEE d MMM yyyy').format(value);

String formatTime(DateTime? value) => value == null ? '—' : DateFormat('HH:mm').format(value);

/// `YYYY-MM-DD`, the format of an Offer Day.
String formatIsoDay(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

/// An Offer Day (`2026-11-05`) as `Thu 5 Nov 2026`.
String formatOfferDay(String isoDay) {
  final parsed = DateTime.tryParse(isoDay);
  return parsed == null ? isoDay : DateFormat('EEE d MMM yyyy').format(parsed);
}

/// `just now`, `5 min ago`, `3 h ago`, `2 days ago`.
String timeAgo(DateTime? value, {DateTime? now}) {
  if (value == null) return '';
  final minutes = (now ?? DateTime.now()).difference(value).inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '$hours h ago';
  final days = (hours / 24).round();
  return '$days day${days > 1 ? 's' : ''} ago';
}

/// `snake_case` / `lower words` → `Title case`.
String humanize(String value) {
  final text = value.replaceAll('_', ' ').trim();
  if (text.isEmpty) return '';
  return text[0].toUpperCase() + text.substring(1);
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final second = parts.length > 1 ? parts.last[0] : '';
  return (first + second).toUpperCase();
}
