// ignore_for_file: invalid_use_of_visible_for_testing_member
// Design review screenshots of the marketplace (not part of `flutter test`):
//   flutter test tool/shots/market_shots_test.dart --update-goldens
// Renders real screens at iPhone size in light and dark mode against a fake
// backend, with photos served from SHOTS_IMAGES (a folder of .jpg files).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/market_app.dart';
import 'package:kitchenlink_mobile/client/market_nav.dart';
import 'package:kitchenlink_mobile/client/screens/cart_sheet.dart';

import 'shots_support.dart';

late String img;

Map<String, Object?> vendor(String id, String name, String type, String area, String photo, {double rating = 4.7, int reviews = 86, bool open = true, bool nearby = false, String? description}) => {
      'id': id,
      'name': name,
      'vendor_type': type,
      'rating': rating,
      'reviews_count': reviews,
      'estimated_prep_time': '20-30',
      'delivery_fee': 1000,
      'neighborhood': area,
      'description': description ?? 'Home-made isombe, brochettes and fresh juice, cooked to order.',
      'is_nearby': nearby,
      'is_open': open,
      'banner_image_url': '$img/$photo.jpg',
    };

Map<String, Object?> dish(String id, String name, int price, String photo, {String vendorId = 'v1', String vendorName = 'Mama Aline\'s Kitchen', double rating = 4.8, String description = 'Cassava leaves slow-cooked with peanut and palm oil.', bool available = true}) => {
      'id': id,
      'name': name,
      'description': description,
      'price_rwf': price,
      'category': 'Local Food',
      'rating': rating,
      'prep_time': 25,
      'is_available': available,
      'image_url': '$img/$photo.jpg',
      'vendor': {'id': vendorId, 'name': vendorName},
    };

List<Map<String, Object?>> get kitchens => [
      vendor('v1', "Mama Aline's Kitchen", 'home_cook', 'Kimironko', 'spread', nearby: true),
      vendor('v2', 'Kigali Grill House', 'restaurant', 'Kacyiru', 'skewers', rating: 4.5, reviews: 210),
      vendor('v3', 'Green Bowl', 'restaurant', 'Remera', 'salad', rating: 4.9, reviews: 54),
      vendor('v4', 'Nyamirambo Bakery', 'bakery', 'Nyamirambo', 'bread', open: false),
    ];

List<Map<String, Object?>> get dishes => [
      dish('d1', 'Isombe & plantain', 2500, 'plate'),
      dish('d2', 'Goat brochettes', 3000, 'skewers', vendorId: 'v2', vendorName: 'Kigali Grill House', description: 'Grilled over charcoal, with chips.'),
      dish('d3', 'Garden bowl', 4500, 'bowl', vendorId: 'v3', vendorName: 'Green Bowl', description: 'Avocado, beans, greens and sesame.'),
      dish('d4', 'Margherita pizza', 6000, 'pizza', vendorId: 'v2', vendorName: 'Kigali Grill House', description: 'Wood-fired, fresh basil.'),
      dish('d5', 'Beef burger', 5500, 'burger', vendorId: 'v2', vendorName: 'Kigali Grill House', available: false),
      dish('d6', 'Fresh salad', 3500, 'salad', vendorId: 'v3', vendorName: 'Green Bowl'),
    ];

class MarketBackend {
  MarketBackend({this.signedIn = false});

  final bool signedIn;
  final cart = <String, int>{'d1': 2, 'd2': 1};

  Map<String, dynamic> get cartPayload => {
        'vendor': {'id': 'v1', 'name': "Mama Aline's Kitchen", 'vendor_type': 'home_cook', 'ordering': null},
        'items': [
          for (final e in cart.entries)
            {
              'menu_item_id': e.key,
              'name': dishes.firstWhere((d) => d['id'] == e.key)['name'],
              'price_rwf': dishes.firstWhere((d) => d['id'] == e.key)['price_rwf'],
              'quantity': e.value,
              'image_url': dishes.firstWhere((d) => d['id'] == e.key)['image_url'],
              'is_available': true,
              'vendor_id': 'v1',
              'vendor_name': "Mama Aline's Kitchen",
            },
        ],
      };

  Map<String, dynamic> order(String id, String status) => {
        'id': id,
        'order_number': 'KL-10$id',
        'status': status,
        'order_type': 'immediate',
        'fulfillment': 'delivery',
        'vendor': {'id': 'v1', 'name': "Mama Aline's Kitchen", 'vendor_type': 'home_cook', 'phone': '+250788000111'},
        'items': [
          {'menu_item_id': 'd1', 'name': 'Isombe & plantain', 'price_rwf': 2500, 'quantity': 2, 'image_url': '$img/plate.jpg'},
          {'menu_item_id': 'd2', 'name': 'Goat brochettes', 'price_rwf': 3000, 'quantity': 1, 'image_url': '$img/skewers.jpg'},
        ],
        'subtotal_rwf': 8000,
        'delivery_fee_rwf': 1200,
        'total_rwf': 9200,
        'payment_method': 'mobile_money',
        'payment_method_label': 'Mobile Money',
        'payment_status': 'paid',
        'payment_details': {'phone': '0788123456'},
        'delivery_location': {'address': 'KG 11 Ave, blue gate', 'neighborhood': 'Kimironko'},
        'delivery': {'proof_of_delivery_code': '482913', 'otp_verified': false},
        'created_at': '2026-11-10T09:00:00Z',
      };

