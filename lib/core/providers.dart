import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/dashboard/data/dashboard_repository.dart';
import '../features/menu/data/menu_repository.dart';
import '../features/notifications/data/notifications_repository.dart';
import '../features/orders/data/orders_repository.dart';
import '../features/promotions/data/promotions_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/support/data/support_repository.dart';
import '../features/wallet/data/wallet_repository.dart';
import 'config/app_config.dart';
import 'config/server_address.dart';
import 'network/api_client.dart';
import 'storage/token_store.dart';
import 'utils/uploads.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.current);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Replaces the network with something else. Null (always, in the real app)
/// means the real network. Only vendor preview mode sets it, to answer from
/// sample data on the device (see `lib/preview/`).
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(config: ref.watch(appConfigProvider));
  final adapter = ref.watch(httpAdapterProvider);
  if (adapter != null) client.dio.httpClientAdapter = adapter;
  // A request can finish after this scope is gone (sign-out, switching role): then there is
  // nobody to tell, and reading a disposed ref would throw.
  client.onConnectivity = (online) => Future.microtask(() {
        if (ref.mounted) ref.read(connectionProvider.notifier).report(online: online);
      });
  return client;
});

final serverAddressStoreProvider = Provider<ServerAddressStore>((ref) => ServerAddressStore());

/// The API address in use. Changing it points the client at the new server.
class ServerAddressNotifier extends Notifier<String> {
  @override
  String build() => AppConfig.current.apiBaseUrl;

  /// Saves and uses [url] (already normalised), or the build default for null.
  Future<void> apply(String? url) async {
    final store = ref.read(serverAddressStoreProvider);
    if (url == null) {
      await store.clear();
    } else {
      await store.write(url);
    }
    AppConfig.overrideApiBaseUrl(url);
    state = AppConfig.current.apiBaseUrl;
    ref.read(apiClientProvider).setBaseUrl(state);
  }
}

final serverAddressProvider = NotifierProvider<ServerAddressNotifier, String>(ServerAddressNotifier.new);

final mediaPickerProvider = Provider<MediaPicker>((ref) => DeviceMediaPicker());

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(apiClientProvider)));
final dashboardRepositoryProvider = Provider((ref) => DashboardRepository(ref.watch(apiClientProvider)));
final ordersRepositoryProvider = Provider((ref) => OrdersRepository(ref.watch(apiClientProvider)));
final menuRepositoryProvider = Provider((ref) => MenuRepository(ref.watch(apiClientProvider)));
final walletRepositoryProvider = Provider((ref) => WalletRepository(ref.watch(apiClientProvider)));
final promotionsRepositoryProvider = Provider((ref) => PromotionsRepository(ref.watch(apiClientProvider)));
final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(apiClientProvider)));
final chatRepositoryProvider = Provider((ref) => ChatRepository(ref.watch(apiClientProvider)));
final notificationsRepositoryProvider = Provider((ref) => NotificationsRepository(ref.watch(apiClientProvider)));
final supportRepositoryProvider = Provider((ref) => SupportRepository(ref.watch(apiClientProvider)));

/// Whether the app is in the foreground. Polling pauses while it is not.
class AppActiveNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool active) => state = active;
}

final appActiveProvider = NotifierProvider<AppActiveNotifier, bool>(AppActiveNotifier.new);

/// Whether the last request reached the server. Drives the offline banner.
class ConnectionNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void report({required bool online}) {
    if (state != online) state = online;
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, bool>(ConnectionNotifier.new);

/// Runs [refresh] every [interval] while the app is in the foreground, and
/// once more whenever it comes back to the foreground. Stops with the provider.
void keepFresh(Ref ref, Duration interval, FutureOr<void> Function() refresh) {
  Future<void> safe() async {
    try {
      await refresh();
    } catch (_) {
      // A failed background refresh is retried on the next tick.
    }
  }

  final timer = Timer.periodic(interval, (_) {
    if (ref.mounted && ref.read(appActiveProvider)) safe();
  });
  ref.listen<bool>(appActiveProvider, (previous, active) {
    if (active && previous == false) safe();
  });
  ref.onDispose(timer.cancel);
}
