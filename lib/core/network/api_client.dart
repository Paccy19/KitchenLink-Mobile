import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// The single door to the KitchenLink API.
///
/// - Sends `Authorization: Bearer <vendor token>` on every request except the
///   ones marked `auth: false` (sign-in, registration, public lists).
/// - Turns every failure into an [ApiException], whatever its cause.
/// - Reports a rejected session (401) and a blocked account (403 suspended /
///   rejected) to the session layer. Ordinary failures never sign anyone out.
class ApiClient {
  ApiClient({required AppConfig config, Dio? dio})
      : dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: AppConfig.connectTimeoutSeconds),
                receiveTimeout: const Duration(seconds: AppConfig.receiveTimeoutSeconds),
                headers: const {'Accept': 'application/json'},
                // Non-2xx responses are parsed by us, into ApiException.
                validateStatus: (_) => true,
              ),
            ) {
    this.dio.options.validateStatus = (_) => true;
  }

  final Dio dio;
  String? _token;

  /// A signed-in request got 401: the token is no longer valid.
  void Function()? onSessionInvalid;

  /// A request was refused because the account is suspended or rejected.
  void Function(ApiException error)? onAccountBlocked;

  /// A write was refused because the documents are still under review.
  void Function(ApiException error)? onPendingReview;

  /// Called after every request: true when the server answered, false when it
  /// could not be reached.
  void Function(bool online)? onConnectivity;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  void setToken(String? token) => _token = token;

  Future<Object?> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<Object?> post(String path, {Object? data, bool auth = true}) =>
      _send('POST', path, data: data, auth: auth);

  Future<Object?> put(String path, {Object? data, bool auth = true}) =>
      _send('PUT', path, data: data, auth: auth);

  Future<Object?> patch(String path, {Object? data, bool auth = true}) =>
      _send('PATCH', path, data: data, auth: auth);

  Future<Object?> delete(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _send('DELETE', path, query: query, auth: auth);

  /// Sends a `multipart/form-data` request (files are real parts, never base64).
  Future<Object?> multipart(
    String method,
    String path,
    FormData form, {
    bool auth = true,
    void Function(int sent, int total)? onProgress,
  }) =>
      _send(method, path, data: form, auth: auth, onProgress: onProgress);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    bool auth = true,
    void Function(int sent, int total)? onProgress,
  }) async {
    final sentToken = auth ? _token : null;
    final Response<dynamic> response;
    try {
      response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        onSendProgress: onProgress,
        options: Options(
          method: method,
          headers: {if (sentToken != null) 'Authorization': 'Bearer $sentToken'},
          // JSON bodies are encoded by Dio; FormData sets its own boundary.
          contentType: data is FormData ? null : (data == null ? null : Headers.jsonContentType),
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (error) {
      final mapped = _mapDioError(error);
      if (mapped.isNetwork) onConnectivity?.call(false);
      throw mapped;
    }
    onConnectivity?.call(true);

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final body = response.data;
      if (body is String && body.trim().isNotEmpty) {
        // e.g. an HTML page from a proxy answering API paths.
        throw const ApiException(message: 'The server returned an unexpected response.');
      }
      return body is String ? null : body;
    }

    final error = ApiException.fromResponse(status, response.data);
    _report(error, sentToken);
    throw error;
  }

  void _report(ApiException error, String? sentToken) {
    if (error.isUnauthorized && sentToken != null && sentToken == _token) {
      onSessionInvalid?.call();
    } else if (error.isBlockedAccount) {
      onAccountBlocked?.call(error);
    } else if (error.isPendingReview) {
      onPendingReview?.call(error);
    }
  }

  ApiException _mapDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException.timedOut;
      case DioExceptionType.connectionError:
        return ApiException.offline;
      case DioExceptionType.cancel:
        return const ApiException(message: 'The request was cancelled.');
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'The secure connection to the server could not be verified.',
          kind: ApiErrorKind.network,
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        if (error.error is SocketException || error.error is HttpException) {
          return ApiException.offline;
        }
        return const ApiException(message: 'Something went wrong. Please try again.');
    }
  }
}
