import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/providers.dart';
import '../../core/storage/token_store.dart';
import '../../core/theme/app_theme.dart';
import '../../features/support/data/support_repository.dart';
import '../../features/wallet/data/wallet_repository.dart';
import 'driver_router.dart';

/// What the delivery worker app changes in the shared core: its own token key
/// (so it never shares a session with the kitchen app), and the `/driver`
/// paths for the support and wallet screens it reuses.
final List<Override> driverOverrides = [
  tokenStoreProvider.overrideWithValue(SecureTokenStore(null, SecureTokenStore.driverKey)),
  supportRepositoryProvider.overrideWith(
    (ref) => SupportRepository(ref.watch(apiClientProvider), basePath: '/driver/support'),
  ),
  walletRepositoryProvider.overrideWith(
    (ref) => WalletRepository(ref.watch(apiClientProvider), basePath: '/driver/wallet'),
  ),
];

class KitchenLinkDeliveryApp extends ConsumerStatefulWidget {
  const KitchenLinkDeliveryApp({super.key});

  @override
  ConsumerState<KitchenLinkDeliveryApp> createState() => _KitchenLinkDeliveryAppState();
}

class _KitchenLinkDeliveryAppState extends ConsumerState<KitchenLinkDeliveryApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Polling and GPS pause in the background and catch up on return.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => ref.read(appActiveProvider.notifier).set(state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'KitchenLink Delivery',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.driverLight(),
        darkTheme: AppTheme.driverDark(),
        themeMode: ThemeMode.system,
        routerConfig: ref.watch(driverRouterProvider),
      );
}
