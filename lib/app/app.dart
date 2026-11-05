import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class KitchenLinkApp extends ConsumerStatefulWidget {
  const KitchenLinkApp({super.key});

  @override
  ConsumerState<KitchenLinkApp> createState() => _KitchenLinkAppState();
}

class _KitchenLinkAppState extends ConsumerState<KitchenLinkApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Polling pauses in the background and catches up when the app returns.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          ref.read(appActiveProvider.notifier).set(state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'KitchenLink Kitchen',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: ref.watch(routerProvider),
      );
}
