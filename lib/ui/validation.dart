/// Email and Rwandan phone rules, the same as the website's utils/validation.js
/// (the backend applies them too).
library;

// Rwandan mobile numbers: MTN 078/079, Airtel 072/073.
final _rwPhone = RegExp(r'^(?:\+?250|0)7[2389]\d{7}$');
final _email = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9._%+-]{0,62}[A-Za-z0-9_%+-])?@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}$',
);

const emailMaxLength = 254;
const phoneMaxLength = 13;
const nameMaxLength = 50;
const phonePlaceholder = '07XXXXXXXX';
const phoneError = 'Enter a valid Rwandan number: 07XXXXXXXX or +2507XXXXXXXX (MTN or Airtel).';
const emailError = 'Enter a valid email address, e.g. name@example.com.';

String _compact(String value) => value.replaceAll(RegExp(r'[\s\-().]'), '');

/// Keeps a leading "+" and digits, cut at the number's full length.
String sanitizePhoneInput(String value) {
  var next = value.replaceAll(RegExp(r'[^\d+]'), '');
  next = next.replaceAllMapped(RegExp(r'(?!^)\+'), (_) => '');
  final max = next.startsWith('+') ? 13 : next.startsWith('250') ? 12 : 10;
  return next.length > max ? next.substring(0, max) : next;
}

String sanitizeEmailInput(String value) {
  final next = value.replaceAll(RegExp(r'\s'), '');
  return next.length > emailMaxLength ? next.substring(0, emailMaxLength) : next;
}

bool isValidRwandaPhone(String value) => _rwPhone.hasMatch(_compact(value));

bool isValidEmail(String value) {
  final email = value.trim();
  return email.length <= emailMaxLength && !email.contains('..') && _email.hasMatch(email);
}

/// "jean paul" → "Jean Paul" as the user types, capped at [nameMaxLength].
String formatNameInput(String value) {
  var next = value.replaceFirst(RegExp(r'^\s+'), '').replaceAll(RegExp(r'\s{2,}'), ' ');
  next = next.replaceAllMapped(
    RegExp(r"(^|[\s'-])(\p{Ll})", unicode: true),
    (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}',
  );
  return next.length > nameMaxLength ? next.substring(0, nameMaxLength) : next;
}
