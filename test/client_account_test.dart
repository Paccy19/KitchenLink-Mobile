import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/client_theme.dart';
import 'package:kitchenlink_mobile/client/customer_api.dart';
import 'package:kitchenlink_mobile/client/customer_session.dart';
import 'package:kitchenlink_mobile/client/market_app.dart';
import 'package:kitchenlink_mobile/client/market_models.dart';
import 'package:kitchenlink_mobile/client/market_state.dart';
import 'package:kitchenlink_mobile/client/screens/order_screen.dart';
import 'package:kitchenlink_mobile/client/screens/support_screens.dart';

Map<String, dynamic> _order({String fulfillment = 'delivery', String status = 'preparing'}) => {
      'id': 'o1',
      'order_number': 'KL-2002',
      'status': status,
      'order_type': 'immediate',
      'fulfillment': fulfillment,
      'vendor': {'id': 'v1', 'name': 'Mama Kitchen', 'vendor_type': 'home_cook', 'phone': '+250788000111'},
      'items': [
        {'menu_item_id': 'd1', 'name': 'Isombe', 'price_rwf': 2500, 'quantity': 2},
      ],
      'subtotal_rwf': 5000,
      'delivery_fee_rwf': fulfillment == 'pickup' ? 0 : 1200,
      'total_rwf': fulfillment == 'pickup' ? 5000 : 6200,
      'payment_method_label': 'Mobile Money',
      'payment_status': 'paid',
      'pickup': fulfillment == 'pickup' ? {'code': '771204', 'address': 'KG 9 Ave', 'neighborhood': 'Kimironko', 'latitude': -1.95, 'longitude': 30.12} : null,
      'delivery_location': {'address': 'KG 11 Ave'},
      'created_at': '2026-11-10T09:00:00Z',
    };

class Backend {
  Backend({this.fulfillment = 'delivery'});

  final String fulfillment;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final cart = <String, int>{};
  final messages = <Map<String, dynamic>>[
    {'id': 'm1', 'body': 'Hello! Your isombe is on the stove.', 'mine': false, 'created_at': '2026-11-10T09:05:00Z'},
  ];
  final ticketMessages = <Map<String, dynamic>>[];

