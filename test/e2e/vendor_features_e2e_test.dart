// End-to-end: what an approved vendor can do. A real kitchen is registered, approved by
// the (scratch) admin and given a real customer order through the backend's own API; then
// the app's real screens and repositories work with it. See e2e_support.dart to run.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/app.dart';
import 'package:kitchenlink_mobile/app/router.dart';
import 'package:kitchenlink_mobile/core/network/api_exception.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/features/menu/models/menu.dart';
import 'package:kitchenlink_mobile/features/wallet/models/wallet.dart';

import 'e2e_support.dart';

String _uniquePhone([int offset = 0]) =>
    '079${((DateTime.now().millisecondsSinceEpoch + offset) % 10000000).toString().padLeft(7, '0')}';

class _World {
  late String vendorPhone, vendorId, vendorToken, customerToken, orderId, orderNumber, pickupCode, itemId;
}

ProviderContainer _container(String token) {
  final container = ProviderContainer(overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore(token))]);
  container.read(apiClientProvider).setToken(token);
  addTearDown(container.dispose);
  return container;
}

void main() {
  if (!e2eEnabled) {
    test('vendor feature tests need a backend (see test/e2e/e2e_support.dart)', () {}, skip: 'no E2E backend configured');
    return;
  }

  final backend = Backend(kE2eApi);
  late E2eFiles files;
  final w = _World();

  setUpAll(() async {
    HttpOverrides.global = null;
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();
    files = E2eFiles.create();

    // A real kitchen: registered, approved by an admin, signed in through the backend's own login.
    w.vendorPhone = _uniquePhone();
    final registered = await registerVendorFixture(backend, files, w.vendorPhone, name: 'Feature Kitchen');
    w.vendorId = (registered['vendor'] as Map)['id'] as String;
    await backend.approveVendor(w.vendorId);
    w.vendorToken = await backend.vendorToken(w.vendorPhone);
    await backend.ok('PATCH', '/vendor/availability', body: {'is_open': true}, token: w.vendorToken);
    final dish = await backend.ok('POST', '/vendor/menu',
        body: {'name': 'Fixture Dish', 'price_rwf': 6000, 'description': 'A fixture dish.', 'preparation_time_minutes': 10},
        token: w.vendorToken);
    w.itemId = dish['id'] as String;

    // A real customer order for it (pickup, so the vendor completes it with the customer's code).
    final customerPhone = _uniquePhone(7);
    w.customerToken = await backend.customerToken(customerPhone, 'Fixture Customer');
    await backend.ok('POST', '/cart', body: {'menu_item_id': w.itemId, 'quantity': 1}, token: w.customerToken);
    final order = await backend.ok('POST', '/orders/checkout',
        body: {
          'fulfillment': 'pickup',
          'payment_method': 'mobile_money',
          'payment_details': {'phone': customerPhone},
          'order_type': 'immediate',
        },
        token: w.customerToken);
    w.orderId = order['id'] as String;
    w.orderNumber = order['order_number'] as String;
    w.pickupCode = (order['pickup'] as Map)['code'] as String;
  });

  testWidgets('ORDERS (UI): dashboard shows the new order, vendor moves it new -> completed with the pickup code', (tester) async {
    freshKeystore({'ofk_vendor_token': w.vendorToken});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(retry: (_, _) => null, child: const KitchenLinkApp()));
    expect(await tester.until(find.text('Feature Kitchen'), seconds: 30), isTrue, reason: 'dashboard of THIS vendor');
    expect(await tester.until(find.text('New orders')), isTrue);
    expect(find.text('Pending'), findsNothing); // approved: no review banner
    expect(find.textContaining('under review'), findsNothing);

    // Orders tab lists the customer's real order.
    await tester.tap(find.text('Orders').last);
    expect(await tester.until(find.textContaining(w.orderNumber)), isTrue, reason: 'the order the customer placed is listed');
    await tester.tap(find.textContaining(w.orderNumber).first);
    expect(await tester.until(find.text('Accept order')), isTrue);
    // The order page slides in; touches are ignored until it has arrived.
    await tester.settle(rounds: 4);
    expect(find.textContaining('Fixture Dish'), findsWidgets);
    expect(find.textContaining('Fixture Customer'), findsWidgets);

    Future<void> step(String label, String next) async {
      await tester.tap(find.text(label));
      await tester.settle(rounds: 3);
      // some actions ask for confirmation
      final confirm = find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton));
      if (confirm.evaluate().isNotEmpty) await tester.tap(confirm.last);
      expect(await tester.until(find.text(next), seconds: 20), isTrue, reason: 'after "$label" the screen offers "$next"');
    }

    await step('Accept order', 'Start preparing');
    await step('Start preparing', 'Mark ready');
    await step('Mark ready', 'Confirm pickup with code');
    final (_, readyJson) = (await tester.runAsync(() => backend.call('GET', '/vendor/orders/${w.orderId}', token: w.vendorToken)))!;
    expect((readyJson as Map)['status'], 'ready', reason: 'the backend really holds "ready"');

    // A wrong pickup code is refused by the backend; the right one completes the order.
    await tester.tap(find.text('Confirm pickup with code'));
    await tester.settle(rounds: 3);
    await tester.enterText(find.byType(TextField).last, w.pickupCode == '000000' ? '111111' : '000000');
    await tester.tap(find.text('Complete pickup'));
    await tester.settle(rounds: 6);
    expect(find.text('Complete pickup'), findsOneWidget, reason: 'wrong code keeps the sheet open');
    await tester.enterText(find.byType(TextField).last, w.pickupCode);
    await tester.tap(find.text('Complete pickup'));
    await tester.settle(rounds: 8);

    final (_, doneJson) = (await tester.runAsync(() => backend.call('GET', '/vendor/orders/${w.orderId}', token: w.vendorToken)))!;
    expect((doneJson as Map)['status'], 'completed', reason: 'backend: order completed');
    final (_, wallet) = (await tester.runAsync(() => backend.call('GET', '/vendor/wallet', token: w.vendorToken)))!;
    expect(((wallet as Map)['available_balance_rwf'] as num) > 0, isTrue, reason: 'completing the order credits the vendor');
    await tester.finish();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('MENU + IMAGE UPLOAD (real multipart): create with photo, edit, hide, delete', () async {
    final menu = _container(w.vendorToken).read(menuRepositoryProvider);
    final categories = await menu.categories();
    final created = await menu.create(
      MenuItemDraft(name: 'Uploaded Dish', priceRwf: 4500, description: 'With a photo.', preparationMinutes: 15, categoryId: categories.first.id),
      image: files.png,
    );
    expect(created.name, 'Uploaded Dish');
    expect(created.imageUrl, isNotNull, reason: 'the backend stored the photo');
    final client = HttpClient();
    final image = await (await client.getUrl(Uri.parse(created.imageUrl!.startsWith('http') ? created.imageUrl! : kE2eApi.replaceFirst('/api/v1', '') + created.imageUrl!))).close();
    expect(image.statusCode, 200, reason: 'the uploaded photo is really served');
    await image.drain<void>();
    client.close(force: true);

    final edited = await menu.update(created.id, MenuItemDraft(name: 'Uploaded Dish', priceRwf: 5000, categoryId: categories.first.id));
    expect(edited.priceRwf, 5000);
    expect((await menu.setAvailability(created.id, false)).isAvailable, isFalse);
    expect((await menu.list()).items.map((i) => i.name), containsAll(['Fixture Dish', 'Uploaded Dish']));
    await menu.delete(created.id);
    expect((await menu.list()).items.any((i) => i.id == created.id), isFalse);
    // validation comes from the backend
    await expectLater(
      menu.create(const MenuItemDraft(name: 'X', priceRwf: -5)),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
  });

  test('WALLET + WITHDRAWAL (real money rules): balance from the completed order, withdraw, refuse too much', () async {
    final c = _container(w.vendorToken);
    final wallets = c.read(walletRepositoryProvider);
    final before = await wallets.wallet();
    expect(before.availableBalanceRwf, greaterThan(0), reason: 'credited by the order completed in the orders test');
    expect(before.commissionPercent, greaterThan(0));
    expect((await wallets.banks()).banks, isNotNull);

    await expectLater(
      wallets.requestWithdrawal(WithdrawalRequest(amountRwf: before.availableBalanceRwf + 100000, method: PayoutMethod.mtn, phone: w.vendorPhone)),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('balance'))),
    );
    final taken = await wallets.requestWithdrawal(WithdrawalRequest(amountRwf: 1000, method: PayoutMethod.mtn, phone: w.vendorPhone));
    expect(taken.amountRwf, 1000);
    final after = await wallets.wallet();
    expect(after.availableBalanceRwf, before.availableBalanceRwf - 1000);
    expect(after.withdrawals.any((x) => x.id == taken.id), isTrue);
  });

  test('NOTIFICATIONS, CHAT, SUPPORT: a real conversation with the customer and a real support ticket', () async {
    final c = _container(w.vendorToken);
    final notes = c.read(notificationsRepositoryProvider);
    final page = await notes.list();
    expect(page.items.any((n) => n.orderId == w.orderId), isTrue, reason: 'the order notification reached the vendor');
    await notes.markAllRead();
    expect((await notes.list()).unreadCount, 0);

    // The customer writes first (as in the real app); the vendor reads and replies.
    final chat = await backend.ok('POST', '/chats/with/${w.vendorId}', token: w.customerToken);
    final chatId = ((chat['conversation'] ?? chat) as Map)['id'] as String;
    await backend.ok('POST', '/chats/$chatId/messages', body: {'body': 'Is my order ready?'}, token: w.customerToken);
    final chats = c.read(chatRepositoryProvider);
    expect(await chats.unreadCount(), greaterThan(0));
    final conversations = await chats.conversations();
    expect(conversations.single.customerName, 'Fixture Customer');
    final thread = await chats.thread(conversations.single.id);
    expect(thread.messages.single.body, 'Is my order ready?');
    expect(thread.messages.single.mine, isFalse);
    await chats.send(conversations.single.id, 'Yes, come and collect it.');
    final seen = await backend.ok('GET', '/chats/$chatId', token: w.customerToken);
    expect((seen['messages'] as List).map((m) => (m as Map)['body']), contains('Yes, come and collect it.'));

    final support = c.read(supportRepositoryProvider);
    final categories = (await support.list()).categories;
    expect(categories, isNotEmpty);
    final ticket = await support.create(subject: 'Payout question', message: 'When is my payout paid?', category: 'payment');
    expect(ticket.status, 'open');
    final replied = await support.reply(ticket.id, 'Thank you.');
    expect(replied.messages.length, greaterThanOrEqualTo(2));
    expect((await support.list()).tickets.map((t) => t.subject), contains('Payout question'));
  });

  test('PROFILE, STORE STATUS, IMAGES, ORDERING, NATIONWIDE, EVENTS, SPECIAL, OFFERS (real saves)', () async {
    final c = _container(w.vendorToken);
    final settings = c.read(settingsRepositoryProvider);

    expect((await settings.setAvailability(isOpen: false)).isOpen, isFalse);
    expect((await settings.setAvailability(isOpen: true)).isOpen, isTrue);
    final updated = await settings.updateProfile({'description': 'Updated by the e2e test for the kitchen.'});
    expect(updated.description, 'Updated by the e2e test for the kitchen.');
    final withImages = await settings.updateImages(banner: files.png, profile: files.png);
    expect(withImages.bannerImageUrl, isNotNull);
    expect(withImages.profileImageUrl, isNotNull);
    await expectLater(settings.updateProfile({'name': 'x'}), throwsA(isA<ApiException>()), reason: 'name too short is refused');

    final ordering = await settings.saveOrdering(minOrderRwf: 2000, sendDailyLimit: false);
    expect(ordering.minOrderRwf, 2000);
    final nationwide = await settings.saveNationwide(travelBaseFeeRwf: 6000, travelPerKmRwf: 350);
    expect(nationwide.travelBaseFeeRwf, 6000);
    final events = await settings.eventPackage();
    expect(events.limits.packages, greaterThan(0));
    await settings.saveEventPackage(events);

    final promos = c.read(promotionsRepositoryProvider);
    final now = DateTime.now();
    final special = await promos.saveSpecial(
      text: 'Tomorrow: pilau and goat',
      cutoffAt: now.add(const Duration(hours: 6)),
      deliveryAt: now.add(const Duration(hours: 24)),
    );
    expect(special?.text, 'Tomorrow: pilau and goat');
    await promos.clearSpecial();
    expect(await promos.special(), isNull);
    final day = now.add(const Duration(days: 5));
    final date = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final offer = await promos.createOffer(title: 'Brochette Friday', details: 'Two for one.', offerDate: date);
    expect((await promos.offers()).map((o) => o.id), contains(offer.id));
    await promos.cancelOffer(offer.id);

    // the logged-in vendor only ever sees their own data
    final other = await backend.ok('GET', '/vendor/orders', token: w.vendorToken);
    expect((other['orders'] as List).every((o) => (o as Map)['id'] == w.orderId), isTrue);
  });

  testWidgets('EVERY SCREEN (UI) opens with this vendor\'s real data, no errors, at 360x640 and 430x932', (tester) async {
    for (final size in const [Size(360, 640), Size(430, 932)]) {
      freshKeystore({'ofk_vendor_token': w.vendorToken});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KitchenLinkApp()));
      expect(await tester.until(find.text('Feature Kitchen'), seconds: 30), isTrue);
      final router = container.read(routerProvider);
      for (final tab in ['Orders', 'Menu', 'Wallet', 'More']) {
        await tester.tap(find.text(tab).last);
        await tester.settle(rounds: 5);
      }
      for (final path in [
        '/orders/${w.orderId}', '/menu/new', '/menu/${w.itemId}/edit', '/wallet/withdraw', '/notifications', '/messages',
        '/support', '/support/new', '/special', '/offers', '/settings/account', '/settings/location', '/settings/type',
        '/settings/ordering', '/settings/nationwide', '/settings/events',
      ]) {
        router.push(path);
        await tester.settle(rounds: 5);
        expect(router.state.uri.path, path, reason: 'could not open $path at $size');
        router.pop();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose(); // stops the screens' polling timers
      await tester.pump(const Duration(seconds: 6));
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
