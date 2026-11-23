// Kitchen side of big-event delivery: the kitchen chooses where it delivers
// (never the price, which KitchenLink sets) and answers special delivery
// requests with the server's allowed actions. Also the shared sign-in field.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_client.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/core/utils/validators.dart';
import 'package:kitchenlink_mobile/features/auth/models/vendor_type.dart';
import 'package:kitchenlink_mobile/features/special_delivery/application/special_delivery_providers.dart';
import 'package:kitchenlink_mobile/features/special_delivery/presentation/coverage_screen.dart';
import 'package:kitchenlink_mobile/features/special_delivery/presentation/special_deliveries_screens.dart';

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

ResponseBody _json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});

({ProviderContainer container, _Adapter adapter}) _setup(ResponseBody Function(RequestOptions) route) {
  final adapter = _Adapter(route);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  final container = ProviderContainer(overrides: [
    tokenStoreProvider.overrideWithValue(MemoryTokenStore('vendor-token')),
    apiClientProvider.overrideWith((ref) => ApiClient(config: const AppConfig(apiBaseUrl: 'http://test/api/v1'), dio: dio)),
  ]);
  addTearDown(container.dispose);
  return (container: container, adapter: adapter);
}

Map<String, dynamic> _coverage({bool enabled = true, List<Map<String, dynamic>> areas = const []}) => {
      'coverage': {'big_event_enabled': enabled, 'areas': areas},
      'districts': [
        {'code': 'gasabo', 'name': 'Gasabo', 'province': 'Kigali City'},
        {'code': 'musanze', 'name': 'Musanze', 'province': 'Northern'},
      ],
      'limits': {'areas': 10, 'radius_km': [1, 150]},
      'platform_pricing': {'starting_fee_rwf': 3000, 'per_meter_rwf': 0.5, 'min_fee_rwf': 3000, 'auto_ceiling_rwf': 40000, 'automatic_pricing_enabled': true},
    };

Future<void> _pump(WidgetTester tester, ProviderContainer container, Widget screen) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: screen)));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('saving coverage sends only places, never a price', () async {
    Object? sent;
    final s = _setup((options) {
      if (options.method == 'PUT') sent = options.data;
      return _json(_coverage());
    });
    await s.container.read(specialDeliveryRepositoryProvider).saveCoverage(enabled: true, areas: [
      {'kind': 'district', 'district': 'gasabo', 'label': 'Gasabo', 'district_name': 'Gasabo'},
      {'kind': 'radius', 'radius_km': 20, 'label': 'Within 20 km of my kitchen'},
    ]);
    final body = sent as Map;
    expect(s.adapter.log.single.path, '/vendor/delivery-coverage');
    expect(body.keys, unorderedEquals(['big_event_enabled', 'areas']));
    expect(jsonEncode(body).contains('fee'), isFalse, reason: 'KitchenLink sets delivery prices');
    expect((body['areas'] as List).first, {'kind': 'district', 'district': 'gasabo', 'label': 'Gasabo'});
  });

  testWidgets('the coverage screen shows KitchenLink pricing read-only and saves a new district', (tester) async {
    final s = _setup((options) => _json(_coverage(areas: options.method == 'PUT' ? (options.data['areas'] as List).cast<Map<String, dynamic>>() : const [])));
    await _pump(tester, s.container, const DeliveryCoverageScreen());
    expect(find.text('I deliver big-event orders'), findsOneWidget);
    expect(find.textContaining('RWF 3,000 starting fee + 0.5 RWF per meter of road'), findsOneWidget);
    expect(find.textContaining('you cannot change it'), findsOneWidget);
    expect(find.byType(TextField).evaluate().where((e) => (e.widget as TextField).decoration?.labelText?.contains('fee') ?? false), isEmpty,
        reason: 'no price field anywhere');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('   Musanze').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add district'));
    await tester.pumpAndSettle();
    expect(find.text('Musanze district'), findsOneWidget);
    await tester.ensureVisible(find.text('Save coverage'));
    await tester.tap(find.text('Save coverage'));
    await tester.pumpAndSettle();
    final put = s.adapter.log.where((o) => o.method == 'PUT').single;
    expect((put.data['areas'] as List).single['district'], 'musanze');
  });

  testWidgets('a new request offers exactly the server’s actions: accepting opens the negotiation', (tester) async {
    var status = 'pending_vendor_review';
    final calls = <String>[];
    final s = _setup((options) {
      calls.add('${options.method} ${options.path}');
      if (options.path.endsWith('/messages')) return _json({'messages': [], 'privacy_note': 'Chats are kept.'});
      if (options.path.endsWith('/accept-negotiation')) status = 'negotiation_accepted';
      return _json({
        'id': 'sd1',
        'reference': 'SD-000124',
        'status': status,
        'status_label': status == 'pending_vendor_review' ? 'Waiting for the kitchen' : 'Kitchen is open to discuss',
        'customer': {'name': 'Aline Uwase', 'phone': '+250788123456'},
        'event': {'guests': 200},
        'delivery_location': {'address': 'Musanze Hall'},
        'destination_district': {'code': 'musanze', 'name': 'Musanze'},
        'trigger_messages': ["This destination is outside the kitchen's delivery coverage."],
        'allowed_actions': status == 'pending_vendor_review'
            ? ['accept_negotiation', 'request_information', 'decline']
            : ['submit_quotation', 'decline', 'send_message'],
        'quotations': [],
        'arrangement_options': [{'code': 'own_vehicle', 'label': 'Own vehicle'}],
        'quotation_max_valid_hours': 48,
        'chat_open': status != 'pending_vendor_review',
      });
    });
    await _pump(tester, s.container, const SpecialDeliveryDetailScreen(requestId: 'sd1'));
    expect(find.text('Aline Uwase'), findsOneWidget);
    expect(find.textContaining("outside the kitchen's delivery coverage"), findsOneWidget);
    expect(find.text('Send a formal quotation'), findsNothing, reason: 'not before accepting to negotiate');
    await tester.tap(find.text('Accept to negotiate'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /vendor/special-deliveries/sd1/accept-negotiation'));
    expect(find.text('Send a formal quotation'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('one sign-in field: a phone or an email, the server decides', () {
    expect(Validators.identifier('0788123456'), isNull);
    expect(Validators.identifier('aline@example.com'), isNull);
    expect(Validators.identifier('12345'), contains('valid phone number'));
    expect(Validators.identifier('aline@'), contains('email'));
    expect(Validators.toIdentifier('+250 788 123 456'), '0788123456');
    expect(Validators.toIdentifier('  aline@example.com '), 'aline@example.com');
  });

  test("a kitchen type carries the food categories it gets automatically", () {
    final type = VendorType.fromJson({
      'code': 'bakery',
      'label': 'Bakery',
      'default_categories': [
        {'id': 'c1', 'name': 'Breads'},
        {'id': 'c2', 'name': 'Pastries'},
      ],
    });
    expect(type.defaultCategories, ['Breads', 'Pastries']);
  });
}
