// The vendor app in PREVIEW MODE: opens straight into the dashboard, no
// sign-in, so every vendor screen can be looked at without an account.
//
//   flutter run -t lib/main_vendor_preview.dart
//
// Everything on screen is sample data made up on the device (lib/preview/).
// Nothing is sent to the KitchenLink server and every write is refused.
// The real vendor app is the "Vendor" role of the unified app (`flutter run`,
// lib/main.dart): it uses the real sign-in and the real backend.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/token_store.dart';
import 'preview/preview_adapter.dart';
import 'preview/preview_mode.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        previewModeProvider.overrideWithValue(true),
        // The app's own session code restores this "token" and asks
        // GET /vendor/auth/me, which the preview adapter answers locally.
        tokenStoreProvider.overrideWithValue(MemoryTokenStore(kPreviewToken)),
        httpAdapterProvider.overrideWithValue(PreviewAdapter()),
      ],
      child: const KitchenLinkApp(),
    ),
  );
}
