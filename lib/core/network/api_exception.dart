/// What kind of failure an [ApiException] describes.
enum ApiErrorKind {
  /// No connection, DNS failure, refused connection…
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  server,
  unknown,
}

/// Well-known backend error codes the app reacts to.
class ApiCodes {
  const ApiCodes._();

  static const vendorPendingReview = 'VENDOR_PENDING_REVIEW';
  static const vendorSuspended = 'VENDOR_SUSPENDED';
  static const vendorRejected = 'VENDOR_REJECTED';
  static const otpResendTooSoon = 'OTP_RESEND_TOO_SOON';
  static const pickupCodeIncorrect = 'PICKUP_CODE_INCORRECT';
  static const pickupCodeLocked = 'PICKUP_CODE_LOCKED';
  static const locationRequired = 'LOCATION_REQUIRED';
}

/// A failed API call, parsed from `{ error: { code, message, details } }`.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code = '',
    this.details = const {},
    this.kind = ApiErrorKind.unknown,
  });

  /// Written for people by the backend; shown as is.
  final String message;
  final int? statusCode;
  final String code;
  final Map<String, dynamic> details;
  final ApiErrorKind kind;

  bool get isNetwork => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
  bool get isPendingReview => code == ApiCodes.vendorPendingReview;
  bool get isBlockedAccount =>
      code == ApiCodes.vendorSuspended || code == ApiCodes.vendorRejected;

  /// `details` entries that are plain strings, keyed by field name
  /// (`{ phone: 'expected …' }`), for showing next to form fields.
  Map<String, String> get fieldErrors => {
        for (final entry in details.entries)
          if (entry.value is String) entry.key: entry.value as String,
      };

  /// Seconds before a rate-limited action may be retried, when the backend says.
  int? get retryAfterSeconds {
    final value = details['retry_after_seconds'];
    return value is num ? value.toInt() : null;
  }

  static ApiErrorKind kindForStatus(int? status) {
    switch (status) {
      case 400:
      case 422:
        return ApiErrorKind.validation;
      case 401:
        return ApiErrorKind.unauthorized;
      case 403:
        return ApiErrorKind.forbidden;
      case 404:
        return ApiErrorKind.notFound;
      case 409:
        return ApiErrorKind.conflict;
      case 429:
        return ApiErrorKind.rateLimited;
    }
    if (status != null && status >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  /// Builds an exception from a decoded error body (any shape).
  factory ApiException.fromResponse(int? status, Object? body) {
    var message = '';
    var code = '';
    var details = <String, dynamic>{};
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        message = _text(error['message']);
        code = _text(error['code']);
        final rawDetails = error['details'];
        if (rawDetails is Map) details = Map<String, dynamic>.from(rawDetails);
      } else if (error is String) {
        message = error;
      }
      if (message.isEmpty) message = _text(body['message']);
    }
    final kind = kindForStatus(status);
    if (message.isEmpty) {
      message = switch (kind) {
        ApiErrorKind.server => 'The server had a problem. Please try again shortly.',
        ApiErrorKind.notFound => 'We could not find that.',
        ApiErrorKind.forbidden => 'You are not allowed to do that.',
        ApiErrorKind.unauthorized => 'Please sign in again.',
        ApiErrorKind.rateLimited => 'Too many requests. Please wait a moment.',
        _ => 'Request failed${status == null ? '' : ' ($status)'}.',
      };
    }
    return ApiException(
      message: message,
      statusCode: status,
      code: code,
      details: details,
      kind: kind,
    );
  }

  static const ApiException offline = ApiException(
    message: 'No connection. Check your internet and try again.',
    kind: ApiErrorKind.network,
  );

  static const ApiException timedOut = ApiException(
    message: 'The request took too long. Check your connection and try again.',
    kind: ApiErrorKind.timeout,
  );

  static String _text(Object? value) => value is String ? value.trim() : '';

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}

/// A readable message for any error thrown while loading or saving.
String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is String && error.isNotEmpty) return error;
  return 'Something went wrong. Please try again.';
}
