import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'preview_data.dart';
import 'preview_mode.dart';

/// A Dio adapter that serves the vendor API from [PreviewData] instead of the
/// network.
///
/// - `GET` → sample data shaped like the real backend's responses.
/// - Anything else (create, update, delete, status change, upload, sign-out…)
///   → refused with a 403 `PREVIEW_MODE` error, so the app shows the message
///   and nothing changes anywhere.
///
/// No socket is ever opened, so there is nothing to leak to the real server.
class PreviewAdapter implements HttpClientAdapter {
  PreviewAdapter({
    PreviewData? data,
    this.latency = const Duration(milliseconds: 180),
  }) : data = data ?? PreviewData(DateTime.now());

  final PreviewData data;

  /// A short pause so loading states are visible, like a real request.
  final Duration latency;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    if (options.method.toUpperCase() != 'GET') {
      return _json(403, {
        'error': {
          'code': kPreviewErrorCode,
          'message':
              'Preview mode: this is sample data, so nothing was saved or sent. '
              'Sign in with a vendor account to do this for real.',
        },
      });
    }

    final result = data.get(options.path, options.queryParameters);
    if (result == null) {
      return _json(404, {
        'error': {
          'code': 'PREVIEW_NOT_AVAILABLE',
          'message': 'Not available in preview mode.',
        },
      });
    }
    return _json(200, result);
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
