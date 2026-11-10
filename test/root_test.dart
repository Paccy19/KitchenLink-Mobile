import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/root/role_switcher.dart';

void main() {
  test('a remembered role is read back, and anything unknown means the marketplace', () {
    expect(AppRole.parse('driver'), AppRole.driver);
    expect(AppRole.parse('vendor'), AppRole.vendor);
    expect(AppRole.parse(null), AppRole.marketplace);
    expect(AppRole.parse('nonsense'), AppRole.marketplace);
  });

  Future<List<AppRole>> pumpChooser(WidgetTester tester, {Future<void> Function()? onCustomerSignIn}) async {
    final opened = <AppRole>[];
    await tester.pumpWidget(RoleSwitcher(
      current: AppRole.marketplace,
      open: opened.add,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSignInChooser(context, onCustomerSignIn: onCustomerSignIn ?? () async {}),
              child: const Text('Sign in'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('Sign in offers the same four roles as the website', (tester) async {
    await pumpChooser(tester);
    expect(find.text('How do you want to sign in?'), findsOneWidget);
    for (final role in ['Customer', 'Vendor', 'Delivery Worker', 'Admin']) {
      expect(find.text(role), findsOneWidget);
    }
  });

  testWidgets('choosing Delivery Worker opens the delivery worker sign-in', (tester) async {
    final opened = await pumpChooser(tester);
    await tester.tap(find.text('Delivery Worker'));
    await tester.pumpAndSettle();
    expect(opened, [AppRole.driver]);
    expect(find.text('How do you want to sign in?'), findsNothing);
  });

  testWidgets('choosing Vendor or Admin opens their sign-in', (tester) async {
    var opened = await pumpChooser(tester);
    await tester.tap(find.text('Vendor'));
    await tester.pumpAndSettle();
    expect(opened, [AppRole.vendor]);

    opened = await pumpChooser(tester);
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(opened, [AppRole.admin]);
  });

  testWidgets('choosing Customer opens customer sign-in without changing role', (tester) async {
    var customerSignInOpened = false;
    final opened = await pumpChooser(tester, onCustomerSignIn: () async => customerSignInOpened = true);
    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(customerSignInOpened, isTrue);
  });

  testWidgets('"Other ways to sign in" goes back to the marketplace', (tester) async {
    final opened = <AppRole>[];
    await tester.pumpWidget(RoleSwitcher(
      current: AppRole.driver,
      open: opened.add,
      child: const MaterialApp(home: Scaffold(body: OtherSignInButton())),
    ));
    await tester.tap(find.text('Other ways to sign in'));
    expect(opened, [AppRole.marketplace]);
  });

  testWidgets('a delivery worker visiting the marketplace gets one tap back to deliveries', (tester) async {
    final opened = <AppRole>[];
    await tester.pumpWidget(RoleSwitcher(
      current: AppRole.marketplace,
      returnTo: AppRole.driver,
      open: opened.add,
      child: const MaterialApp(home: Scaffold(floatingActionButton: ReturnToRoleButton())),
    ));
    expect(find.text('Back to deliveries'), findsOneWidget);
    await tester.tap(find.text('Back to deliveries'));
    expect(opened, [AppRole.driver]);
  });

  testWidgets('a kitchen visiting the marketplace is offered its kitchen back', (tester) async {
    await tester.pumpWidget(RoleSwitcher(
      current: AppRole.marketplace,
      returnTo: AppRole.vendor,
      open: (_) {},
      child: const MaterialApp(home: Scaffold(floatingActionButton: ReturnToRoleButton())),
    ));
    expect(find.text('Back to my kitchen'), findsOneWidget);
  });

  testWidgets('nobody visiting means no way-back button', (tester) async {
    await tester.pumpWidget(RoleSwitcher(
      current: AppRole.marketplace,
      open: (_) {},
      child: const MaterialApp(home: Scaffold(body: ReturnToRoleButton())),
    ));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  test('visiting the marketplace is a visit when the app supports it, else a plain switch', () {
    var visited = 0;
    final opened = <AppRole>[];
    RoleSwitcher(current: AppRole.driver, open: opened.add, onVisitMarketplace: () => visited++, child: const SizedBox())
        .visitMarketplace();
    expect(visited, 1);
    expect(opened, isEmpty);

    RoleSwitcher(current: AppRole.driver, open: opened.add, child: const SizedBox()).visitMarketplace();
    expect(opened, [AppRole.marketplace]);
  });

  testWidgets('a sign-in screen on its own shows no back button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: OtherSignInButton())));
    expect(find.text('Other ways to sign in'), findsNothing);
  });
}
