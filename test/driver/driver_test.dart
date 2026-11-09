import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_client.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/driver/app/driver_app.dart';
import 'package:kitchenlink_mobile/driver/app/driver_router.dart';
import 'package:kitchenlink_mobile/driver/application/location.dart';
import 'package:kitchenlink_mobile/driver/application/session.dart';
import 'package:kitchenlink_mobile/driver/models/delivery.dart';
import 'package:kitchenlink_mobile/driver/models/driver_account.dart';
import 'package:kitchenlink_mobile/driver/models/navigation.dart';
import 'package:kitchenlink_mobile/driver/presentation/widgets/slide_to_confirm.dart';
import 'package:kitchenlink_mobile/features/support/application/support_providers.dart';
import 'package:kitchenlink_mobile/features/wallet/application/wallet_providers.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.route);
  final ResponseBody Function(RequestOptions) route;
  final List<RequestOptions> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    log.add(options);
    return route(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});

// Shapes copied from a live run against the reference backend.
Map<String, dynamic> _driver({bool online = false}) => {
      'id': 'd1', 'name': 'Eric Uwimana', 'phone': '+250788100001', 'email': null,
      'vehicle_type': 'motorcycle', 'plate_number': 'RC 123 A', 'rating': 5, 'rating_count': 0,
      'is_online': online, 'status': online ? 'online' : 'offline', 'active_deliveries_count': 0,
      'max_active_deliveries': 3, 'completed_deliveries': 0, 'total_earnings_rwf': 0,
      'available_balance_rwf': 0, 'profile_image_url': null, 'verification_status': 'approved',
      'current_location': {'latitude': -1.9441, 'longitude': 30.0619, 'updated_at': null},
    };

Map<String, dynamic> _delivery({
  String status = 'assigned_to_driver',
  List<String> next = const ['picked_up', 'ready_for_pickup', 'cancelled'],
  bool kitchenReady = true,
}) =>
    {
      'id': 'del1', 'order_id': 'o1', 'order_number': 'OFK-20261109-A00343', 'status': status,
      'status_label': 'Assigned to a delivery worker', 'allowed_next_statuses': next,
      'vendor': {'id': 'v1', 'name': 'Shape Kitchen', 'phone': '+250784324560', 'address': 'KN 3 Rd, Kigali', 'neighborhood': 'Nyarugenge', 'latitude': -1.9441, 'longitude': 30.0619},
      'customer': {'id': 'c1', 'name': 'Shape Customer', 'phone_number': '+250785324560'},
      'pickup_location': {'address': 'KN 3 Rd, Kigali', 'neighborhood': 'Nyarugenge', 'latitude': -1.9441, 'longitude': 30.0619},
      'delivery_location': {'address': 'KN 5 Rd, Kigali', 'neighborhood': '', 'note': 'Blue gate', 'latitude': -1.95, 'longitude': 30.07},
      'route_distance_km': 1.4, 'distance_from_driver_km': 0.3, 'delivery_fee_rwf': 800,
      'promised_earnings_rwf': 800, 'paid_earnings_rwf': null, 'payment_method': 'mobile_money',
      'otp_required': true, 'kitchen_ready': kitchenReady, 'expected_ready_at': null,
      'pickup_due_at': '2026-11-09T07:43:45.547Z', 'pickup_reassign_at': '2026-11-09T07:58:45.547Z',
      'pickup_rules': {'warning_minutes': 10, 'charge_after_minutes': 15, 'reassign_after_minutes': 30},
      'late_pickup': null,
      'order_progress': {'status': 'assigned', 'label': 'Assigned', 'history': [
        {'status': 'placed', 'label': 'Order placed', 'at': '2026-11-09T07:28:45.365Z', 'note': ''},
      ]},
      'items': [
        {'name': 'Isombe', 'price_rwf': 2500, 'quantity': 2, 'options': [{'name': 'Extra spicy'}]},
      ],
    };

