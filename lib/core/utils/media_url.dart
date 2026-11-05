import '../config/app_config.dart';

/// Turns an image URL from the API into one this phone can load.
///
/// - Absolute URLs are used as they are.
/// - Relative paths (`/uploads/x.jpg`) are resolved against the API server.
/// - A URL that points at `localhost` / `127.0.0.1` (the backend's
///   `PUBLIC_BASE_URL` on a development machine) is unreachable from a phone
///   or emulator, so only its host is swapped for the API server's.
String? resolveMediaUrl(String? url, {AppConfig? config}) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) return null;
  final origin = (config ?? AppConfig.current).origin;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;

  if (!parsed.hasScheme) {
    return origin.resolve(raw.startsWith('/') ? raw : '/$raw').toString();
  }
  const loopback = {'localhost', '127.0.0.1', '0.0.0.0', '::1'};
  if (loopback.contains(parsed.host) && !loopback.contains(origin.host)) {
    return parsed.replace(host: origin.host, port: origin.hasPort ? origin.port : null).toString();
  }
  return raw;
}
