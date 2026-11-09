import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

typedef Json = Map<String, dynamic>;

/// An API failure with the message to show the user, as the website's ApiError.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.path = '', this.code = ''});

  final String message;
  final int status;
  final String path;

  /// Machine-readable error code from the API (e.g. 'CHALLENGE_EXPIRED').
  final String code;

  @override
  String toString() => message;
}

/// Thin HTTP client for the `/admin/*` endpoints with the admin bearer token.
///
/// A 401, or a 403 telling a deactivated / not-yet-joined member to leave,
/// calls [onUnauthorized] so the session signs out, like the website.
class ApiClient {
  ApiClient({required this.baseUrl});

  String baseUrl;
  String? token;
  void Function(String? message)? onUnauthorized;

  /// Bumped after every successful write, so open screens refetch
  /// (the website's notifyDataChanged + invalidateQueries).
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Query string that skips null / empty values.
  static String qs([Map<String, Object?>? params]) {
    if (params == null) return '';
    final entries = params.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}');
    final text = entries.join('&');
    return text.isEmpty ? '' : '?$text';
  }

  static String id(String value) => Uri.encodeComponent(value);

  Uri _uri(String path) => Uri.parse('$_base$path');

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> request(String path, {String method = 'GET', Object? body}) async {
    final hasBody = body != null;
    final request = http.Request(method, _uri(path))..headers.addAll(_headers(json: hasBody));
    if (hasBody) request.body = jsonEncode(body);

    http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(milliseconds: kApiTimeoutMs));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('The request took too long. Check your connection.', path: path);
    } catch (_) {
      // No connection, or (in the browser) the backend refused this origin (CORS).
      throw ApiException('Cannot reach the KitchenLink API.', path: path);
    }

    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = null;
    }
    final error = data is Map ? data['error'] : null;
    final errorCode = error is Map ? (error['code'] ?? '').toString() : '';
    final errorMessage = error is Map ? error['message']?.toString() : null;

    if (response.statusCode == 401) {
      token = null;
      onUnauthorized?.call(errorMessage);
    }
    // A deactivated or removed team member is signed out straight away.
    if (response.statusCode == 403 && (errorCode == 'ADMIN_DISABLED' || errorCode == 'INVITATION_PENDING')) {
      token = null;
      onUnauthorized?.call(errorMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        errorMessage ?? (data is Map ? data['message']?.toString() : null) ?? 'Request failed (${response.statusCode}).',
        status: response.statusCode,
        path: path,
        code: errorCode,
      );
    }
    if (data == null && response.body.isNotEmpty) {
      throw ApiException('The API returned malformed JSON.', path: path);
    }
    if (method != 'GET') _changes.add(null);
    return data;
  }

  /// A private file (e.g. a vendor's verification document) fetched with the
  /// admin's sign-in. Returns the bytes and the content type.
  Future<(Uint8List, String)> file(String path) async {
    http.Response response;
    try {
      response = await http.get(_uri(path), headers: _headers()).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('Cannot reach the KitchenLink API.', path: path);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      try {
        message = (jsonDecode(response.body) as Map)['error']?['message']?.toString();
      } catch (_) {}
      throw ApiException(message ?? 'Could not open the file (${response.statusCode}).', status: response.statusCode, path: path);
    }
    return (response.bodyBytes, response.headers['content-type'] ?? '');
  }

  /// Fire-and-forget sign-out on the server, so a copy of the token stops working.
  Future<void> logout(String oldToken) async {
    try {
      await http
          .post(_uri('/admin/auth/logout'), headers: {'Authorization': 'Bearer $oldToken'})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline: the token still expires on its own.
    }
  }
}
