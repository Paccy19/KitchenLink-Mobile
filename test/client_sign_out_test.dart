// A signed-in customer can always sign out: from the account menu (even on a
// short phone, where the menu scrolls) and from the profile, after
// confirming; also of all devices.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/customer_session.dart';
import 'package:kitchenlink_mobile/client/market_app.dart';
import 'package:kitchenlink_mobile/client/screens/account_screens.dart';

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _signedIn = {
  'ofk_access_token': 'customer-token',
  'ofk_customer_name': 'Aline Uwase',
  'ofk_customer_phone': '+250788123456',
  // The location question was already answered.
  'ofk_location_primer_v1': 'seen',
};

MockClient _backend(List<String> calls) => MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      calls.add('${request.method} $path');
      final body = switch (path) {
        '/auth/me' => {
            'customer': {'id': 'c1', 'name': 'Aline Uwase', 'phone_number': '+250788123456'},
          },
        '/auth/logout' || '/auth/logout-all' => {'signed_out': true},
        '/notifications' => {'notifications': [], 'unread_count': 0},
        '/orders' => {'orders': []},
        '/cart' => {'items': []},
        '/wishlist' => {'items': []},
        _ => <String, dynamic>{},
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

void main() {
  testWidgets('on a short phone the account menu scrolls to "Sign out", which asks first', (tester) async {
    FlutterSecureStorage.setMockInitialValues(Map.of(_signedIn));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];

    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
        child: const KitchenLinkMarketApp(),
      ));
      await settle(tester);
      final session = tester.element(find.byType(Scaffold).first).read<CustomerSession>();
      expect(session.isSignedIn, isTrue);

      // The account button in the bottom bar opens the account menu.
      await tester.tap(find.text('Aline').last);
      await settle(tester);
      expect(find.text('My profile'), findsOneWidget);

      final signOut = find.text('Sign out');
      await tester.scrollUntilVisible(signOut, 80, scrollable: find.byType(Scrollable).last);
      await tester.tap(signOut);
      await settle(tester, 5);
      // Asks first: cancelling keeps the customer signed in.
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester, 5);
      expect(session.isSignedIn, isTrue);

      await tester.tap(signOut);
      await settle(tester, 5);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await settle(tester);
      expect(session.isSignedIn, isFalse);
      expect(calls, contains('POST /auth/logout'), reason: 'the token is ended on the server too');
      expect(find.text("You're signed out."), findsOneWidget);
      expect(find.text('Sign In'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }, () => _backend(calls));
  });

  testWidgets('the profile offers "Sign out of all devices"', (tester) async {
    FlutterSecureStorage.setMockInitialValues(Map.of(_signedIn));
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];

    await http.runWithClient(() async {
      final client = ApiClient(baseUrl: 'http://localhost:4000/api/v1');
      await tester.pumpWidget(MultiProvider(
        providers: marketProviders(client),
        child: const MaterialApp(home: ProfileScreen()),
      ));
      await settle(tester);
      final session = tester.element(find.byType(ProfileScreen)).read<CustomerSession>();
      await session.restore();
      await settle(tester);
      expect(session.isSignedIn, isTrue);

      final everywhere = find.text('Sign out of all devices');
      await tester.ensureVisible(everywhere);
      await tester.tap(everywhere);
      await settle(tester, 5);
      expect(find.text('Sign out of all devices?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out everywhere'));
      await settle(tester);
      expect(calls, containsAllInOrder(['POST /auth/logout-all', 'POST /auth/logout']));
      expect(session.isSignedIn, isFalse);
      await tester.pumpWidget(const SizedBox());
    }, () => _backend(calls));
  });
}
