import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads every font the app bundles (text and icons), so screenshots show
/// real glyphs instead of the test font's boxes.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// An iPhone 15 screen (393 × 852 points at 3×), or another size.
void phone(WidgetTester tester, {double width = 393, double height = 852}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets real network images arrive and decode, then draws them.
Future<void> loadImages(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester, 6);
}

/// Serves a folder of photos on localhost to the app's Image.network.
class ImageServer {
  ImageServer._(this._server, this.base);

  final HttpServer _server;
  final String base;

  static Future<ImageServer> start(String folder) async {
    HttpOverrides.global = null; // flutter_test blocks the network by default
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final file = File('$folder${request.uri.path}');
      if (await file.exists()) {
        request.response.headers.contentType = ContentType('image', 'jpeg');
        await request.response.addStream(file.openRead());
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    return ImageServer._(server, 'http://127.0.0.1:${server.port}');
  }

  Future<void> close() => _server.close(force: true);
}
