// Big-event delivery on the customer side, against the website's endpoints:
// the server says when a venue needs a special delivery; an agreed fee is
// booked as it is (venue and fee locked); quotations are accepted only
// through the server's allowed actions.
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
import 'package:kitchenlink_mobile/client/screens/event_order_screen.dart';
import 'package:kitchenlink_mobile/client/screens/special_delivery_screens.dart';

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _quote({required int guests, required Map<String, dynamic> delivery, int? deliveryFee}) {
  final food = guests * 1000;
  final total = food + (deliveryFee ?? 0);
  return {
    'vendor': {'id': 'v1', 'name': 'Mama Kitchen'},
    'offer': {
      'package': {'id': 'p1', 'name': 'Standard', 'tiers': [], 'menu': []},
      'packages': [],
    },
    'delivery': delivery,
    'quote': {
      'guests': guests,
      'package_id': 'p1',
      'price_per_plate_rwf': 1000,
      'food_total_rwf': food,
      'delivery_fee_rwf': deliveryFee,
      'total_rwf': total,
      'deposit_percent': 50,
      'deposit_rwf': total ~/ 2,
      'balance_rwf': total - total ~/ 2,
      'min_lead_hours': 48,
      'balance_due_hours_before': 24,
    },
  };
}

Future<void> settle(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget home) => MultiProvider(
      providers: marketProviders(ApiClient(baseUrl: 'http://localhost:4000/api/v1')),
      child: MaterialApp(theme: buildClientTheme(), home: home),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a venue outside the automatic pricing asks for a special delivery; no fee is charged', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mock = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      if (path == '/orders/event-quote') {
        return _json(_quote(guests: 150, delivery: {
          'status': 'negotiation_required',
          'message': 'This delivery needs to be arranged with the kitchen.',
          'reason_messages': ["This destination is outside the kitchen's delivery coverage."],
        }));
      }
      return _json({'notifications': [], 'unread_count': 0});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const EventOrderScreen(vendorId: 'v1', guests: 150)));
      await settle(tester);
      expect(find.text('Special delivery needed'), findsOneWidget);
      expect(find.textContaining("outside the kitchen's delivery coverage"), findsOneWidget);
      expect(find.text('Request special delivery'), findsOneWidget);
      expect(find.text("No delivery fee is charged until you accept the kitchen's quotation."), findsOneWidget);
      // The order can't be placed with an unknown delivery fee.
      expect(find.text('Place order'), findsOneWidget);
      expect(find.textContaining('Place order · pay'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => mock);
  });

  testWidgets('booking with an agreed special delivery uses its fee and venue, and sends the agreement', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? checkout;
    final eventAt = DateTime.now().add(const Duration(days: 10)).toUtc().toIso8601String();
    final mock = MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      switch (path) {
        case '/special-deliveries/sd1':
          return _json({
            'id': 'sd1',
            'reference': 'SD-000124',
            'status': 'quotation_accepted',
            'can_checkout': true,
            'agreed_fee_rwf': 50000,
            'event': {'guests': 150, 'package_id': 'p1', 'event_at': eventAt},
            'delivery_location': {'address': 'Musanze Hall', 'latitude': -1.5, 'longitude': 29.6},
          });
        case '/orders/event-quote':
          return _json(_quote(guests: 150, delivery: {'status': 'negotiation_required', 'message': 'Arrange it with the kitchen.'}));
        case '/orders/event-checkout':
          checkout = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'error': {'message': 'stop here'}}, 400);
      }
      return _json({'notifications': [], 'unread_count': 0});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const EventOrderScreen(vendorId: 'v1', guests: 150, agreementId: 'sd1')));
      await settle(tester);
      expect(find.textContaining('Special delivery SD-000124: 50,000 RWF agreed'), findsOneWidget);
      expect(find.text('Special delivery needed'), findsNothing, reason: 'the agreement replaces the request');
      // (150,000 food + 50,000 agreed delivery) × 50 % now.
      expect(find.text('Place order · pay 100,000 RWF now'), findsOneWidget);
      checkout = null;
      await tester.pumpWidget(const SizedBox());
    }, () => mock);
    expect(checkout, isNull);
  });

  testWidgets('a quotation is accepted through its own action, after confirming', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    var status = 'quotation_submitted';
    Map<String, dynamic> request() => {
          'id': 'sd1',
          'reference': 'SD-000124',
          'status': status,
          'status_label': status == 'quotation_accepted' ? 'Quotation accepted' : 'Quotation received',
          'vendor': {'id': 'v1', 'name': 'Mama Kitchen'},
          'event': {'guests': 150},
          'delivery_location': {'address': 'Musanze Hall'},
          'allowed_actions': status == 'quotation_submitted' ? ['accept_quotation', 'request_revision', 'reject_quotation', 'cancel', 'send_message'] : ['send_message'],
          'active_quotation': status == 'quotation_submitted'
              ? {'id': 'q1', 'reference': 'SQ-1', 'version': 1, 'status': 'submitted', 'fee_rwf': 45000, 'arrangements': [{'code': 'own_vehicle', 'label': 'Own vehicle'}]}
              : null,
          'quotations': [],
          'agreed_fee_rwf': status == 'quotation_accepted' ? 45000 : null,
          'can_checkout': status == 'quotation_accepted',
          'chat_open': true,
        };
    final mock = MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1', '');
      calls.add('${req.method} $path');
      if (path == '/special-deliveries/sd1') return _json(request());
      if (path == '/special-deliveries/sd1/quotations/q1/accept') {
        status = 'quotation_accepted';
        return _json(request());
      }
      if (path == '/special-deliveries/sd1/messages') return _json({'messages': [], 'privacy_note': 'Chats are kept.'});
      return _json({});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const SpecialDeliveryScreen(requestId: 'sd1')));
      await settle(tester);
      expect(find.text('45,000 RWF delivery fee'), findsOneWidget);
      await tester.ensureVisible(find.text('Accept 45,000 RWF'));
      await tester.tap(find.text('Accept 45,000 RWF'));
      await settle(tester, 5);
      expect(find.textContaining('This price will be locked'), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await settle(tester);
      expect(calls, contains('POST /special-deliveries/sd1/quotations/q1/accept'));
      expect(find.text('Book the event with this delivery fee'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => mock);
  });
}
