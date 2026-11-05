import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kitchenlink_mobile/nav/admin_nav.dart';
import 'package:kitchenlink_mobile/screens/admin_shell.dart';
import 'package:kitchenlink_mobile/screens/pages/chats_page.dart';
import 'package:kitchenlink_mobile/screens/pages/complaints_page.dart';
import 'package:kitchenlink_mobile/screens/pages/orders_page.dart';
import 'package:kitchenlink_mobile/screens/pages/vendors_page.dart';
import 'package:kitchenlink_mobile/state/admin_session.dart';
import 'package:kitchenlink_mobile/state/theme_controller.dart';
import 'package:kitchenlink_mobile/ui/theme.dart';

/// Signs in to demo mode and opens every admin page, failing on any error.
void main() {
  testWidgets('every admin page loads on demo data', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    // The map's tile cache asks for a folder; tests have no phone to ask.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );

    final session = AdminSession();
    await tester.runAsync(() async {
      await session.restore();
      expect(session.demoMode, isTrue);
      await session.login('admin@foodkitchen.rw', 'anything');
    });
    expect(session.isAuthenticated, isTrue);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const AdminShell()),
    ));

    final shell = tester.state(find.byType(AdminShell)) as dynamic;
    for (final section in Pages.sections) {
      for (final page in section.pages) {
        shell.go(AdminRoute(page));
        // Let the demo server answer (it waits a few hundred ms) and the page build.
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Something went wrong.'), findsNothing, reason: page.label);
        expect(find.textContaining('not available in demo mode'), findsNothing, reason: page.label);
        final error = tester.takeException();
        expect(error, isNull, reason: '${page.label}: $error');
      }
    }

    // Detail screens: an order out for delivery (live map), a vendor, a complaint, a chat.
    final details = <String, Widget>{
      'order': const OrderDetailScreen(orderId: 'o9'),
      'vendor': const VendorDetailScreen(vendorId: 'v2'),
      'complaint': const ComplaintDetailScreen(complaintId: 'cmp1'),
      'chat': const ChatScreen(chatId: 'chat1'),
    };
    for (final entry in details.entries) {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(builder: (_) => entry.value));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Something went wrong.'), findsNothing, reason: entry.key);
      expect(find.textContaining('not found'), findsNothing, reason: entry.key);
      expect(tester.takeException(), isNull, reason: entry.key);
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Close everything so polling timers stop.
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