  http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, dynamic> get _ticket => {
        'id': 't1',
        'subject': 'Cold food',
        'reference': 'SUP-1',
        'category': 'order',
        'status': 'open',
        'status_label': 'Open',
        'messages': ticketMessages,
      };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    final key = '${request.method} $path';
    calls.add(key);
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    bodies[key] = body;
    switch (key) {
      case 'GET /auth/me':
        return _json({'customer': {'id': 'c1', 'name': 'Aline Uwase', 'phone_number': '+250788123456'}});
      case 'GET /orders':
        return _json({'orders': [_order(fulfillment: fulfillment)]});
      case 'GET /orders/o1':
        return _json(_order(fulfillment: fulfillment));
      case 'GET /orders/o1/live':
        return _json({'active': false});
      case 'GET /cart':
        return _json({'items': []});
      case 'POST /cart':
        cart.update('${body['menu_item_id']}', (q) => q + (body['quantity'] as int), ifAbsent: () => body['quantity'] as int);
        return _json({
          'vendor': {'id': 'v1', 'name': 'Mama Kitchen', 'vendor_type': 'home_cook'},
          'items': [
            for (final e in cart.entries) {'menu_item_id': e.key, 'name': 'Isombe', 'price_rwf': 2500, 'quantity': e.value, 'vendor_id': 'v1', 'is_available': true},
          ],
        });
      case 'GET /vendors/v1/delivery-quote':
        return _json({'delivery_fee_rwf': 1200, 'distance_km': 2.5, 'fulfillment': 'delivery'});
      case 'GET /wishlist':
        return _json({'items': []});
      case 'GET /notifications':
        return _json({'notifications': [], 'unread_count': 0});
      case 'POST /chats/with/v1':
        return _json({'conversation': {'id': 'ch1'}});
      case 'GET /chats/ch1':
        return _json({
          'conversation': {'id': 'ch1', 'with': {'id': 'v1', 'name': 'Mama Kitchen', 'vendor_type': 'home_cook'}},
          'messages': request.url.queryParameters.containsKey('after') ? [] : messages,
          'has_more': false,
        });
      case 'POST /chats/ch1/read':
        return _json({'ok': true});
      case 'POST /chats/ch1/messages':
        final message = {'id': 'm${messages.length + 1}', 'body': body['body'], 'mine': true, 'created_at': '2026-11-10T09:06:00Z'};
        messages.add(message);
        return _json({'message': message});
      case 'GET /support':
        return _json({'tickets': ticketMessages.isEmpty ? [] : [_ticket]});
      case 'POST /support':
        ticketMessages.add({'id': 's1', 'from': 'you', 'body': body['message'], 'at': '2026-11-10T09:10:00Z'});
        return _json({'ticket': _ticket});
      case 'GET /support/t1':
        return _json({'ticket': _ticket});
      case 'POST /support/t1/messages':
        ticketMessages.add({'id': 's2', 'from': 'you', 'body': body['message'], 'at': '2026-11-10T09:11:00Z'});
        return _json({'ticket': _ticket});
    }
    return _json({'error': {'message': 'Not found: $key'}}, 404);
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

Future<void> pumpSignedIn(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'ofk_access_token': 't0ken', 'ofk_customer_name': 'Aline Uwase', 'ofk_customer_phone': '+250788123456'});
  await tester.pumpWidget(MultiProvider(
    providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
    child: MaterialApp(theme: buildClientTheme(), home: home),
  ));
  await settle(tester);
}