  http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    switch ((request.method, path)) {
      case ('GET', '/home/feed'):
        return _json({
          'categories': [
            for (final (i, n) in ['Local Food', 'Grill', 'Pizza', 'Breakfast', 'Healthy', 'Desserts', 'Drinks'].indexed) {'id': 'c$i', 'name': n},
          ],
          'nearby_vendors': kitchens,
          'popular_dishes': dishes,
        });
      case ('GET', '/home/categories'):
        return _json({'categories': []});
      case ('GET', '/home/vendors'):
        return _json({'vendors': kitchens, 'meta': {'total': 14, 'location_used': false}});
      case ('GET', '/vendors/specials'):
        return _json({
          'specials': [
            {...kitchens[0], 'special': {'text': 'Tomorrow: isombe, rice and beans', 'cutoff_at': '2026-11-12T20:00:00Z', 'delivery_at': '2026-11-13T12:00:00Z'}},
          ],
        });
      case ('GET', '/vendors/offers'):
        return _json({
          'offers': [
            {'id': 'o1', 'title': '20% off brochettes', 'details': 'All day Saturday', 'offer_date': '2026-11-14', 'vendor': kitchens[1]},
          ],
        });
      case ('GET', '/vendors/v1'):
        return _json({
          ...kitchens[0],
          'location': {'neighborhood': 'Kimironko', 'latitude': -1.95, 'longitude': 30.12},
          'menu': [
            {'category': 'Local Food', 'items': [for (final d in dishes.take(3)) {...d, 'vendor': null}]},
            {'category': 'Grill', 'items': [for (final d in dishes.skip(3)) {...d, 'vendor': null}]},
          ],
          'ordering': {'vendor_type': 'home_cook', 'order_now': true, 'min_lead_minutes': 45, 'max_days_ahead': 3, 'daily_order_limit': null, 'min_order_rwf': 0, 'max_items_per_order': 10},
        });
      case ('GET', '/vendors/v1/delivery-quote'):
        return _json({'delivery_fee_rwf': 1200, 'distance_km': 2.5, 'fulfillment': 'delivery'});
      case ('GET', '/cart'):
        return _json(signedIn ? cartPayload : {'vendor': null, 'items': []});
      case ('GET', '/wishlist'):
        return _json({
          'items': [
            for (final d in dishes.take(3)) {'menu_item_id': d['id'], 'name': d['name'], 'price_rwf': d['price_rwf'], 'image_url': d['image_url'], 'is_available': true, 'vendor_id': 'v1', 'vendor_name': "Mama Aline's Kitchen"},
          ],
        });
      case ('GET', '/orders'):
        return _json({'orders': signedIn ? [order('1', 'out_for_delivery'), order('2', 'delivered'), order('3', 'cancelled')] : []});
      case ('GET', '/orders/1'):
        return _json(order('1', 'out_for_delivery'));
      case ('GET', '/orders/1/live'):
        return _json({'active': false});
      case ('GET', '/notifications'):
        return _json({'notifications': [], 'unread_count': 2});
      case ('GET', '/auth/me'):
        return _json({'customer': {'id': 'c1', 'name': 'Aline Uwase', 'phone_number': '+250788123456', 'email': ''}});
      case ('GET', '/chats'):
        return _json({'conversations': []});
      case ('GET', '/support'):
        return _json({'tickets': []});
    }
    return _json({'error': {'message': 'Not found: ${request.method} $path'}}, 404);
  }
}

typedef Step = Future<void> Function(WidgetTester tester, BuildContext context);

Future<void> shoot(WidgetTester tester, String name, {bool dark = false, bool signedIn = true, Step? step, double height = 852}) async {
  FlutterSecureStorage.setMockInitialValues({
    'ofk-theme': dark ? 'dark' : 'light',
    'ofk_saved_location': '-1.95|30.12|manual|Kimironko, Kigali',
    'ofk_location_primer_v1': '1',
    if (signedIn) ...{'ofk_access_token': 't', 'ofk_customer_name': 'Aline Uwase', 'ofk_customer_phone': '+250788123456'},
  });
  final backend = MarketBackend(signedIn: signedIn);
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
      child: const KitchenLinkMarketApp(),
    ));
    await settle(tester);
    if (step != null) {
      await step(tester, tester.element(find.byType(Scaffold).first));
      await settle(tester);
    }
    await loadImages(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name-${dark ? 'dark' : 'light'}.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }, () => MockClient(backend.handle));
}

void main() {
  late ImageServer server;
  setUpAll(() async {
    await loadAppFonts();
    server = await ImageServer.start(Platform.environment['SHOTS_IMAGES'] ?? 'tool/shots/images');
    img = server.base;
  });
  tearDownAll(() => server.close());

  for (final dark in [false, true]) {
    testWidgets('home ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester);
      await shoot(tester, 'home', dark: dark);
    });
    testWidgets('home full ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester, height: 2300);
      await shoot(tester, 'home-full', dark: dark);
    });
    testWidgets('home signed out ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester, width: 360, height: 780);
      await shoot(tester, 'home-small-signed-out', dark: dark, signedIn: false);
    });
    testWidgets('kitchen ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester, height: 1400);
      await shoot(tester, 'kitchen', dark: dark, step: (t, c) async { MarketNav.kitchen(c, 'v1'); });
    });
    testWidgets('basket ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester);
      await shoot(tester, 'basket', dark: dark, step: (t, c) async { showCartSheet(c); });
    });
    testWidgets('orders ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester);
      await shoot(tester, 'orders', dark: dark, step: (t, c) async { MarketNav.orders(c); });
    });
    testWidgets('order ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester, height: 1500);
      await shoot(tester, 'order', dark: dark, step: (t, c) async { MarketNav.order(c, '1'); });
    });
    testWidgets('saved ${dark ? 'dark' : 'light'}', (tester) async {
      phone(tester);
      await shoot(tester, 'saved', dark: dark, step: (t, c) async { MarketNav.wishlist(c); });
    });
  }
}
