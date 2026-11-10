import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/support/presentation/support_screens.dart';
import '../../features/wallet/presentation/withdraw_screen.dart';
import '../application/session.dart';
import '../presentation/account_screen.dart';
import '../presentation/auth_screens.dart';
import '../presentation/earnings_screen.dart';
import '../presentation/history_screen.dart';
import '../presentation/home_screen.dart';
import '../presentation/notifications_screen.dart';
import '../presentation/shell.dart';
import '../presentation/trip_screen.dart';

const _authPaths = {'/login', '/register', '/register/done'};
const _statusPaths = {'/splash', '/offline', '/blocked'};

/// Where a visitor must go, given the session and where they are. Null =
/// stay. Pure, so it is tested without a widget tree.
String? driverRedirect(DriverSessionStatus status, Uri location) {
  final path = location.path;
  switch (status) {
    case DriverSessionStatus.restoring:
      return path == '/splash' ? null : '/splash';
    case DriverSessionStatus.unreachable:
      return path == '/offline' ? null : '/offline';
    case DriverSessionStatus.blocked:
      return path == '/blocked' ? null : '/blocked';
    case DriverSessionStatus.unauthenticated:
      if (_authPaths.contains(path)) return null;
      // Remember a deep link (e.g. a notification) to open after sign-in.
      final from = _statusPaths.contains(path) || path == '/home' || path == '/' ? null : location.toString();
      return from == null ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
    case DriverSessionStatus.authenticated:
      if (path == '/login') {
        final from = location.queryParameters['from'];
        return (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : '/home';
      }
      if (_authPaths.contains(path) || _statusPaths.contains(path) || path == '/') return '/home';
      return null;
  }
}

final driverRootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'driver-root');

final driverRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(driverSessionProvider.select((state) => state.status), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: driverRootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => driverRedirect(ref.read(driverSessionProvider).status, state.uri),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const DriverSplashScreen()),
      GoRoute(path: '/offline', builder: (_, _) => const DriverOfflineScreen()),
      GoRoute(path: '/blocked', builder: (_, _) => const DriverBlockedScreen()),
      GoRoute(path: '/login', builder: (_, _) => const DriverLoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const DriverRegisterScreen()),
      GoRoute(path: '/register/done', builder: (_, _) => const DriverRegisteredScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => DriverShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/trip', builder: (_, _) => const TripScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/earnings', builder: (_, _) => const EarningsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),
      _full('/history', (_, _) => const HistoryScreen()),
      _full('/notifications', (_, _) => const DriverNotificationsScreen()),
      _full('/earnings/withdraw', (_, _) => const WithdrawScreen()),
      _full('/account/edit', (_, _) => const EditProfileScreen()),
      _full('/support', (_, _) => const SupportScreen()),
      _full('/support/new', (_, _) => const NewSupportRequestScreen()),
      _full('/support/:id', (_, state) => SupportTicketScreen(ticketId: state.pathParameters['id']!)),
    ],
  );
});

/// A screen that opens over the tabs, full screen.
GoRoute _full(String path, Widget Function(BuildContext, GoRouterState) builder) =>
    GoRoute(path: path, parentNavigatorKey: driverRootNavigatorKey, builder: builder);
