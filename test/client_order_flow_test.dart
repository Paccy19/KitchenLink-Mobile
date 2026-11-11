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
import 'package:kitchenlink_mobile/client/market_models.dart';
import 'package:kitchenlink_mobile/client/market_state.dart';
import 'package:kitchenlink_mobile/client/screens/event_order_screen.dart';
import 'package:kitchenlink_mobile/client/screens/kitchen_screen.dart';

/// A small in-memory backend with the customer endpoints the website uses.
class FakeBackend {
  final cart = <String, int>{};
  final wishlist = <String>{};
  final calls = <String>[];
  final authorizationHeaders = <String?>[];
  Map<String, dynamic>? checkoutBody;
  String orderStatus = 'placed';
  bool failNextCartAdd = false;

  static const dish = {
    'id': 'd1',
    'name': 'Isombe',
    'description': 'Cassava leaves',
    'price_rwf': 2500,
    'is_available': true,
    'image_url': null,
  };

  Map<String, dynamic> get cartPayload => {
    'vendor': cart.isEmpty
        ? null
        : {
            'id': 'v1',
            'name': 'Mama Kitchen',
            'vendor_type': 'home_cook',
            'ordering': null,
          },
    'items': [
      for (final e in cart.entries)
        {
          'menu_item_id': e.key,
          'name': 'Isombe',
          'price_rwf': 2500,
          'quantity': e.value,
          'image_url': null,
          'is_available': true,
          'vendor_id': 'v1',
          'vendor_name': 'Mama Kitchen',
        },
    ],
  };

  Map<String, dynamic> get order => {
    'id': 'o1',
    'order_number': 'KL-1001',
    'status': orderStatus,
    'order_type': 'immediate',
    'fulfillment': 'delivery',
    'vendor': {
      'id': 'v1',
      'name': 'Mama Kitchen',
      'vendor_type': 'home_cook',
      'phone': '+250788000111',
    },
    'items': [
      {
        'menu_item_id': 'd1',
        'name': 'Isombe',
        'price_rwf': 2500,
        'quantity': 2,
      },
    ],
    'subtotal_rwf': 5000,
    'delivery_fee_rwf': 1200,
    'total_rwf': 6200,
    'payment_method': 'mobile_money',
    'payment_method_label': 'Mobile Money',
    'payment_status': orderStatus == 'cancelled' ? 'refunded' : 'paid',
    'payment_details': {'phone': '0788123456'},
    'delivery_location': {
      'address': 'KG 11 Ave, blue gate',
      'neighborhood': 'Kimironko',
    },
    'delivery': {'proof_of_delivery_code': '482913', 'otp_verified': false},
    if (orderStatus == 'cancelled')
      'refund': {
        'status': 'pending',
        'status_label': 'Refund on its way',
        'amount_rwf': 6200,
        'destination': {
          'type': 'mobile_money',
          'label': 'Mobile Money 0788123456',
        },
        'expected_within_hours': 24,
      },
    'created_at': '2026-11-10T09:00:00Z',
  };

  http.Response _json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    final method = request.method;
    calls.add('$method $path');
    authorizationHeaders.add(
      request.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'authorization')
          .map((entry) => entry.value)
          .firstOrNull,
    );
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    switch ((method, path)) {
      case ('GET', '/auth/me'):
        return _json({
          'customer': {
            'id': 'c1',
            'name': 'Aline Uwase',
            'phone_number': '+250788123456',
            'email': '',
          },
        });
      case ('GET', '/vendors/v1'):
        return _json({
          'id': 'v1',
          'name': 'Mama Kitchen',
          'vendor_type': 'home_cook',
          'rating': 4.6,
          'estimated_prep_time': 30,
          'delivery_available': true,
          'is_open': true,
          'location': {
            'neighborhood': 'Kimironko',
            'latitude': -1.95,
            'longitude': 30.12,
          },
          'menu': [
            {
              'category': 'Local Food',
              'items': [dish],
            },
          ],
          'ordering': {
            'vendor_type': 'home_cook',
            'order_now': true,
            'min_lead_minutes': 45,
            'max_days_ahead': 3,
            'daily_order_limit': null,
            'min_order_rwf': 0,
            'max_items_per_order': 10,
          },
        });
      case ('GET', '/vendors/v1/delivery-quote'):
        return _json({
          'delivery_fee_rwf': 1200,
          'distance_km': 2.5,
          'fulfillment': 'delivery',
        });
      case ('GET', '/cart'):
        return _json(cartPayload);
      case ('POST', '/cart'):
        if (failNextCartAdd) {
          failNextCartAdd = false;
          return _json({
            'error': {'message': 'Dish is no longer available.'},
          }, 409);
        }
        cart.update(
          '${body['menu_item_id']}',
          (q) => q + (body['quantity'] as int),
          ifAbsent: () => body['quantity'] as int,
        );
        return _json(cartPayload);
      case ('PATCH', '/cart/d1'):
        cart['d1'] = body['quantity'] as int;
        return _json(cartPayload);
      case ('GET', '/wishlist'):
        return _json({'items': []});
      case ('POST', '/wishlist'):
        wishlist.add('${body['menu_item_id']}');
        return _json({
          'items': [
            for (final id in wishlist)
              {
                'menu_item_id': id,
                'name': 'Isombe',
                'price_rwf': 2500,
                'is_available': true,
                'vendor_id': 'v1',
                'vendor_name': 'Mama Kitchen',
              },
          ],
        });
      case ('GET', '/orders'):
        return _json({
          'orders': checkoutBody == null ? [] : [order],
        });
      case ('POST', '/orders/checkout'):
        checkoutBody = body;
        cart.clear();
        return _json(order);
      case ('GET', '/orders/o1'):
        return _json(order);
      case ('GET', '/orders/o1/live'):
        return _json({'active': false});
      case ('POST', '/orders/o1/cancel'):
        orderStatus = 'cancelled';
        return _json(order);
      case ('GET', '/notifications'):
        return _json({'notifications': [], 'unread_count': 0});
      case ('POST', '/orders/event-quote'):
        final guests = body['guests'] as int;
        final foodTotal = guests * 1000;
        return _json({
          'vendor': {'id': 'v1', 'name': 'Mama Kitchen'},
          'offer': {
            'package': {
              'id': 'p1',
              'name': 'Standard',
              'tiers': [],
              'menu': [],
            },
            'packages': [],
          },
          'quote': {
            'guests': guests,
            'package_id': 'p1',
            'price_per_plate_rwf': 1000,
            'food_total_rwf': foodTotal,
            'delivery_fee_rwf': 0,
            'total_rwf': foodTotal,
            'deposit_percent': 50,
            'deposit_rwf': foodTotal ~/ 2,
            'balance_rwf': foodTotal ~/ 2,
            'min_lead_hours': 48,
            'balance_due_hours_before': 24,
          },
        });
    }
    return _json({
      'error': {'message': 'Not found: $method $path'},
    }, 404);
  }
}

