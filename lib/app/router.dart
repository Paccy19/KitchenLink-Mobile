import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/status_screens.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/chat/presentation/chat_screens.dart';
import '../features/menu/presentation/menu_form_screen.dart';
import '../features/menu/presentation/menu_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/promotions/presentation/offers_screen.dart';
import '../features/promotions/presentation/special_screen.dart';
import '../features/settings/presentation/account_screen.dart';
import '../features/settings/presentation/business_settings_screens.dart';
import '../features/settings/presentation/event_package_screen.dart';
import '../features/settings/presentation/location_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/more_screen.dart';
import '../features/support/presentation/support_screens.dart';
import '../features/wallet/presentation/wallet_screen.dart';
import '../features/wallet/presentation/withdraw_screen.dart';

const _authPaths = {'/login', '/register', '/register/done'};

/// Where a visitor must be sent, given the session and where they are now.
/// Returns null to stay. Pure so it can be tested without a widget tree.
String? appRedirect(SessionStatus status, Uri location) {
  final path = location.path;
  switch (status) {
    case SessionStatus.restoring:
      return path == '/splash' ? null : '/splash';
    case SessionStatus.unreachable:
      return path == '/offline' ? null : '/offline';
    case SessionStatus.blocked:
      return path == '/blocked' ? null : '/blocked';
    case SessionStatus.unauthenticated:
      if (_authPaths.contains(path)) return null;
      // Remember a deep link (a notification, a shared order) to open after sign-in.
      final from = path == '/splash' || path == '/offline' || path == '/blocked' || path == '/dashboard'
          ? null
          : location.toString();
      return from == null ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
    case SessionStatus.authenticated:
      if (path == '/login') {
        final from = location.queryParameters['from'];
        return (from != null && from.startsWith('/')) ? from : '/dashboard';
      }
      if (_authPaths.contains(path) || path == '/splash' || path == '/offline' || path == '/blocked' || path == '/') {
        return '/dashboard';
      }
      return null;
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider.select((state) => state.status), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(ref.read(sessionProvider).status, state.uri),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/offline', builder: (_, _) => const ConnectionProblemScreen()),
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedAccountScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/register/done', builder: (_, _) => const RegistrationDoneScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/menu', builder: (_, _) => const MenuScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())]),
        ],
      ),
      GoRoute(
        path: '/orders/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      _full('/menu/new', (_, _) => const MenuFormScreen()),
      _full('/menu/:id/edit', (_, state) => MenuFormScreen(itemId: state.pathParameters['id'])),
      _full('/wallet/withdraw', (_, _) => const WithdrawScreen()),
      _full('/notifications', (_, _) => const NotificationsScreen()),
      _full('/messages', (_, _) => const MessagesScreen()),
      _full('/messages/:id', (_, state) => ChatThreadScreen(conversationId: state.pathParameters['id']!)),
      _full('/support', (_, _) => const SupportScreen()),
      _full('/support/new', (_, _) => const NewSupportRequestScreen()),
      _full('/support/:id', (_, state) => SupportTicketScreen(ticketId: state.pathParameters['id']!)),
      _full('/special', (_, _) => const SpecialScreen()),
      _full('/offers', (_, _) => const OffersScreen()),
      _full('/settings', (_, _) => const AccountScreen()),
      _full('/settings/account', (_, _) => const AccountScreen()),
      _full('/settings/location', (_, _) => const LocationScreen()),
      _full('/settings/type', (_, _) => const VendorTypeScreen()),
      _full('/settings/ordering', (_, _) => const OrderingSettingsScreen()),
      _full('/settings/nationwide', (_, _) => const NationwideScreen()),
      _full('/settings/events', (_, _) => const EventPackageScreen()),
    ],
  );
});

/// A screen that opens over the tabs, full screen.
GoRoute _full(String path, Widget Function(BuildContext, GoRouterState) builder) =>
    GoRoute(path: path, parentNavigatorKey: rootNavigatorKey, builder: builder);
