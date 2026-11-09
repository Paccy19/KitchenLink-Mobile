import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kitchenlink_mobile/api/api_client.dart';
import 'package:kitchenlink_mobile/client/screens/vendor_register_screen.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Finder _input(String hint) => find.ancestor(of: find.text(hint), matching: find.byType(TextField)).first;

void main() {
  for (final width in [360.0, 800.0]) {
    testWidgets('become a vendor: 3 steps, then the summary, at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      http.BaseRequest? registered;
      String? registeredBody;
      final mock = MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        if (path == '/home/categories') {
          return _json(200, {
            'categories': [
              {'name': 'Local Food', 'vendor_types': []},
              {'name': 'Breakfast', 'vendor_types': []},
              {'name': 'Pizza', 'vendor_types': []},
            ],
          });
        }
        if (path == '/vendor/auth/register') {
          registered = request;
          registeredBody = request.body;
          return _json(201, {
            'vendor': {
              'name': 'Mama Africa Kitchen',
              'vendor_type': 'home_cook',
              'location': {'neighborhood': 'Kimironko'},
              'verification_status': 'pending',
            },
          });
        }
        return _json(404, {});
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: VendorRegisterScreen(
              client: ApiClient(baseUrl: 'http://localhost:4000/api/v1'),
              pickDocuments: () async => [
                const PickedDocument('national-id.pdf', [1, 2, 3]),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1: as on the website.
        for (final text in [
          'TURN YOUR COOKING INTO A BUSINESS',
          'Become a Vendor',
          'Create your digital storefront on KitchenLink in a few steps — no restaurant required.',
          'Business',
          'Operations',
          'Verification',
          'Business details',
          'Tell customers who you are',
          'Business / vendor name',
          'What kind of food business are you?',
          'Home Cook',
          'Home-made meals cooked in a family kitchen.',
          'Other food business',
          'You can sell any kind of food whatever type you choose.',
          'Owner name',
          'Phone number',
          'Email (optional)',
          'Description',
          'Cancel',
          'Continue',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }

        // Continue with nothing filled in shows the website's errors.
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Business name is required.'), findsOneWidget);
        expect(find.text('Choose the type of food business you run.'), findsOneWidget);
        expect(find.text('Please write at least 10 characters.'), findsOneWidget);

        await tester.enterText(_input('e.g. Your Kitchen Name'), 'Mama Africa Kitchen');
        await tester.ensureVisible(find.text('Home Cook'));
        await tester.tap(find.text('Home Cook'));
        await tester.pumpAndSettle();
        expect(find.text('GREAT FOR'), findsOneWidget);
        expect(find.text('Only 20 orders a day'), findsOneWidget);
        await tester.enterText(_input('Full name'), 'jean paul');
        await tester.enterText(_input('07XXXXXXXX'), '0788123456');
        await tester.enterText(_input('Describe your food, story and what makes it special…'), 'Home-made Rwandan food every day.');
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 2.
        expect(find.text('Where you cook and what you serve'), findsOneWidget);
        expect(find.text('Use my current location'), findsOneWidget);
        await tester.enterText(_input('e.g. Kimironko'), 'Kimironko');
        await tester.enterText(_input('e.g. -1.944100'), '-1.9441, 30.0619');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Categories for Home Cook kitchens. Pick the ones you serve.'), findsOneWidget);
        expect(find.text('Pizza'), findsNothing);
        await tester.ensureVisible(find.text('Show all categories (1 more)'));
        await tester.tap(find.text('Show all categories (1 more)'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Local Food'));
        await tester.tap(find.text('Local Food'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 3: payout follows the phone's network.
        expect(find.text('Verification & payout'), findsOneWidget);
        expect(find.text('MTN Mobile Money'), findsOneWidget);
        await tester.ensureVisible(find.text('Create Vendor Account'));
        await tester.tap(find.text('Create Vendor Account'));
        await tester.pumpAndSettle();
        expect(find.text('Upload at least one verification document.'), findsOneWidget);
        expect(find.text('Please accept the vendor agreement.'), findsOneWidget);
        expect(registered, isNull);

        await tester.tap(find.text('Tap to upload documents'));
        await tester.pumpAndSettle();
        expect(find.text('national-id.pdf'), findsOneWidget);
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.ensureVisible(find.text('Create Vendor Account'));
        await tester.tap(find.text('Create Vendor Account'));
        await tester.pumpAndSettle();

        expect(registered, isNotNull);
        for (final part in [
          'name="name"',
          'Mama Africa Kitchen',
          'name="vendor_type"',
          'home_cook',
          'Jean Paul',
          '"neighborhood":"Kimironko"',
          '"latitude":-1.9441',
          '"longitude":30.0619',
          '["Local Food"]',
          '"open_time":"08:00"',
          '"payout_method":"mobile_money"',
          '"mobile_money_number":"0788123456"',
          'filename="national-id.pdf"',
        ]) {
          expect(registeredBody, contains(part), reason: part);
        }

        expect(find.text("You're all set, Mama Africa Kitchen!"), findsOneWidget);
        expect(find.text('Home Cook'), findsOneWidget);
        expect(find.text('Kimironko'), findsOneWidget);
        expect(find.text('pending'), findsOneWidget);
        expect(find.text('Go to Vendor Login'), findsOneWidget);
      }, () => mock);
    });
  }
}