Future<void> settle(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await settle(tester, 3);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets(
    'changing event quote inputs hides the previous price immediately',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({});
      final backend = FakeBackend();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: marketProviders(
              ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
            ),
            child: MaterialApp(
              theme: buildClientTheme(),
              home: const EventOrderScreen(
                vendorId: 'v1',
                guests: 150,
                pickup: true,
              ),
            ),
          ),
        );
        await settle(tester);
        expect(
          backend.calls,
          contains('POST /orders/event-quote'),
          reason: 'backend calls: ${backend.calls}',
        );
        expect(find.text('Place order · pay 75,000 RWF now'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'e.g. 150'),
          '200',
        );
        await tester.pump();
        expect(find.text('Place order · pay 75,000 RWF now'), findsNothing);
        expect(
          backend.calls.where((call) => call == 'POST /orders/event-quote'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(backend.handle));
    },
  );

  test('card details reject an invalid checksum and an expired card', () {
    expect(
      buildPaymentDetails(
        'card',
        cardNumber: '4242 4242 4242 4241',
        cardExpiry: '12/30',
        cardCvv: '123',
      ).error,
      isNotNull,
    );
    final now = DateTime.now();
    final expiredMonth = now.month == 1 ? 12 : now.month - 1;
    final expiredYear = now.month == 1 ? now.year - 1 : now.year;
    final expiry =
        '${expiredMonth.toString().padLeft(2, '0')}/${(expiredYear % 100).toString().padLeft(2, '0')}';
    expect(
      buildPaymentDetails(
        'card',
        cardNumber: '4242 4242 4242 4242',
        cardExpiry: expiry,
        cardCvv: '123',
      ).error,
      'This card has expired.',
    );
  });

  testWidgets(
    'a signed-in customer orders from a kitchen page, tracks the order and cancels it',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({
        'ofk_access_token': 't0ken',
        'ofk_customer_name': 'Aline Uwase',
        'ofk_customer_phone': '+250788123456',
      });
      final backend = FakeBackend();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: marketProviders(
              ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
            ),
            child: MaterialApp(
              theme: buildClientTheme(),
              home: const KitchenScreen(vendorId: 'v1'),
            ),
          ),
        );
        await settle(tester);
        expect(backend.authorizationHeaders, contains('Bearer t0ken'));

        // The kitchen page: details, how it takes orders, the menu.
        expect(find.text('Mama Kitchen'), findsWidgets);
        expect(find.text('Orders for now or later'), findsOneWidget);
        expect(find.text('Isombe'), findsOneWidget);

        // Save the dish, then add it twice.
        await tester.tap(find.byIcon(Icons.favorite_border).first);
        await settle(tester);
        expect(backend.wishlist, {'d1'});
        await tapText(tester, 'Add');
        await tapText(tester, 'Add');
        expect(backend.cart, {
          'd1': 2,
        }, reason: 'the account basket follows the screen');
        expect(find.text('View Cart · 2'), findsOneWidget);

        // The basket: totals with the distance-priced delivery fee.
        await tapText(tester, 'View Cart · 2');
        expect(find.text('Your basket'), findsOneWidget);
        expect(find.text('Delivery fee (2.5 km)'), findsOneWidget);
        expect(find.text('6,200 RWF'), findsOneWidget);
        await tapText(tester, 'Proceed to Checkout');

        // Checkout: no address yet, so placing the order asks for one.
        expect(find.text('Checkout & Confirmation'), findsOneWidget);
        await tapText(tester, 'Place order · 6,200 RWF');
        expect(
          find.text(
            'Add or select a delivery address before placing your order.',
          ),
          findsOneWidget,
        );
        expect(backend.checkoutBody, isNull);

        await tapText(tester, 'Add Location');
        await tester.enterText(
          find.widgetWithText(TextField, 'Area (any part of Kigali)'),
          'Kimironko',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Street name / Landmark'),
          'KG 11 Ave, blue gate',
        );
        await settle(tester, 3);
        await tapText(tester, 'Save');
        expect(find.textContaining('KG 11 Ave, blue gate'), findsOneWidget);

        // The Mobile Money number starts as the account's number.
        expect(find.widgetWithText(TextField, '0788123456'), findsOneWidget);
        await tapText(tester, 'Place order · 6,200 RWF');
        await settle(tester, 20);

        final sent = backend.checkoutBody!;
        expect(sent['payment_method'], 'mobile_money');
        expect(sent['payment_details'], {'phone': '0788123456'});
        expect(sent['fulfillment'], 'delivery');
        expect(sent['order_type'], 'immediate');
        expect(
          (sent['delivery_location'] as Map)['address'],
          'KG 11 Ave, blue gate',
        );
        expect((sent['delivery_location'] as Map)['neighborhood'], 'Kimironko');

        // The order page: status, the delivery code, the receipt.
        expect(find.text('Order KL-1001'), findsOneWidget);
        expect(find.text('Order placed'), findsWidgets);
        expect(find.text('482913'), findsOneWidget);
        expect(find.text('Order Receipt'), findsOneWidget);
        expect(
          tester.element(find.byType(Scaffold).last).read<Cart>().lines,
          isEmpty,
          reason: 'the basket empties after ordering',
        );

        // Cancel: the refund shows.
        await tapText(tester, 'Cancel order');
        await tapText(tester, 'Cancel order');
        expect(backend.calls, contains('POST /orders/o1/cancel'));
        expect(find.text('Order cancelled'.toUpperCase()), findsOneWidget);
        expect(find.textContaining('Refund on its way'), findsOneWidget);

        // Unmount so the order and notification polling stops.
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(backend.handle));
    },
  );

  testWidgets(
    'a guest basket is kept on the device and a dish from another kitchen asks first',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({});
      final backend = FakeBackend();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: marketProviders(
              ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
            ),
            child: MaterialApp(
              theme: buildClientTheme(),
              home: const KitchenScreen(vendorId: 'v1'),
            ),
          ),
        );
        await settle(tester);
        await tapText(tester, 'Add');
        expect(
          backend.calls.where((c) => c.startsWith('POST /cart')),
          isEmpty,
          reason: 'a guest basket stays on the device',
        );
        final cart = tester.element(find.byType(KitchenScreen)).read<Cart>();
        expect(cart.itemCount, 1);
        expect(
          await const FlutterSecureStorage().read(key: 'ofk_cart'),
          contains('Isombe'),
        );

        // Another kitchen's dish: "Start a new basket?" — keep, then replace.
        expect(cart.vendor!.id, 'v1');
        final brochette = MenuDish.fromJson({
          'id': 'd9',
          'name': 'Brochette',
          'price_rwf': 1500,
        });
        const grill = KitchenRef(id: 'v2', name: 'Kigali Grill');
        expect(cart.add(brochette, grill), AddResult.conflict);
        expect(cart.conflict, isNotNull);
        cart.cancelConflict();
        expect(
          cart.itemCount,
          1,
          reason: 'keeping the current basket changes nothing',
        );
        expect(cart.vendor!.id, 'v1');

        cart.add(brochette, grill);
        cart.replaceWith();
        await settle(tester, 3);
        expect(cart.vendor!.id, 'v2');
        expect(cart.lines.map((l) => l.name), ['Brochette']);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(backend.handle));
    },
  );

  testWidgets(
    'a failed account basket update blocks checkout until a successful retry',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({
        'ofk_access_token': 't0ken',
        'ofk_customer_name': 'Aline Uwase',
        'ofk_customer_phone': '+250788123456',
      });
      final backend = FakeBackend()..failNextCartAdd = true;

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: marketProviders(
              ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
            ),
            child: MaterialApp(
              theme: buildClientTheme(),
              home: const KitchenScreen(vendorId: 'v1'),
            ),
          ),
        );
        await settle(tester);
        final cart = tester.element(find.byType(KitchenScreen)).read<Cart>();

        await tapText(tester, 'Add');
        await settle(tester);
        expect(await cart.waitForSync(), isFalse);
        expect(
          cart.lines,
          isEmpty,
          reason: 'the failed add is replaced by the server basket',
        );

        await tapText(tester, 'Add');
        await settle(tester);
        expect(await cart.waitForSync(), isTrue);
        expect(cart.itemCount, 1);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(backend.handle));
    },
  );
}
