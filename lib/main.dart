import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/server_address.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A server address chosen in the app is used from the very first request.
  await ServerAddressStore().applySaved();
  // A failed load is shown with a "Try again" button, never retried silently.
  runApp(ProviderScope(retry: (_, _) => null, child: const KitchenLinkApp()));
}
