// ignore_for_file: invalid_use_of_visible_for_testing_member
// Design review screenshots of the admin console (demo server, on device):
//   flutter test tool/shots/admin_shots_test.dart --update-goldens
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/demo/demo_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/screens/admin_app.dart';

import 'shots_support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (name, tap) in [('overview', null), ('more', 'More')]) {
      testWidgets('admin $name $mode', (tester) async {
        phone(tester, height: name == 'overview' ? 1700 : 852);
        FlutterSecureStorage.setMockInitialValues({'ofk_admin_token': 'demo-token-admin', 'ofk_theme': mode});
        final demo = DemoServer();
        // The website's demo data, answered on the device.
        final client = MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1', '') + (request.url.hasQuery ? '?${request.url.query}' : '');
          try {
            final data = await demo.handle(request.method, path, request.body.isEmpty ? null : jsonDecode(request.body), request.headers['Authorization']?.replaceFirst('Bearer ', ''));
            return http.Response(jsonEncode(data), 200, headers: {'content-type': 'application/json'});
          } on ApiException catch (e) {
            return http.Response(jsonEncode({'error': {'message': e.message, 'code': e.code}}), e.status, headers: {'content-type': 'application/json'});
          }
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(buildAdminApp());
          await settle(tester, 20);
          if (tap != null) {
            await tester.tap(find.text(tap).last);
            await settle(tester, 10);
          }
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/admin-$name-$mode.png'));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 20));
        }, () => client);
      });
    }
  }
}
