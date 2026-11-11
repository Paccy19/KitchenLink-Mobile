import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/client_theme.dart';
import 'package:kitchenlink_mobile/client/market_app.dart';

Map<String, Object?> vendor(String id, String name) => {
      'id': id,
      'name': name,
      'vendor_type': 'home_cook',
      'rating': 4.5,
      'reviews_count': 12,
      'estimated_prep_time': '20-30',
      'delivery_fee': 1000,
      'neighborhood': 'Kimironko',
      'description': 'Home-made isombe and brochettes.',
      'is_nearby': true,
    };

final responses = <String, Object?>{
  '/home/feed': {
    'categories': [
      {'id': 'c1', 'name': 'Local Food'},
      {'id': 'c2', 'name': 'Fast Food'},
    ],
    'nearby_vendors': [vendor('v1', 'Mama Kitchen'), vendor('v2', 'Kigali Grill House With A Long Name')],
    'popular_dishes': [
      {'id': 'd1', 'name': 'Isombe with plantain', 'price': 2500, 'category': 'Local', 'rating': 4.8, 'prep_time': 25, 'vendor': {'id': 'v1', 'name': 'Mama Kitchen'}},
    ],
  },
  '/home/categories': {'categories': []},
  '/home/vendors': {
    'vendors': [vendor('v1', 'Mama Kitchen')],
    'meta': {'total': 14, 'location_used': false},
  },
  '/vendors/specials': {
    'specials': [
      {
        ...vendor('v1', 'Mama Kitchen'),
        'special': {'text': 'Tomorrow: Isombe and rice', 'cutoff_at': '2026-11-05T20:00:00Z', 'delivery_at': '2026-11-06T12:00:00Z'},
      },
    ],
  },
  '/vendors/offers': {
    'offers': [
      {'id': 'o1', 'title': '20% off brochettes', 'details': 'All day', 'offer_date': '2026-11-08', 'vendor': vendor('v2', 'Kigali Grill')},
    ],
  },
  '/home/search': {
    'dishes': [
      {'id': 'd1', 'name': 'Pizza Margherita', 'price': 6000, 'vendor': {'id': 'v2', 'name': 'Kigali Grill'}},
    ],
    'vendors': [],
  },
};

void main() {
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets('marketplace home renders at $width px', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final mock = MockClient((request) async {
        final body = responses[request.url.path.replaceFirst('/api/v1', '')];
        return http.Response(jsonEncode(body ?? {}), body == null ? 404 : 200, headers: {'content-type': 'application/json'});
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(MultiProvider(
          providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
          child: const KitchenLinkMarketApp(),
        ));
        await settle(tester);

        // First visit: the location primer.
        expect(find.text('Find kitchens near you'), findsOneWidget);
        await tester.tap(find.text('Continue with Kigali city centre'));
        await settle(tester);

        for (final text in [
          'Categories',
          'Top Deals Near You',
          'All Kitchens',
          "Tomorrow's Specials",
          'Popular Dishes Near You',
          'Isombe with plantain',
          'Add to basket',
          'Pre-order now',
          '20% off brochettes',
          "Pre-order tomorrow's dishes",
        ]) {
          expect(find.textContaining(text, findRichText: true), findsWidgets, reason: text);
        }
        // Section links are a "›" whose label is the tooltip.
        expect(find.byTooltip('See all 14'), findsOneWidget);
        // The bottom bar, with the raised basket button.
        expect(find.bySemanticsLabel('Basket, 0 dishes'), findsOneWidget);
        for (final label in ['Home', 'Kitchens', 'Saved', 'Sign In']) {
          expect(find.text(label), findsWidgets, reason: label);
        }

        // Location picker.
        await tester.tap(find.text('Kigali City Centre'));
        await settle(tester);
        expect(find.text('Delivery location'), findsOneWidget);
        await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Kimironko')));
        await settle(tester);
        expect(find.text('Kimironko, Kigali'), findsOneWidget);

        // Search.
        await tester.tap(find.byType(TextField));
        await settle(tester);
        expect(find.text('TRY SEARCHING FOR'), findsOneWidget);
        await tester.tap(find.text('Pizza'));
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester);
        expect(find.text('Pizza Margherita'), findsOneWidget);

        // No website footer in the app.
        expect(find.text('FOR FOOD LOVERS'), findsNothing);
        expect(find.textContaining('All rights reserved'), findsNothing);
      }, () => mock);
    });
  }

  group('dark mode', () {
    Future<void> openHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
        child: const KitchenLinkMarketApp(),
      ));
      await settle(tester);
      await tester.tap(find.text('Continue with Kigali city centre'));
      await settle(tester);
    }

    Color pageColor(WidgetTester tester) => tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;
    Color? textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text).first).style?.color;

    final mock = MockClient((request) async {
      final body = responses[request.url.path.replaceFirst('/api/v1', '')];
      return http.Response(jsonEncode(body ?? {}), body == null ? 404 : 200, headers: {'content-type': 'application/json'});
    });

    testWidgets('the moon button switches the marketplace to dark and back, and remembers it', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await http.runWithClient(() async {
        await openHome(tester);
        expect(K.dark, isFalse);
        final lightText = textColor(tester, 'Categories');

        await tester.tap(find.byIcon(Icons.dark_mode_outlined));
        await settle(tester);

        expect(K.dark, isTrue);
        expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
        expect(pageColor(tester).computeLuminance(), lessThan(0.05), reason: 'chocolate page background');
        // Text inside const widgets is rebuilt too: light on dark.
        expect(textColor(tester, 'Categories'), isNot(lightText));
        expect(textColor(tester, 'Categories')!.computeLuminance(), greaterThan(0.8));
        expect(await const FlutterSecureStorage().read(key: MarketTheme.storageKey), 'dark');

        await tester.tap(find.byIcon(Icons.light_mode_outlined));
        await settle(tester);
        expect(K.dark, isFalse);
        expect(textColor(tester, 'Categories'), lightText);
        expect(await const FlutterSecureStorage().read(key: MarketTheme.storageKey), 'light');
      }, () => mock);
    });

    testWidgets('a saved dark choice opens the marketplace in dark', (tester) async {
      FlutterSecureStorage.setMockInitialValues({MarketTheme.storageKey: 'dark'});
      await http.runWithClient(() async {
        await openHome(tester);
        expect(K.dark, isTrue);
        expect(pageColor(tester).computeLuminance(), lessThan(0.05));
        expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      }, () => mock);
    });
  });
}

/// Lets requests finish and animations play without waiting for endless ones.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
