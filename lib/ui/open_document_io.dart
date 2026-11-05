import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';

/// Native viewer for downloaded files (MainActivity.kt / AppDelegate.swift).
const _files = MethodChannel('kitchenlink/files');

Future<void> openDocument(Uint8List bytes, String mime, String name) async {
  final ext = mime.contains('pdf') ? 'pdf' : 'bin';
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.$ext');
  await file.writeAsBytes(bytes, flush: true);
  try {
    await _files.invokeMethod('open', {'path': file.path, 'mime': mime});
  } on PlatformException catch (err) {
    throw ApiException(err.message ?? 'Could not open the document.');
  }
}
