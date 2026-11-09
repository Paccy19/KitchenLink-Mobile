import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/screens/staff_login_screen.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [360.0, 800.0]) {
    testWidgets('delivery worker login: phone, then code, at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sent = <String, Object?>{};
      final mock = MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        sent[path] = jsonDecode(request.body);
        return switch (path) {
          '/driver/auth/register' => _json(201, {
            'driver': {'id': 'd1', 'name': 'Eric Moto'},
          }),
          '/driver/auth/send-otp' => _json(200, {'phone_number': '+250788123456', 'dev_otp': '112233'}),
          '/driver/auth/verify-otp' => _json(200, {
            'token': 'driver-token',
            'driver': {'id': 'd1', 'name': 'Eric Moto'},
          }),
          _ => _json(404, {}),
        };
      });

      await http.runWithClient(() async {
        StaffSignIn? result;
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await Navigator.of(context).push<StaffSignIn>(
                  MaterialPageRoute(builder: (_) => DriverLoginScreen(client: ApiClient(baseUrl: 'http://localhost:4000/api/v1'))),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        for (final text in [
          'Delivery Worker Login',
          'Sign in securely using a one-time code sent to your phone.',
          'Phone number',
          'Send verification code',
          'Create a driver account',
          'Back to marketplace',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(find.byIcon(Icons.directions_bike), findsOneWidget);

        // Create a driver account → "Become a Delivery Worker" → back to login.
        await tester.tap(find.text('Create a driver account'));
        await tester.pumpAndSettle();
        for (final text in [
          'Become a Delivery Worker',
          'Deliver orders and earn on every trip. Sign in with a code when you’re done.',
          'Full name',
          'Phone number',
          'Vehicle',
          'Motorcycle',
          'Plate number',
          'Create delivery worker account',
          'Already a driver? Log in',
          'Back to marketplace',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        await tester.tap(find.text('Create delivery worker account'));
        await tester.pumpAndSettle();
        expect(find.text('Enter your full name.'), findsOneWidget);
        expect(sent, isEmpty);

        Finder field(String hint) => find.ancestor(of: find.text(hint), matching: find.byType(TextField)).first;
        await tester.enterText(field('e.g. Eric Uwimana'), 'eric moto');
        await tester.enterText(field('07XXXXXXXX'), '0788123456');
        await tester.enterText(field('RAD 101 A'), 'RAD 101 A');
        await tester.tap(find.text('Motorcycle'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bicycle').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create delivery worker account'));
        await tester.pumpAndSettle();
        expect(sent['/driver/auth/register'], {
          'name': 'Eric Moto',
          'phone': '0788123456',
          'vehicle_type': 'bicycle',
          'plate_number': 'RAD 101 A',
        });
        expect(find.text('Delivery Worker Login'), findsOneWidget);
        expect(find.text('Delivery worker account created — log in with a verification code'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '0788123456');
        await tester.tap(find.text('Send verification code'));
        await tester.pumpAndSettle();
        expect(sent['/driver/auth/send-otp'], {'phone': '0788123456'});
        expect(find.text('Code sent to +250788123456'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '112233');
        await tester.tap(find.text('Verify & sign in'));
        await tester.pumpAndSettle();
        expect(sent['/driver/auth/verify-otp'], {'phone': '+250788123456', 'code': '112233'});
        expect(result?.name, 'Eric Moto');
        expect(await const FlutterSecureStorage().read(key: DriverLoginScreen.tokenKey), 'driver-token');
      }, () => mock);
    });
  }
}
