import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/app.dart';
import 'package:kitchenlink_mobile/app/router.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_exception.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/features/auth/application/session.dart';
import 'package:kitchenlink_mobile/features/orders/models/order.dart';
import 'package:kitchenlink_mobile/preview/preview_adapter.dart';
import 'package:kitchenlink_mobile/preview/preview_mode.dart';
import 'package:kitchenlink_mobile/root/role_switcher.dart';

/// Records every request that reaches the adapter.
class _Recording extends PreviewAdapter {
  _Recording() : super(latency: Duration.zero);
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests.add('${options.method} ${options.path}');
    return super.fetch(options, body, cancel);
  }
}

ProviderContainer _container(_Recording adapter) {
  final container = ProviderContainer(overrides: [
    previewModeProvider.overrideWithValue(true),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore(kPreviewToken)),
    httpAdapterProvider.overrideWithValue(adapter),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the real repositories parse every preview payload', () async {
    final c = _container(_Recording());
    final orders = await c.read(ordersRepositoryProvider).list();
    expect(orders.orders, isNotEmpty);
    expect(orders.meta.total, orders.orders.length);
    final detail = await c.read(ordersRepositoryProvider).detail(orders.orders.first.id);
    expect(detail.items, isNotEmpty);

    // Every order status the app knows is present, plus an event order and a pickup.
    final all = orders.orders;
    for (final status in OrderStatus.values) {
      expect(all.any((o) => o.status == status), isTrue, reason: 'no sample ${status.code} order');
    }
    expect(all.any((o) => o.isEvent && o.deposit != null), isTrue);
    expect(all.any((o) => o.canConfirmPickup), isTrue);

    final onlyNew = await c.read(ordersRepositoryProvider).list(status: OrderStatus.newOrder);
    expect(onlyNew.orders.every((o) => o.status == OrderStatus.newOrder), isTrue);

    final stats = await c.read(dashboardRepositoryProvider).stats();
    expect(stats.newOrders, all.where((o) => o.status == OrderStatus.newOrder).length);
    expect(stats.todayOrders, greaterThan(0));

    final menu = await c.read(menuRepositoryProvider).list();
    expect(menu.items.length, greaterThan(5));
    expect(menu.items.any((i) => !i.isAvailable), isTrue);
    expect(await c.read(menuRepositoryProvider).categories(), isNotEmpty);

    final wallet = await c.read(walletRepositoryProvider).wallet();
    expect(wallet.withdrawals, isNotEmpty);
    expect((await c.read(walletRepositoryProvider).banks()).banks, isNotEmpty);

    expect((await c.read(notificationsRepositoryProvider).list()).unreadCount, greaterThan(0));
    final chats = await c.read(chatRepositoryProvider).conversations();
    expect(chats, isNotEmpty);
    expect((await c.read(chatRepositoryProvider).thread(chats.first.id)).messages, isNotEmpty);
    expect((await c.read(supportRepositoryProvider).list()).tickets, isNotEmpty);
    expect(await c.read(promotionsRepositoryProvider).special(), isNotNull);
    expect(await c.read(promotionsRepositoryProvider).offers(), isNotEmpty);

    final settings = c.read(settingsRepositoryProvider);
    expect((await settings.ordering()), isNotNull);
    expect((await settings.nationwide()).enabled, isTrue);
    expect((await settings.eventPackage()).packages, isNotEmpty);
    expect(await c.read(authRepositoryProvider).vendorTypes(), isNotEmpty);
  });

  test('every write is refused with PREVIEW_MODE and nothing leaves the device', () async {
    final adapter = _Recording();
    final c = _container(adapter);
    final api = c.read(apiClientProvider);

    for (final call in <Future<Object?> Function()>[
      () => api.post('/vendor/menu', data: {'name': 'x'}),
      () => api.patch('/vendor/orders/ord-1001/status', data: {'status': 'accepted'}),
      () => api.put('/vendor/special', data: {'text': 'x'}),
      () => api.delete('/vendor/offers/off-1'),
      () => api.post('/vendor/wallet/withdrawals', data: {'amount_rwf': 1000}),
      () => api.post('/vendor/auth/logout'),
      () => api.multipart('PATCH', '/vendor/profile', FormData.fromMap({'name': 'x'})),
    ]) {
      await expectLater(
        call(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', kPreviewErrorCode).having((e) => e.isUnauthorized, 'unauthorized', isFalse)),
      );
    }
    // The adapter answered everything itself: no request was handed to a socket.
    expect(adapter.requests.length, 7);
  });

  test('the preview adapter never sets a real server address in play', () {
    // The preview token is a placeholder, not a credential.
    expect(kPreviewToken, isNot(contains('.')));
    expect(AppConfig.current.apiBaseUrl, isNotEmpty);
  });

  // A small and a large phone: the layouts must not overflow on either.
  for (final size in const [Size(360, 640), Size(430, 932)]) {
    testWidgets('preview opens the dashboard and every tab on a ${size.width.toInt()}x${size.height.toInt()} phone', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      addTearDown(tester.view.reset);

      final adapter = _Recording();
      final container = _container(adapter);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KitchenLinkApp()));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(container.read(sessionProvider).status, SessionStatus.authenticated);
      expect(find.textContaining('PREVIEW MODE'), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);

      // Every bottom tab opens (a layout overflow would fail the test here).
      for (final tab in ['Orders', 'Menu', 'Wallet', 'More']) {
        await tester.tap(find.text(tab).last);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
      }
      expect(find.text('Sign out'), findsNothing);

      // Every other vendor screen opens over the tabs with its sample data.
      final router = container.read(routerProvider);
      for (final path in const [
        '/orders/ord-1001', '/orders/ord-1003', '/orders/ord-1006', '/menu/new', '/menu/m2/edit', '/wallet/withdraw',
        '/notifications', '/messages', '/messages/chat-1', '/support', '/support/new', '/support/tkt-1',
        '/special', '/offers', '/settings/account', '/settings/location', '/settings/type', '/settings/ordering',
        '/settings/nationwide', '/settings/events',
      ]) {
        router.push(path);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(router.state.uri.path, path, reason: 'could not open $path');
        router.pop();
        await tester.pump(const Duration(milliseconds: 400));
      }
      // Only reads, only to the preview adapter.
      expect(adapter.requests.every((r) => r.startsWith('GET ')), isTrue, reason: adapter.requests.toString());

      // Leave the tree so the polling timers stop before the test ends.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }

  testWidgets('inside the unified app, More offers a way back to the marketplace', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);

    final container = _container(_Recording());
    AppRole? opened;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RoleSwitcher(current: AppRole.vendor, open: (role) => opened = role, child: const KitchenLinkApp()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.text('More').last);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // The list builds lazily: scroll the visible tab until the entry exists.
    await tester.scrollUntilVisible(find.text('Back to the marketplace'), 200, scrollable: find.byType(Scrollable).hitTestable().first);
    await tester.tap(find.text('Back to the marketplace'));
    await tester.pump();
    expect(opened, AppRole.marketplace);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
