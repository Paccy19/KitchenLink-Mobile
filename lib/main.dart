import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A failed load is shown with a "Try again" button, never retried silently.
  runApp(ProviderScope(retry: (_, _) => null, child: const KitchenLinkApp()));
}
