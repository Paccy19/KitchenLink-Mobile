import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_client.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/core/theme/app_theme.dart';
import 'package:kitchenlink_mobile/driver/app/driver_app.dart';
import 'package:kitchenlink_mobile/driver/presentation/earnings_screen.dart';

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    final data = o.path == '/driver/wallet'
        ? {
            'available_balance_rwf': 1200, 'total_earnings_rwf': 5000, 'withdrawn_rwf': 0, 'processing_rwf': 0,
            'payout_phone': '0788100001', 'payout_name': 'Eric', 'withdrawals': [],
          }
        : {
            'today_rwf': 800, 'today_deliveries': 1, 'total_rwf': 5000, 'total_deliveries': 4,
            'share_percent': 80, 'rating': 5, 'deliveries': [],
          };
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // The loading placeholder used to be a full-height list inside this
  // scrolling page: "unbounded height", then "Unexpected null value", and a
  // blank screen. Any layout error fails this test.
  testWidgets('earnings renders while loading and after, with the balance', (tester) async {
    // Tall enough that the whole page (and its loading placeholder) is laid out.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = _Adapter();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...driverOverrides.skip(1),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore('t')),
        apiClientProvider.overrideWith((ref) => ApiClient(config: const AppConfig(apiBaseUrl: 'http://test/api/v1'), dio: dio)),
      ],
      child: MaterialApp(theme: AppTheme.driverLight(), home: const EarningsScreen()),
    ));
    // First frame: wallet and earnings still loading (skeletons on screen).
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('RECENT DELIVERIES'), findsOneWidget);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('RWF 800'), findsOneWidget); // today
    expect(find.text('Withdraw'), findsOneWidget); // 1,200 RWF available
    expect(find.textContaining('Completed deliveries'), findsOneWidget);
  });
}
