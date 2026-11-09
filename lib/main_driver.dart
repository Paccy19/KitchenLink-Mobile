// The delivery worker app, KitchenLink Delivery. Run it with:
//   flutter run -t lib/main_driver.dart
// (lib/main.dart is the admin app, lib/main_vendor.dart the kitchen app.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/server_address.dart';
import 'driver/app/driver_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A server address chosen in the app is used from the very first request.
  await ServerAddressStore().applySaved();
  runApp(ProviderScope(
    // A failed load is shown with a "Try again" button, never retried silently.
    retry: (_, _) => null,
    overrides: driverOverrides,
    child: const KitchenLinkDeliveryApp(),
  ));
}
