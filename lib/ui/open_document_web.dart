import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../api/api_client.dart';

/// Opens the file in a new tab as a temporary blob: URL (like the website).
Future<void> openDocument(Uint8List bytes, String mime, String name) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final tab = web.window.open(url, '_blank');
  if (tab == null) {
    web.URL.revokeObjectURL(url);
    throw ApiException('The browser blocked the new tab. Allow pop-ups for this site and try again.');
  }
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}
