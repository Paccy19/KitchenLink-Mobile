import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitchenlink_mobile/client/widgets/role_select_sheet.dart';

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets('sign-in role popup at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SignInRole? picked;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showRoleSelect(context);
                closed = true;
              },
              child: const Text('Sign In'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      for (final text in [
        'How do you want to sign in?',
        'Choose your role and we will take you to the right login page.',
        'Customer',
        'Vendor',
        'Delivery Worker',
        'Admin',
        'Manage the marketplace, users, orders, payments & analytics',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, SignInRole.admin);
      expect(find.text('How do you want to sign in?'), findsNothing);

      // The close button returns nothing.
      closed = false;
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, isNull);
    });
  }
}
