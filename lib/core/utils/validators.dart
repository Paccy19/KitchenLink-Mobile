/// Form rules, kept identical to the website and the backend
/// (`validation.js`, `vendorValidators.js`).
class Validators {
  const Validators._();

  // Rwandan mobile numbers: MTN 078/079, Airtel 072/073, as 07XXXXXXXX,
  // 2507XXXXXXXX or +2507XXXXXXXX.
  static final RegExp _phone = RegExp(r'^(?:\+?250|0)7[2389]\d{7}$');
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9._%+-]{0,62}[A-Za-z0-9_%+-])?@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}$',
  );
  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  static const String phoneError =
      'Enter a valid Rwandan number: 07XXXXXXXX or +2507XXXXXXXX (MTN or Airtel).';
  static const String emailError = 'Enter a valid email address, e.g. name@example.com.';
  static const int nameMaxLength = 50;

  static String _compact(String value) => value.replaceAll(RegExp(r'[\s\-().]'), '');

  static bool isValidPhone(String value) => _phone.hasMatch(_compact(value));

  static bool isValidEmail(String value) {
    final email = value.trim();
    return email.length <= 254 && !email.contains('..') && _email.hasMatch(email);
  }

  static bool isValidTime(String value) => _time.hasMatch(value);

  /// Any accepted form → local `07XXXXXXXX`.
  static String toLocalPhone(String value) {
    var digits = _compact(value).replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('250')) digits = digits.substring(3);
    if (!digits.startsWith('0')) digits = '0$digits';
    return digits;
  }

  /// Mobile-money network of a local number: `mtn` (078/079), `airtel`
  /// (072/073), or null.
  static String? networkOfPhone(String localPhone) {
    if (localPhone.startsWith('078') || localPhone.startsWith('079')) return 'mtn';
    if (localPhone.startsWith('072') || localPhone.startsWith('073')) return 'airtel';
    return null;
  }

  // ---- form-field validators: return an error text, or null when fine ----

  static String? required(String? value, [String label = 'This field']) =>
      (value == null || value.trim().isEmpty) ? '$label is required.' : null;

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your phone number.';
    return isValidPhone(value) ? null : phoneError;
  }

  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return isValidEmail(value) ? null : emailError;
  }

  static String? length(String? value, String label, {required int min, required int max}) {
    final length = value?.trim().length ?? 0;
    if (length < min) {
      return min <= 1 ? '$label is required.' : '$label must be at least $min characters.';
    }
    if (length > max) return '$label must be at most $max characters.';
    return null;
  }

  static String? name(String? value, String label) =>
      length(value, label, min: 2, max: nameMaxLength);

  static String? otp(String? value) {
    final text = value?.trim() ?? '';
    return RegExp(r'^\d{6}$').hasMatch(text) ? null : 'Enter the 6-digit code.';
  }

  /// A whole number in [min]..[max] (blank is an error unless [optional]).
  static String? wholeNumber(
    String? value,
    String label, {
    int min = 0,
    int? max,
    bool optional = false,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return optional ? null : '$label is required.';
    final number = int.tryParse(text.replaceAll(',', ''));
    if (number == null) return '$label must be a whole number.';
    if (number < min) return '$label must be at least $min.';
    if (max != null && number > max) return '$label must be at most $max.';
    return null;
  }

  static String? latitude(String? value) {
    final number = double.tryParse((value ?? '').trim());
    if (number == null) return 'Enter a latitude.';
    return (number < -90 || number > 90) ? 'Latitude is between -90 and 90.' : null;
  }

  static String? longitude(String? value) {
    final number = double.tryParse((value ?? '').trim());
    if (number == null) return 'Enter a longitude.';
    return (number < -180 || number > 180) ? 'Longitude is between -180 and 180.' : null;
  }
}
