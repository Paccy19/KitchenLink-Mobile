// End-to-end: how a vendor gets into the unified app (front door, kitchen
// registration, kitchen sign-in with an SMS code, session restore, sign-out).
// Real screens, real ApiClient, real backend. See e2e_support.dart to run.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/app.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/root/kitchenlink_root.dart';

import 'e2e_support.dart';

String _uniquePhone() => '078${(DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}';

/// Taps the wizard's bottom button. An error snackbar from the previous try covers
/// it for a few seconds, so (like a person would) dismiss it first.
Future<void> _tapNext(WidgetTester tester, String label) async {
  ScaffoldMessenger.of(tester.element(find.text(label))).clearSnackBars();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300)); // exit animation, then removal
  }
  await tester.tap(find.text(label));
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Widget _vendorApp(E2eFiles files) => ProviderScope(
      retry: (_, _) => null,
      overrides: [mediaPickerProvider.overrideWithValue(FakePicker(files.png, [files.pdf]))],
      child: const KitchenLinkApp(),
    );

void main() {
  if (!e2eEnabled) {
    test('vendor end-to-end tests need a backend (see test/e2e/e2e_support.dart)', () {}, skip: 'no E2E backend configured');
    return;
  }

  setUpAll(() async {
    HttpOverrides.global = null; // allow real network in tests
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();
  });
  final backend = Backend(kE2eApi);
  final files = E2eFiles.create();

  testWidgets('FRONT DOOR: marketplace -> Sign In -> Vendor opens the kitchen sign-in and remembers the role', (tester) async {
    freshKeystore();
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final marketplaceOverflows = collectOverflows();
    await tester.pumpWidget(const KitchenLinkRoot());
    await tester.settle(rounds: 6);
    // First launch shows the one-time location primer over the marketplace; a person dismisses it.
    if (find.text('Find kitchens near you').evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.close)); // the dialog's X: "Continue with default location"
      await tester.settle(rounds: 3);
    }
    expect(find.text('Sign In'), findsWidgets, reason: 'the marketplace header has a Sign In control');

    await tester.tap(find.text('Sign In').first);
    await tester.settle(rounds: 3);
    expect(find.text('How do you want to sign in?'), findsOneWidget);
    for (final role in ['Customer', 'Vendor', 'Delivery Worker', 'Admin']) {
      expect(find.text(role), findsOneWidget, reason: 'role choice $role');
    }

    await tester.tap(find.text('Vendor'));
    await tester.settle(rounds: 6);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your kitchen with your phone number.'), findsOneWidget);
    expect(find.text('Register your kitchen'), findsOneWidget);
    expect(find.text('Other ways to sign in'), findsOneWidget);
    expect((await keystoreContents())['ofk_app_role'], 'vendor');

    // The way back to the marketplace works and does not need a session.
    await tester.tap(find.text('Other ways to sign in'));
    await tester.settle(rounds: 6);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Sign In'), findsWidgets);
    expect((await keystoreContents())['ofk_app_role'], 'marketplace');
    // ignore: avoid_print
    expect(marketplaceOverflows, isEmpty);
    await tester.finish();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('LOGIN FORM: validation, unknown number (real backend error), wrong code (real backend error)', (tester) async {
    freshKeystore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_vendorApp(files));
    expect(await tester.until(find.text('Welcome back')), isTrue);

    // 1. empty phone
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter your phone number.'), findsOneWidget);

    // 2. not a Rwandan MTN/Airtel number
    await tester.enterText(_field('Kitchen phone number'), '0712345678');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.textContaining('valid Rwandan'), findsOneWidget);

    // 3. a well-formed number nobody registered: the backend's own message is shown
    await tester.enterText(_field('Kitchen phone number'), '0788999111');
    await tester.tap(find.text('Send code'));
    expect(await tester.until(find.text('No vendor account is registered with this phone number.')), isTrue);
    expect(find.text('Enter your code'), findsNothing, reason: 'must stay on the phone step');

    // 4. a registered number: code step, wrong code is rejected by the backend
    final phone = _uniquePhone();
    await tester.runAsync(() => registerVendorFixture(backend, files, phone, name: 'Login Form Kitchen'));
    await tester.enterText(_field('Kitchen phone number'), phone);
    await tester.tap(find.text('Send code'));
    expect(await tester.until(find.text('Enter your code')), isTrue);
    await tester.enterText(_field('6-digit code'), '12');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter the 6-digit code.'), findsOneWidget);
    await tester.enterText(_field('6-digit code'), '000000');
    await tester.tap(find.text('Sign in'));
    await tester.settle(rounds: 8);
    expect(find.textContaining('code'), findsWidgets);
    expect(find.text('Welcome back'), findsNothing);
    expect((await keystoreContents()).containsKey('ofk_vendor_token'), isFalse, reason: 'a wrong code must not store a token');
    await tester.finish();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('REGISTRATION -> SIGN IN -> DASHBOARD -> RESTART -> SIGN OUT (one real vendor, real backend)', (tester) async {
    freshKeystore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final phone = _uniquePhone();

    await tester.pumpWidget(_vendorApp(files));
    expect(await tester.until(find.text('Register your kitchen')), isTrue);
    await tester.tap(find.text('Register your kitchen'));
    await tester.settle(rounds: 3);

    // --- step 1: validation first, then fill ---
    expect(find.text('Step 1 of 6'), findsOneWidget);
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.text('Please fix the highlighted fields.'), findsWidgets); // shown as a snackbar
    await tester.pump(const Duration(seconds: 5)); // let the snackbar (it covers the Continue button) leave
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(_field('Kitchen name'), 'E2E Test Kitchen');
    expect(await tester.until(find.byType(DropdownButtonFormField<String>)), isTrue, reason: 'kitchen types load from the backend');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.settle(rounds: 2);
    await tester.tap(find.text('Restaurant').last);
    await tester.settle(rounds: 2);
    await tester.enterText(_field('What do you cook?'), 'Short');
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.textContaining('at least 10'), findsWidgets, reason: 'description too short is rejected');
    await tester.enterText(_field('What do you cook?'), 'Rwandan grills and stews, cooked fresh daily.');
    await _tapNext(tester, 'Continue');
    await tester.settle(rounds: 2);

    // --- step 2: owner & contact ---
    expect(find.text('Step 2 of 6'), findsOneWidget);
    await tester.enterText(_field('Owner full name'), 'Eric Tester');
    await tester.enterText(_field('Kitchen phone number'), '12345');
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.textContaining('valid Rwandan'), findsOneWidget, reason: 'bad phone rejected');
    await tester.enterText(_field('Kitchen phone number'), phone);
    await tester.enterText(_field('Email (optional)'), 'not-an-email');
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.textContaining('email'), findsWidgets, reason: 'bad optional email rejected');
    await tester.enterText(_field('Email (optional)'), '');
    await _tapNext(tester, 'Continue');
    await tester.settle(rounds: 2);

    // --- step 3: location (typed coordinates: there is no map picker) ---
    expect(find.text('Step 3 of 6'), findsOneWidget);
    await tester.enterText(_field('Street address'), 'KG 7 Ave, Kimihurura');
    await tester.enterText(_field('Neighbourhood'), 'Kimihurura');
    await tester.enterText(_field('Latitude'), '200');
    await tester.enterText(_field('Longitude'), '30.09');
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.textContaining('atitude'), findsWidgets, reason: 'out-of-range latitude rejected');
    await tester.enterText(_field('Latitude'), '-1.95');
    await _tapNext(tester, 'Continue');
    await tester.settle(rounds: 2);

    // --- step 4: food & hours ---
    expect(find.text('Step 4 of 6'), findsOneWidget);
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.text('Choose at least one food category.'), findsWidgets); // shown as a snackbar
    await tester.pump(const Duration(seconds: 5)); // let the snackbar (it covers the Continue button) leave
    await tester.pump(const Duration(milliseconds: 400));
    expect(await tester.until(find.byType(FilterChip)), isTrue, reason: 'food categories load from the backend');
    await tester.tap(find.byType(FilterChip).first);
    await tester.pump();
    await _tapNext(tester, 'Continue');
    await tester.settle(rounds: 2);

    // --- step 5: payouts (mobile money is bound to the registered phone) ---
    expect(find.text('Step 5 of 6'), findsOneWidget);
    await _tapNext(tester, 'Continue');
    await tester.pump();
    expect(find.textContaining('Account name'), findsWidgets);
    await tester.enterText(_field('Account holder name'), 'Eric Tester');
    await _tapNext(tester, 'Continue');
    await tester.settle(rounds: 2);

    // --- step 6: documents, then submit ---
    expect(find.text('Step 6 of 6'), findsOneWidget);
    await _tapNext(tester, 'Submit application');
    await tester.pump();
    expect(find.text('Add at least one verification document.'), findsWidgets); // shown as a snackbar
    await tester.pump(const Duration(seconds: 5)); // let the snackbar (it covers the Continue button) leave
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Add documents'));
    await tester.settle(rounds: 2);
    expect(find.text('licence.pdf'), findsOneWidget);
    await _tapNext(tester, 'Submit application');
    expect(await tester.until(find.text('Application submitted'), seconds: 40), isTrue, reason: 'the backend accepted the registration');

    // The backend really has the new, pending vendor (checked with a second, independent request).
    final (status, _) = (await tester.runAsync(() => backend.call('POST', '/vendor/auth/send-otp', body: {'phone': phone})))!;
    expect(status, 200, reason: 'a registered (pending) kitchen can request a sign-in code');
    // A duplicate registration is refused by the backend (checked by raw request).
    final (dupStatus, dup) = (await tester.runAsync(() => registerVendorRaw(backend, files, phone, name: 'Duplicate Kitchen')))!;
    expect(dupStatus, 409);
    expect((dup as Map)['error']['code'], 'PHONE_ALREADY_REGISTERED');

    // --- sign in through the real form (the code is the real one the backend issued, via dev_otp) ---
    await tester.tap(find.text('Sign in'));
    await tester.settle(rounds: 3);
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(_field('Kitchen phone number'), phone);
    await tester.tap(find.text('Send code'));
    // The code was already requested a moment ago by the check above, so the backend answers
    // "wait before requesting another"; the app must then still let the vendor type the code.
    expect(await tester.until(find.text('Enter your code'), seconds: 25), isTrue);
    expect(find.textContaining('just sent'), findsOneWidget, reason: 'the backend resend-cooldown message is shown');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 61)));
    await tester.pump(const Duration(seconds: 61)); // let the 60 s cooldown timer finish
    await tester.tap(find.text('Resend code'));
    await tester.settle(rounds: 8);
    final chip = find.textContaining('Development code:');
    expect(await tester.until(chip, seconds: 10), isTrue, reason: 'the dev server returned dev_otp');
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    expect(await tester.until(find.text('E2E Test Kitchen'), seconds: 30), isTrue, reason: 'the vendor dashboard opens');

    // Pending kitchen: dashboard + review banner, not the login screen.
    expect(find.textContaining('under review'), findsWidgets);
    final stored = await keystoreContents();
    expect(stored['ofk_vendor_token'], isNotNull, reason: 'vendor token saved');
    expect(stored.containsKey('ofk_driver_token'), isFalse, reason: 'no other role token');
    final token = stored['ofk_vendor_token']!;
    final me = (await tester.runAsync(() => backend.ok('GET', '/vendor/auth/me', token: token)))!;
    expect((me['vendor'] as Map)['name'], 'E2E Test Kitchen');
    expect((me['vendor'] as Map)['verification_status'], 'pending');

    // --- app restart: same keystore, brand-new widget tree -> still signed in ---
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_vendorApp(files));
    expect(await tester.until(find.text('E2E Test Kitchen'), seconds: 30), isTrue, reason: 'session restored after restart');
    expect(find.text('Welcome back'), findsNothing);

    // --- sign out: token removed from the phone AND revoked on the server ---
    await tester.tap(find.text('More').last);
    await tester.settle(rounds: 4);
    await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).hitTestable().first);
    await tester.tap(find.text('Sign out'));
    await tester.settle(rounds: 3);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    expect(await tester.until(find.text('Welcome back'), seconds: 20), isTrue);
    expect((await keystoreContents()).containsKey('ofk_vendor_token'), isFalse, reason: 'token cleared locally');
    final (revoked, _) = (await tester.runAsync(() => backend.call('GET', '/vendor/auth/me', token: token)))!;
    expect(revoked, 401, reason: 'the old token no longer works on the server');

    // And a restart now stays signed out.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_vendorApp(files));
    expect(await tester.until(find.text('Welcome back')), isTrue);
    await tester.finish();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
