// Design review screenshots of the kitchen and delivery worker screens:
//   flutter test tool/shots/roles_shots_test.dart --update-goldens
// The kitchen runs in its preview mode (sample data on the device); the
// delivery worker against a small fake backend.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/app.dart';
import 'package:kitchenlink_mobile/app/router.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/driver/app/driver_app.dart';
import 'package:kitchenlink_mobile/driver/app/driver_router.dart';
import 'package:kitchenlink_mobile/driver/application/location.dart';
import 'package:kitchenlink_mobile/preview/preview_adapter.dart';
import 'package:kitchenlink_mobile/preview/preview_mode.dart';

import 'shots_support.dart';

class _Gps implements LocationService {
  @override
  Future<LocationAccess> ensureAccess({bool request = true}) async => LocationAccess.granted;
  @override
  Future<GeoFix?> current() async => GeoFix(latitude: -1.9441, longitude: 30.0619, at: DateTime.now());
  @override
  Stream<GeoFix> watch() => const Stream.empty();
  @override
  Future<void> openSettings(LocationAccess access) async {}
}

class _Fake implements HttpClientAdapter {
  _Fake(this.route);
  final Object? Function(RequestOptions) route;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    final data = route(options);
    return ResponseBody.fromString(jsonEncode(data ?? {}), data == null ? 404 : 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> driver() => {
      'id': 'd1', 'name': 'Eric Uwimana', 'phone': '+250788100001', 'email': null,
      'vehicle_type': 'motorcycle', 'plate_number': 'RC 123 A', 'rating': 4.9, 'rating_count': 120,
      'is_online': true, 'status': 'online', 'active_deliveries_count': 0,
      'max_active_deliveries': 3, 'completed_deliveries': 342, 'total_earnings_rwf': 412000,
      'available_balance_rwf': 18400, 'profile_image_url': null, 'verification_status': 'approved',
      'current_location': {'latitude': -1.9441, 'longitude': 30.0619, 'updated_at': null},
    };

Map<String, dynamic> delivery(String id, String status, {String kitchen = "Mama Aline's Kitchen", int fee = 1200}) => {
      'id': id, 'order_id': 'o$id', 'order_number': 'KL-20261111-$id', 'status': status,
      'status_label': status == 'pending' ? 'Waiting for a delivery worker' : 'Assigned to you',
      'allowed_next_statuses': status == 'pending' ? const [] : const ['picked_up', 'cancelled'],
      'vendor': {'id': 'v1', 'name': kitchen, 'phone': '+250784324560', 'address': 'KG 11 Ave', 'neighborhood': 'Kimironko', 'latitude': -1.9441, 'longitude': 30.0619},
      'customer': {'id': 'c1', 'name': 'Aline Uwase', 'phone_number': '+250785324560'},
      'pickup_location': {'address': 'KG 11 Ave', 'neighborhood': 'Kimironko', 'latitude': -1.9441, 'longitude': 30.0619},
      'delivery_location': {'address': 'KG 9 Ave, house 14', 'neighborhood': 'Remera', 'note': 'Blue gate', 'latitude': -1.95, 'longitude': 30.07},
      'route_distance_km': 2.4, 'distance_from_driver_km': 0.6, 'delivery_fee_rwf': fee,
      'promised_earnings_rwf': fee, 'paid_earnings_rwf': null, 'payment_method': 'mobile_money',
      'otp_required': true, 'kitchen_ready': true, 'expected_ready_at': null,
      'pickup_due_at': DateTime.now().add(const Duration(minutes: 12)).toUtc().toIso8601String(),
      'pickup_reassign_at': DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String(),
      'pickup_rules': {'warning_minutes': 10, 'charge_after_minutes': 15, 'reassign_after_minutes': 30},
      'late_pickup': null,
      'order_progress': {'status': 'assigned', 'label': 'Assigned', 'history': []},
      'items': [
        {'name': 'Isombe & plantain', 'price_rwf': 2500, 'quantity': 2, 'options': []},
        {'name': 'Goat brochettes', 'price_rwf': 3000, 'quantity': 1, 'options': []},
      ],
    };

Object? driverRoute(RequestOptions o, {required bool onTrip}) {
  switch (o.path) {
    case '/driver/auth/me':
      return {'driver': driver()};
    case '/driver/stats':
      return {'stats': {'active_deliveries': onTrip ? 1 : 0, 'completed_today': 7, 'earnings_today_rwf': 8400, 'completed_total': 342, 'earnings_total_rwf': 412000, 'rating': 4.9, 'is_online': true, 'status': 'online'}};
    case '/driver/deliveries/available':
      return {'deliveries': onTrip ? [] : [delivery('a1', 'pending'), delivery('a2', 'pending', kitchen: 'Kigali Grill House', fee: 1500)]};
    case '/driver/deliveries/active':
      return {'delivery': onTrip ? delivery('t1', 'assigned_to_driver') : null};
    case '/driver/deliveries/earnings':
      return {
        'summary': {'today_rwf': 8400, 'week_rwf': 52300, 'month_rwf': 198000, 'total_rwf': 412000, 'available_balance_rwf': 18400},
        'deliveries': [for (var i = 0; i < 4; i++) {...delivery('e$i', 'completed'), 'paid_earnings_rwf': 1200, 'completed_at': DateTime.now().subtract(Duration(hours: i * 3)).toUtc().toIso8601String()}],
      };
    case '/driver/deliveries/history':
      return {'deliveries': [], 'meta': {'total': 0}};
    case '/driver/notifications':
      return {'notifications': [], 'unread_count': 0};
    case '/driver/wallet':
      return {'available_balance_rwf': 18400, 'processing_rwf': 0, 'withdrawn_rwf': 120000, 'withdrawals': []};
    case '/driver/location':
    case '/driver/availability':
      return {'ok': true};
  }
  return null;
}

void dark(WidgetTester tester, bool on) {
  tester.platformDispatcher.platformBrightnessTestValue = on ? Brightness.dark : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 20));
}

void main() {
  setUpAll(loadAppFonts);

  for (final on in [false, true]) {
    final mode = on ? 'dark' : 'light';
    for (final tab in ['/dashboard', '/orders', '/menu', '/wallet', '/more']) {
      testWidgets('kitchen $tab $mode', (tester) async {
        phone(tester, height: tab == '/dashboard' ? 1500 : 852);
        dark(tester, on);
        final container = ProviderContainer(overrides: [
          previewModeProvider.overrideWithValue(true),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore(kPreviewToken)),
          httpAdapterProvider.overrideWithValue(PreviewAdapter(latency: Duration.zero)),
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KitchenLinkApp()));
        await settle(tester, 12);
        container.read(routerProvider).go(tab);
        await settle(tester, 12);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/kitchen${tab.replaceAll('/', '-')}-$mode.png'));
        await finish(tester);
      });
    }

    for (final (name, path, onTrip) in [('offers', '/home', false), ('trip', '/trip', true), ('earnings', '/earnings', false), ('account', '/account', false)]) {
      testWidgets('delivery $name $mode', (tester) async {
        phone(tester, height: name == 'trip' ? 1300 : 852);
        dark(tester, on);
        final container = ProviderContainer(overrides: [
          ...driverOverrides.skip(1),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore('tok')),
          httpAdapterProvider.overrideWithValue(_Fake((o) => driverRoute(o, onTrip: onTrip))),
          locationServiceProvider.overrideWithValue(_Gps()),
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KitchenLinkDeliveryApp()));
        await settle(tester, 12);
        container.read(driverRouterProvider).go(path);
        await settle(tester, 12);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/delivery-$name-$mode.png'));
        await finish(tester);
      });
    }
  }
}
