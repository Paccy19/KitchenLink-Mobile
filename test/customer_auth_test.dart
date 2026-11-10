import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/customer_session.dart';
import 'package:kitchenlink_mobile/client/widgets/customer_auth_sheet.dart';

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets('customer sign-in popup: phone, then OTP, at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({});

      final sent = <String, Map<String, dynamic>>{};
      final mock = MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        sent[path] = jsonDecode(request.body) as Map<String, dynamic>;
        final body = switch (path) {
          '/auth/send-otp' => {
            'phone_number': '+250788123456',
            'dev_otp': '123456',
          },
          '/auth/verify-otp' => {
            'token': 'customer-token',
            'customer': {
              'id': 'c1',
              'name': 'Jean Paul',
              'phone_number': '+250788123456',
            },
          },
          _ => null,
        };
        return http.Response(
          jsonEncode(body ?? {}),
          body == null ? 404 : 200,
          headers: {'content-type': 'application/json'},
        );
      });

      await http.runWithClient(() async {
        final session = CustomerSession(
          ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
        );
        bool? result;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: session,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async =>
                        result = await showCustomerSignIn(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        for (final text in [
          'Welcome to KitchenLink',
          'Enter your phone number to sign in or create your customer account',
          'FULL NAME',
          'Also a kitchen or delivery worker on KitchenLink? Use the same name you registered with.',
          'PHONE NUMBER (MTN / AIRTEL)',
          'Continue & Send OTP',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }

        // Invalid phone is caught before calling the server.
        await tester.enterText(find.byType(TextField).at(0), 'jean paul');
        await tester.enterText(find.byType(TextField).at(1), '12345');
        await tester.tap(find.text('Continue & Send OTP'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Enter a valid Rwandan number'),
          findsOneWidget,
        );
        expect(sent, isEmpty);

        await tester.enterText(find.byType(TextField).at(1), '0788123456');
        await tester.tap(find.text('Continue & Send OTP'));
        await tester.pumpAndSettle();
        expect(sent['/auth/send-otp'], {
          'phone_number': '0788123456',
          'name': 'Jean Paul',
        });

        expect(find.text('Verify OTP Code'), findsOneWidget);
        expect(
          find.textContaining('+250788123456', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Development OTP: 123456'), findsOneWidget);
        await tester.tap(find.text('Insert code'));
        await tester.pump();
        await tester.tap(find.text('Verify & Sign In'));
        await tester.pumpAndSettle();

        expect(sent['/auth/verify-otp'], {
          'phone_number': '+250788123456',
          'code': '123456',
          'name': 'Jean Paul',
        });
        expect(result, isTrue);
        expect(session.isSignedIn, isTrue);
        expect(session.firstName, 'Jean');
        expect(session.phone, '+250788123456');
        expect(session.client.token, 'customer-token');
        expect(find.text('Verify OTP Code'), findsNothing);
      }, () => mock);
    });
  }

  test('customer session restores and clears its saved identity', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ofk_access_token': 'saved-token',
      'ofk_customer_name': 'Jean Paul',
      'ofk_customer_phone': '+250788123456',
    });

    final session = CustomerSession(
      ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
    );
    await session.restore();

    expect(session.isSignedIn, isTrue);
    expect(session.firstName, 'Jean');
    expect(session.phone, '+250788123456');
    expect(session.client.token, 'saved-token');

    await session.logout();
    expect(session.isSignedIn, isFalse);
    expect(session.client.token, isNull);
    expect(await const FlutterSecureStorage().read(key: 'ofk_access_token'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'ofk_customer_name'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'ofk_customer_phone'), isNull);
  });
}