({ProviderContainer container, _Adapter adapter, MemoryTokenStore store}) _setup(
  ResponseBody Function(RequestOptions) route, {
  String? token,
}) {
  final adapter = _Adapter(route);
  final store = MemoryTokenStore(token);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  final container = ProviderContainer(overrides: [
    // The app's own /driver paths; the token store is replaced with memory.
    ...driverOverrides.skip(1),
    tokenStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWith((ref) => ApiClient(config: const AppConfig(apiBaseUrl: 'http://test/api/v1'), dio: dio)),
  ]);
  addTearDown(container.dispose);
  return (container: container, adapter: adapter, store: store);
}

Future<void> _settle(ProviderContainer container) async {
  for (var i = 0; i < 120; i++) {
    if (container.read(driverSessionProvider).status != DriverSessionStatus.restoring) break;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  group('delivery parsing', () {
    test('reads the backend delivery shape', () {
      final d = Delivery.fromJson(_delivery());
      expect(d.orderNumber, 'OFK-20261109-A00343');
      expect(d.vendor.name, 'Shape Kitchen');
      expect(d.customer.phone, '+250785324560');
      expect(d.dropoff.note, 'Blue gate');
      expect(d.promisedEarningsRwf, 800);
      expect(d.pickupRules!.reassignAfterMinutes, 30);
      expect(d.items.single.options, 'Extra spicy');
      expect(d.itemCount, 2);
      expect(d.progress.single.label, 'Order placed');
    });

    test('an offer has no customer phone until it is accepted', () {
      final raw = _delivery()..['customer'] = {'id': 'c1', 'name': 'Shape Customer', 'phone_number': null};
      expect(Delivery.fromJson(raw).customer.phone, isEmpty);
    });
  });

  group('trip actions (the server decides)', () {
    test('assigned → confirm pickup, only when the server allows picked_up', () {
      expect(Delivery.fromJson(_delivery()).nextAction!.toStatus, DeliveryStatus.pickedUp);
      expect(Delivery.fromJson(_delivery(next: const ['cancelled'])).nextAction, isNull);
    });

    test('the food is not ready: the worker waits near the kitchen', () {
      final d = Delivery.fromJson(_delivery(kitchenReady: false));
      expect(d.waitingForKitchen, isTrue);
    });

    test('picked up → start the delivery', () {
      final d = Delivery.fromJson(_delivery(status: 'picked_up', next: const ['out_for_delivery', 'cancelled']));
      expect(d.nextAction!.kind, TripActionKind.startDelivery);
      expect(TripStage.of(d.status), TripStage.collected);
    });

    test('out for delivery → hand over with the code (no status is ever sent)', () {
      final d = Delivery.fromJson(_delivery(status: 'out_for_delivery', next: const ['delivered', 'cancelled']));
      expect(d.nextAction!.kind, TripActionKind.handOver);
      expect(d.nextAction!.toStatus, isNull);
    });

    test('a finished delivery offers nothing', () {
      expect(Delivery.fromJson(_delivery(status: 'completed', next: const [])).nextAction, isNull);
    });
  });

  test('navigation reads OSRM [lng, lat] pairs as lat/lng points', () {
    final nav = TripNavigation.fromJson({
      'active': true, 'target': 'kitchen', 'phase_label': 'Heading to the kitchen',
      'kitchen': {'latitude': -1.9441, 'longitude': 30.0619},
      'destination': {'latitude': -1.95, 'longitude': 30.07},
      'driver': {'location': {'latitude': -1.9421, 'longitude': 30.0639, 'stale': false}},
      'route': {'geometry': [[30.064226, -1.942604], [30.0619, -1.9441]], 'distance_m': 1038, 'duration_s': 105,
        'steps': [{'instruction': 'Head right on the road', 'distance_m': 38}]},
      'refresh_after_s': 4,
    });
    expect(nav.geometry.first.latitude, -1.942604);
    expect(nav.geometry.first.longitude, 30.064226);
    expect(nav.headingToKitchen, isTrue);
    expect(nav.targetPoint!.latitude, -1.9441);
    expect(nav.nextStep!.instruction, 'Head right on the road');
  });

  test('registration sends the plate only for motorised vehicles', () {
    const base = (name: ' Eric ', phone: '0788100009');
    final moto = DriverRegistration(name: base.name, phone: base.phone, vehicleType: VehicleType.motorcycle, plateNumber: 'rc 1 a').toJson();
    expect(moto, {'name': 'Eric', 'phone': '0788100009', 'vehicle_type': 'motorcycle', 'plate_number': 'RC 1 A'});
    final bike = DriverRegistration(name: base.name, phone: base.phone, vehicleType: VehicleType.bicycle, plateNumber: 'x', email: 'e@x.rw').toJson();
    expect(bike['plate_number'], '');
    expect(bike['email'], 'e@x.rw');
  });

  group('live GPS sending (website rules)', () {
    final t0 = DateTime(2026, 11, 9, 9);
    GeoFix at(int seconds, {double lat = -1.9441}) =>
        GeoFix(latitude: lat, longitude: 30.0619, at: t0.add(Duration(seconds: seconds)));

    test('the first fix is always sent', () => expect(shouldSendLiveFix(fix: at(0)), isTrue));
    test('never more often than every 4 s', () {
      expect(shouldSendLiveFix(fix: at(3, lat: -1.95), lastSent: at(0)), isFalse);
    });
    test('after 4 s when the rider moved 8 m or more', () {
      expect(shouldSendLiveFix(fix: at(5, lat: -1.9442), lastSent: at(0)), isTrue); // ~11 m
      expect(shouldSendLiveFix(fix: at(5), lastSent: at(0)), isFalse);
    });
    test('at least every 15 s while standing still', () {
      expect(shouldSendLiveFix(fix: at(15), lastSent: at(0)), isTrue);
    });
  });

  group('routing', () {
    test('signed-out workers go to sign-in, keeping a deep link', () {
      expect(driverRedirect(DriverSessionStatus.unauthenticated, Uri.parse('/trip')), '/login?from=%2Ftrip');
      expect(driverRedirect(DriverSessionStatus.unauthenticated, Uri.parse('/register')), isNull);
    });
    test('signed-in workers land on offers or their deep link', () {
      expect(driverRedirect(DriverSessionStatus.authenticated, Uri.parse('/login')), '/home');
      expect(driverRedirect(DriverSessionStatus.authenticated, Uri.parse('/login?from=%2Ftrip')), '/trip');
      // Never an outside address.
      expect(driverRedirect(DriverSessionStatus.authenticated, Uri.parse('/login?from=%2F%2Fevil.com')), '/home');
    });
    test('blocked and unreachable states have their own screens', () {
      expect(driverRedirect(DriverSessionStatus.blocked, Uri.parse('/home')), '/blocked');
      expect(driverRedirect(DriverSessionStatus.unreachable, Uri.parse('/home')), '/offline');
    });
  });

  group('session', () {
    test('a stored token restores the session through /driver/auth/me', () async {
      final s = _setup((_) => _json(200, {'driver': _driver()}), token: 'tok');
      s.container.read(driverSessionProvider);
      await _settle(s.container);
      expect(s.container.read(driverSessionProvider).driver!.name, 'Eric Uwimana');
      expect(s.adapter.log.single.path, '/driver/auth/me');
      expect(s.adapter.log.single.headers['Authorization'], 'Bearer tok');
    });

    test('verifying the code stores the token and signs in', () async {
      final s = _setup((o) => o.path == '/driver/auth/verify-otp'
          ? _json(200, {'token': 'new', 'driver': _driver()})
          : _json(200, {}));
      s.container.read(driverSessionProvider);
      await _settle(s.container);
      await s.container.read(driverSessionProvider.notifier).verifyOtp('0788100001', '123456');
      expect(s.container.read(driverSessionProvider).isAuthenticated, isTrue);
      expect(await s.store.read(), 'new');
      final sent = s.adapter.log.last;
      expect(sent.data, {'phone': '0788100001', 'code': '123456'});
      expect(sent.headers['Authorization'], isNull);
    });

    test('a suspended worker is blocked with the backend reason, and the token is dropped', () async {
      final s = _setup(
        (_) => _json(403, {'error': {'code': 'DRIVER_SUSPENDED', 'message': 'This delivery worker account was suspended. Contact support.'}}),
        token: 'tok',
      );
      s.container.read(driverSessionProvider);
      await _settle(s.container);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = s.container.read(driverSessionProvider);
      expect(state.status, DriverSessionStatus.blocked);
      expect(state.blockMessage, contains('suspended'));
      expect(await s.store.read(), isNull);
    });

    test('the app keeps its own token key, apart from the kitchen app', () {
      expect(SecureTokenStore.driverKey, 'ofk_driver_token');
      expect(SecureTokenStore.vendorKey, 'ofk_vendor_token');
    });
  });

  group('requests match the website', () {
    test('accept, status and hand-over use the driver endpoints and bodies', () async {
      final s = _setup((o) {
        if (o.path.endsWith('/confirm-delivery')) {
          return _json(200, {'delivery': _delivery(status: 'completed', next: const []), 'earned_rwf': 800, 'penalty_rwf': 0});
        }
        return _json(200, {'delivery': _delivery()});
      }, token: 'tok');
      s.container.read(apiClientProvider).setToken('tok');
      final repo = s.container.read(driverRepositoryProvider);
      await repo.accept('del1');
      await repo.updateStatus('del1', 'picked_up');
      final done = await repo.confirmDelivery('del1', code: '263361');
      expect(s.adapter.log.map((o) => '${o.method} ${o.path}'), [
        'POST /driver/deliveries/del1/accept',
        'PATCH /driver/deliveries/del1/status',
        'POST /driver/deliveries/del1/confirm-delivery',
      ]);
      expect(s.adapter.log[1].data, {'status': 'picked_up'});
      expect(s.adapter.log[2].data, {'otp_code': '263361'});
      expect(done.earnedRwf, 800);
    });

    test('offers are asked for near the given position', () async {
      final s = _setup((_) => _json(200, {'deliveries': [_delivery(status: 'pending')]}), token: 'tok');
      final offers = await s.container.read(driverRepositoryProvider).available(latitude: -1.94, longitude: 30.06);
      expect(offers.single.id, 'del1');
      expect(s.adapter.log.single.queryParameters, {'lat': -1.94, 'lng': 30.06});
    });

    test('the reused wallet and support screens call /driver paths', () async {
      final s = _setup((o) => o.path == '/driver/wallet'
          ? _json(200, {'available_balance_rwf': 300, 'processing_rwf': 500, 'withdrawn_rwf': 500, 'withdrawals': []})
          : _json(200, {'tickets': [], 'unread_count': 0, 'categories': ['delivery']}));
      final wallet = await s.container.read(walletProvider.future);
      await s.container.read(supportListProvider.future);
      expect(wallet.availableBalanceRwf, 300);
      expect(wallet.processingRwf, 500);
      expect(s.adapter.log.map((o) => o.path), containsAll(['/driver/wallet', '/driver/support']));
    });
  });

  group('slide to confirm', () {
    Future<List<int>> pump(WidgetTester tester, {bool enabled = true}) async {
      final calls = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SlideToConfirm(
                label: 'Slide to confirm pickup',
                enabled: enabled,
                onConfirmed: () async => calls.add(1),
              ),
            ),
          ),
        ),
      ));
      return calls;
    }

    testWidgets('a slow drag that stops halfway springs back and does nothing', (tester) async {
      final calls = await pump(tester);
      final knob = tester.getTopLeft(find.byType(SlideToConfirm)) + const Offset(32, 32);
      final gesture = await tester.startGesture(knob);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('sliding to the end confirms once', (tester) async {
      final calls = await pump(tester);
      await tester.drag(find.byType(SlideToConfirm), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(calls, [1]);
    });

    testWidgets('a tap only hints; it never confirms', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.byType(SlideToConfirm));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('disabled while the kitchen is cooking', (tester) async {
      final calls = await pump(tester, enabled: false);
      await tester.drag(find.byType(SlideToConfirm), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });
  });
}