void main() {
  signInThenOrderTest();

  testWidgets('order history: track, message the kitchen, and reorder into checkout', (tester) async {
    final backend = Backend();
    await http.runWithClient(() async {
      await pumpSignedIn(tester, const OrdersScreen());
      expect(find.text('Mama Kitchen'), findsOneWidget);
      expect(find.textContaining('Preparing your food'), findsOneWidget);
      expect(find.text('Track Live'), findsOneWidget);

      // Message the kitchen: the chat opens with its messages, and sending works.
      await tapText(tester, 'Message kitchen');
      expect(backend.calls, contains('POST /chats/with/v1'));
      expect(find.text('Hello! Your isombe is on the stove.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Thank you!');
      await settle(tester, 3);
      await tester.tap(find.byTooltip('Send message'));
      await settle(tester);
      expect(backend.bodies['POST /chats/ch1/messages'], {'body': 'Thank you!'});
      expect(find.text('Thank you!'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      // Reorder: the dishes go into the basket and checkout opens.
      await tapText(tester, 'Reorder Dishes');
      expect(backend.cart, {'d1': 2});
      expect(find.text('Checkout & Confirmation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(backend.handle));
  });

  testWidgets('a pickup order shows its pickup code, directions and "get it delivered"', (tester) async {
    final backend = Backend(fulfillment: 'pickup');
    await http.runWithClient(() async {
      await pumpSignedIn(tester, const OrderScreen(orderId: 'o1'));
      expect(find.text('YOUR PICKUP CODE'), findsOneWidget);
      expect(find.text('771204'), findsOneWidget);
      expect(find.text("Can't collect? Get it delivered"), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget, reason: 'no delivery fee when you pick up');
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(backend.handle));
  });

  testWidgets('help & support: a new request about an order, then a reply', (tester) async {
    final backend = Backend();
    await http.runWithClient(() async {
      await pumpSignedIn(tester, const SupportScreen());
      expect(find.text('No conversations yet'), findsOneWidget);
      await tapText(tester, 'New request');
      await tester.enterText(find.widgetWithText(TextField, 'e.g. My order arrived cold'), 'Cold food');
      await tester.enterText(find.widgetWithText(TextField, 'Give as many details as you can.'), 'The isombe arrived cold.');
      await settle(tester, 3);
      await tapText(tester, 'Send to support');
      expect(backend.bodies['POST /support'], {'subject': 'Cold food', 'category': 'order', 'message': 'The isombe arrived cold.'});
      expect(find.text('The isombe arrived cold.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Any news?');
      await settle(tester, 3);
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);
      expect(backend.bodies['POST /support/t1/messages'], {'message': 'Any news?'});
      expect(find.text('Any news?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient(backend.handle));
  });

  group('ordering rules and payment checks (same as the website)', () {
    test('caterers take advance orders only, with a minimum order', () {
      final rules = OrderingRules.from(null, 'caterer');
      expect(rules.orderNow, isFalse);
      expect(rules.lines.first, 'Advance orders only · at least 1 day ahead');
      expect(rules.basketProblem(subtotal: 15000, itemCount: 3), 'This kitchen takes orders from 20,000 RWF — add 5,000 RWF more.');
      expect(rules.basketProblem(subtotal: 25000, itemCount: 3), isNull);
      // A caterer needs a day's notice: no slot is left today.
      expect(scheduleDays(rules).map((d) => d.value), isNot(contains('Today')));
    });

    test('the API ordering object wins over the type defaults', () {
      final rules = OrderingRules.from({'vendor_type': 'home_cook', 'order_now': true, 'max_items_per_order': 2, 'fully_booked_today': true}, null);
      expect(rules.basketProblem(subtotal: 5000, itemCount: 3), 'This kitchen takes up to 2 dishes per order — remove 1.');
      expect(rules.fullyBookedToday, isTrue);
    });

    test('payment details are checked before an order is sent', () {
      expect(buildPaymentDetails('mobile_money', phone: '0721234567').error, contains('MTN or Airtel'));
      expect(buildPaymentDetails('mobile_money', phone: '+250 788 123 456').details, {'phone': '0788123456'});
      expect(buildPaymentDetails('wallet', phone: '0721234567').details, {'phone': '0721234567'});
      expect(buildPaymentDetails('card', cardNumber: '4242 4242 4242 4242', cardExpiry: '13/27', cardCvv: '123').error, 'Enter the card expiry as MM/YY.');
      expect(buildPaymentDetails('card', cardNumber: '4242 4242 4242 4242', cardExpiry: '12/27', cardCvv: '123').details, {'card_number': '4242424242424242', 'card_expiry': '12/27'});
    });

    test('a basket line sums into the subtotal and the scheduled time is built locally', () {
      final at = buildScheduledFor('Tomorrow', '06:30 PM');
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect((at.day, at.hour, at.minute), (tomorrow.day, 18, 30));
      expect(numTextOf(2.5), '2.5');
      expect(numTextOf(3), '3');
    });
  });
}

/// The bug in the screenshot: signed in on screen, but the order request went
/// out without the token ("Missing bearer token"). Signing in must give every
/// customer request the token.
void signInThenOrderTest() {
  testWidgets('signing in with the SMS code sends the token with the order', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = <String, String?>{};
    final mock = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      auth['${request.method} $path'] = request.headers['Authorization'];
      final body = switch (path) {
        '/auth/verify-otp' => {'token': 'fresh-token', 'customer': {'name': 'Aline', 'phone_number': '+250788123456'}},
        '/orders/checkout' => _order(),
        _ => <String, dynamic>{},
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
        child: const MaterialApp(home: SizedBox()),
      ));
      await settle(tester, 3);
      final context = tester.element(find.byType(SizedBox));
      await context.read<CustomerSession>().verifyOtp('0788123456', '123456', 'Aline');
      await context.read<CustomerApi>().checkout({'payment_method': 'mobile_money'});
      expect(auth['POST /orders/checkout'], 'Bearer fresh-token');
      await tester.pumpWidget(const SizedBox());
    }, () => mock);
  });
}
