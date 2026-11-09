import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/screens/vendor_login_screen.dart';

Future<VendorSignIn?> Function() _open(WidgetTester tester) {
  VendorSignIn? result;
  var done = false;
  return () async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<VendorSignIn>(
                  MaterialPageRoute(
                    builder: (_) => VendorLoginScreen(client: ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
                  ),
                );
                done = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return done ? result : null;
  };
}

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [360.0, 800.0]) {
    testWidgets('vendor login: phone, then code, at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sent = <String, Object?>{};
      final mock = MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        sent[path] = jsonDecode(request.body);
        return switch (path) {
          '/vendor/auth/send-otp' => _json(200, {'phone_number': '+250788123456', 'dev_otp': '654321'}),
          '/vendor/auth/verify-otp' => _json(200, {
            'token': 'vendor-token',
            'vendor': {'id': 'v1', 'name': 'Mama Africa Kitchen'},
          }),
          _ => _json(404, {}),
        };
      });

      await http.runWithClient(() async {
        await _open(tester)();
        for (final text in [
          'Vendor Login',
          'Sign in securely using a one-time code sent to your vendor phone.',
          'Vendor phone number',
          'Send verification code',
          'Create a vendor account',
          'Back to marketplace',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }

        await tester.enterText(find.byType(TextField), '0788123456');
        await tester.tap(find.text('Send verification code'));
        await tester.pumpAndSettle();
        expect(sent['/vendor/auth/send-otp'], {'phone': '0788123456'});

        expect(find.text('6-digit verification code'), findsOneWidget);
        expect(find.text('Code sent to +250788123456'), findsOneWidget);
        expect(find.textContaining('Development code: ', findRichText: true), findsOneWidget);
        expect(find.text('Change phone number'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '654321');
        await tester.tap(find.text('Verify & sign in'));
        await tester.pumpAndSettle();
        expect(sent['/vendor/auth/verify-otp'], {'phone': '+250788123456', 'code': '654321'});
        expect(find.text('Vendor Login'), findsNothing);
        expect(await const FlutterSecureStorage().read(key: VendorLoginScreen.tokenKey), 'vendor-token');
      }, () => mock);
    });
  }

  testWidgets('suspended vendor sees the reason and support contact', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final mock = MockClient(
      (request) async => _json(403, {
        'error': {
          'code': 'VENDOR_SUSPENDED',
          'message': 'Your vendor account has been suspended.',
          'details': {
            'status': 'suspended',
            'reason': 'Repeated late orders.',
            'support_phone': '+250 788 000 000',
            'support_email': 'help@kitchenlink.rw',
          },
        },
      }),
    );

    await http.runWithClient(() async {
      await _open(tester)();
      await tester.enterText(find.byType(TextField), '0788123456');
      await tester.tap(find.text('Send verification code'));
      await tester.pumpAndSettle();

      expect(find.text('Your account is suspended'), findsOneWidget);
      expect(find.text('REASON'), findsOneWidget);
      expect(find.text('Repeated late orders.'), findsOneWidget);
      expect(find.text('Call support: +250 788 000 000'), findsOneWidget);
      expect(find.text('help@kitchenlink.rw'), findsOneWidget);

      await tester.tap(find.text('Back to login'));
      await tester.pumpAndSettle();
      expect(find.text('Vendor Login'), findsOneWidget);
    }, () => mock);
  });
}
