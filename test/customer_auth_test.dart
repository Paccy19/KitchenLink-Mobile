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
          'Enter your phone number or email to sign in or create your customer account',
          'FULL NAME',
          'Also a kitchen or delivery worker on KitchenLink? Use the same name you registered with.',
          'PHONE NUMBER OR EMAIL',
          'Continue & Send OTP',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }

        // An invalid phone (or email) is caught before calling the server.
        await tester.enterText(find.byType(TextField).at(0), 'jean paul');
        await tester.enterText(find.byType(TextField).at(1), '12345');
        await tester.tap(find.text('Continue & Send OTP'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Enter a valid phone number (07XXXXXXXX'),
          findsOneWidget,
        );
        expect(sent, isEmpty);

        await tester.enterText(find.byType(TextField).at(1), '0788123456');
        await tester.tap(find.text('Continue & Send OTP'));
        await tester.pumpAndSettle();
        // One field: the server decides whether it is a phone or an email.
        expect(sent['/auth/send-otp'], {
          'identifier': '0788123456',
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
          'identifier': '+250788123456',
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

  /// The sign-in popup against [respond] (path → JSON, or null for 404), recording what was sent.
  Future<({CustomerSession session, Map<String, Map<String, dynamic>> sent, bool? Function() result})> openSignIn(
    WidgetTester tester,
    Map<String, dynamic>? Function(String path) respond,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String, Map<String, dynamic>>{};
    final session = CustomerSession(ApiClient(baseUrl: 'http://localhost:4000/api/v1'));
    bool? result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () async => result = await showCustomerSignIn(context), child: const Text('Open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (session: session, sent: sent, result: () => result);
  }

  MockClient mockFor(Map<String, Map<String, dynamic>> sent, Map<String, dynamic>? Function(String path) respond) =>
      MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        sent[path] = request.body.isEmpty ? {} : jsonDecode(request.body) as Map<String, dynamic>;
        final body = respond(path);
        return http.Response(jsonEncode(body ?? {}), body == null ? 404 : 200, headers: {'content-type': 'application/json'});
      });

  testWidgets('email sign-in: an optional phone for a new account, and the email code is never shown', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sent = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? respond(String path) => switch (path) {
          // Even if a server sent a code for an email, the app must not show it.
          '/auth/send-otp' => {'identifier': 'aline@example.com', 'identifier_type': 'email', 'sent_to': 'al•••@example.com', 'dev_otp': '999999'},
          '/auth/verify-otp' => {
              'token': 'customer-token',
              'customer': {'id': 'c1', 'name': 'Aline Uwase', 'phone_number': null, 'email': 'aline@example.com', 'email_verified': true, 'pending_phone_number': '+250788000111'},
            },
          _ => null,
        };
    await http.runWithClient(() async {
      final opened = await openSignIn(tester, respond);
      await tester.enterText(find.byType(TextField).at(0), 'aline uwase');
      await tester.enterText(find.byType(TextField).at(1), 'aline@example.com');
      await tester.pumpAndSettle();
      // Typing an email shows the optional phone field for a new account.
      expect(find.text('PHONE NUMBER (OPTIONAL, MTN / AIRTEL)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(2), '0788000111');
      await tester.tap(find.text('Continue & Send OTP'));
      await tester.pumpAndSettle();
      expect(sent['/auth/send-otp'], {'identifier': 'aline@example.com', 'name': 'Aline Uwase', 'phone_number': '0788000111'});
      expect(find.textContaining('We emailed a verification code to', findRichText: true), findsOneWidget);
      expect(find.textContaining('999999'), findsNothing, reason: 'email codes are never shown');
      expect(find.text('Insert code'), findsNothing);

      await tester.enterText(find.byType(TextField).last, '424242');
      await tester.tap(find.text('Verify & Sign In'));
      await tester.pumpAndSettle();
      expect(sent['/auth/verify-otp'], {'identifier': 'aline@example.com', 'code': '424242', 'name': 'Aline Uwase'});
      expect(opened.session.isSignedIn, isTrue);
      expect(opened.session.emailVerified, isTrue);
      expect(opened.session.phone, '', reason: 'an unverified phone is not the account phone');
      expect(opened.session.pendingPhone, '+250788000111');
    }, () => mockFor(sent, respond));
  });

  testWidgets("a phone that belongs to another customer shows the server's message", (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sent = <String, Map<String, dynamic>>{};
    final mock = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      sent[path] = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'PHONE_BELONGS_TO_ANOTHER_CUSTOMER',
            'message': 'This phone number is already associated with another customer account. Please use your own phone number or sign in to your existing account.',
          },
        }),
        409,
        headers: {'content-type': 'application/json'},
      );
    });
    await http.runWithClient(() async {
      await openSignIn(tester, (_) => null);
      await tester.enterText(find.byType(TextField).at(0), 'eric mugisha');
      await tester.enterText(find.byType(TextField).at(1), '0788123456');
      await tester.tap(find.text('Continue & Send OTP'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already associated with another customer account'), findsOneWidget);
      expect(find.text('Verify OTP Code'), findsNothing, reason: 'no code step: the server refused');
    }, () => mock);
  });

  testWidgets("an admin's phone opens the admin step; their email + password open the admin session", (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sent = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? respond(String path) => switch (path) {
          '/auth/send-otp' => {'identifier': '+250788999000', 'phone_number': '+250788999000', 'dev_otp': '111222'},
          // No token: the server only gives a one-time challenge.
          '/auth/verify-otp' => {'admin_verification_required': true, 'challenge_token': 'challenge-abc', 'expires_in_seconds': 300},
          '/admin/auth/phone-login' => {'token': 'admin-token', 'admin': {'id': 'a1', 'email': 'grace@kitchenlink.rw'}},
          _ => null,
        };
    await http.runWithClient(() async {
      final opened = await openSignIn(tester, respond);
      await tester.enterText(find.byType(TextField).at(0), 'grace admin');
      await tester.enterText(find.byType(TextField).at(1), '0788999000');
      await tester.tap(find.text('Continue & Send OTP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert code'));
      await tester.pump();
      await tester.tap(find.text('Verify & Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Administrator Verification'), findsOneWidget);
      expect(opened.session.isSignedIn, isFalse, reason: 'no customer session for the admin step');
      await tester.enterText(find.byType(TextField).at(0), 'grace@kitchenlink.rw');
      await tester.enterText(find.byType(TextField).at(1), 'Admin-Password-2026!');
      await tester.tap(find.text('Verify & open dashboard'));
      await tester.pumpAndSettle();

      expect(sent['/admin/auth/phone-login'], {'challenge_token': 'challenge-abc', 'email': 'grace@kitchenlink.rw', 'password': 'Admin-Password-2026!'});
      expect(await const FlutterSecureStorage().read(key: 'ofk_admin_token'), 'admin-token');
      expect(opened.session.isSignedIn, isFalse);
      expect(find.text('Administrator Verification'), findsNothing);
    }, () => mockFor(sent, respond));
  });

  testWidgets('from the admin step, "Continue as a customer" signs in to the customer account', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final sent = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? respond(String path) => switch (path) {
          '/auth/send-otp' => {'identifier': '+250788999000', 'phone_number': '+250788999000', 'dev_otp': '111222'},
          '/auth/verify-otp' => {'admin_verification_required': true, 'challenge_token': 'challenge-abc', 'expires_in_seconds': 300},
          '/auth/continue-as-customer' => {
              'token': 'customer-token',
              'customer': {'id': 'c9', 'name': 'Grace Admin', 'phone_number': '+250788999000'},
            },
          _ => null,
        };
    await http.runWithClient(() async {
      final opened = await openSignIn(tester, respond);
      await tester.enterText(find.byType(TextField).at(0), 'grace admin');
      await tester.enterText(find.byType(TextField).at(1), '0788999000');
      await tester.tap(find.text('Continue & Send OTP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert code'));
      await tester.pump();
      await tester.tap(find.text('Verify & Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue as a customer instead'));
      await tester.pumpAndSettle();

      expect(sent['/auth/continue-as-customer'], {'challenge_token': 'challenge-abc'});
      expect(opened.session.isSignedIn, isTrue);
      expect(opened.result(), isTrue);
      expect(await const FlutterSecureStorage().read(key: 'ofk_admin_token'), isNull);
    }, () => mockFor(sent, respond));
  });

  test('a new phone is only saved after its code; the old one stays until then', () async {
    FlutterSecureStorage.setMockInitialValues({'ofk_access_token': 't', 'ofk_customer_phone': '+250788123456'});
    final sent = <String, Map<String, dynamic>>{};
    final mock = mockFor(sent, (path) => switch (path) {
          '/auth/me/phone/send-code' => {'pending_phone_number': '+250788555444', 'sent_to': '•••••••••444', 'dev_otp': '313131'},
          '/auth/me/phone/verify' => {
              'customer': {'id': 'c1', 'name': 'Jean Paul', 'phone_number': '+250788555444'},
            },
          _ => null,
        });
    await http.runWithClient(() async {
      final session = CustomerSession(ApiClient(baseUrl: 'http://localhost:4000/api/v1'));
      await session.restore();
      final code = await session.startPhoneChange('0788555444');
      expect(sent['/auth/me/phone/send-code'], {'phone_number': '0788555444'});
      expect(code.devOtp, '313131');
      expect(session.phone, '+250788123456', reason: 'unchanged until verified');
      await session.confirmPhoneChange('313131');
      expect(sent['/auth/me/phone/verify'], {'code': '313131'});
      expect(session.phone, '+250788555444');
    }, () => mock);
  });
}
