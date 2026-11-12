import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitchenlink_mobile/core/widgets/kitchen_location_map.dart';

void main() {
  late TextEditingController lat;
  late TextEditingController lng;

  setUp(() {
    lat = TextEditingController();
    lng = TextEditingController();
  });

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: KitchenLocationMap(latitude: lat, longitude: lng, enabled: enabled),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder pin() => find.bySemanticsLabel(RegExp('Kitchen location pin'));

  testWidgets('no pin until there are coordinates; typing them places it', (tester) async {
    await pump(tester);
    expect(pin(), findsNothing);
    lat.text = '-1.95';
    lng.text = '30.06';
    await tester.pump();
    expect(pin(), findsOneWidget);
    expect(find.text('Check on Google Maps'), findsOneWidget);
  });

  testWidgets('tapping the map sets both boxes to the tapped spot', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FlutterMap));
    // The map waits out a possible double tap before reporting a tap.
    await tester.pump(const Duration(milliseconds: 500));
    expect(double.tryParse(lat.text), isNotNull);
    expect(double.tryParse(lng.text), isNotNull);
    // The map starts on Kigali, so the tapped spot is around it.
    expect(double.parse(lat.text), closeTo(-1.94, 0.3));
    expect(double.parse(lng.text), closeTo(30.06, 0.3));
    expect(lat.text.split('.').last.length, 6, reason: '6 decimals, like the website');
    expect(pin(), findsOneWidget);
  });

  testWidgets('pasting "latitude, longitude" into one box fills both', (tester) async {
    await pump(tester);
    lat.text = '-1.944100, 30.061900';
    await tester.pump();
    expect(lat.text, '-1.944100');
    expect(lng.text, '30.061900');
  });

  testWidgets('a disabled map shows the pin but ignores taps', (tester) async {
    lat.text = '-1.95';
    lng.text = '30.06';
    await pump(tester, enabled: false);
    await tester.tap(find.byType(FlutterMap));
    // The map waits out a possible double tap before reporting a tap.
    await tester.pump(const Duration(milliseconds: 500));
    expect(lat.text, '-1.95');
    expect(lng.text, '30.06');
    expect(find.textContaining('This is where customers find'), findsOneWidget);
  });
}
