import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../preview/preview_mode.dart';
import '../../core/widgets/components.dart';
import '../auth/application/session.dart';
import '../auth/presentation/status_screens.dart';
import '../dashboard/application/dashboard_providers.dart';
import '../notifications/application/notifications_providers.dart';
import '../orders/application/orders_providers.dart';

/// Bottom navigation plus the banners that belong on every screen: no
/// connection, documents under review, and new-order alerts.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(vendorProvider);
    final online = ref.watch(connectionProvider);
    final preview = ref.watch(previewModeProvider);
    final newOrders = ref.watch(dashboardProvider).value?.newOrders ?? 0;
    // Keep the unread count fresh for the bell on every tab.
    ref.watch(notificationsProvider);

    // A new order arrived while the app is open: nudge the vendor.
    ref.listen<NewOrderAlert?>(newOrderWatcherProvider, (previous, next) {
      if (next == null) return;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('New order #${next.order.orderNumber} from ${next.order.customer.name}'),
          action: SnackBarAction(label: 'VIEW', onPressed: () => context.push('/orders/${next.order.id}')),
        ));
    });

    return Scaffold(
      body: Column(children: [
        if (preview)
          const _Banner(
            icon: Icons.visibility_outlined,
            text: 'PREVIEW MODE: sample data only. Nothing is saved or sent to the server.',
            tone: Tone.info,
          ),
        if (!online) const _Banner(icon: Icons.wifi_off_rounded, text: 'No connection. Showing the last data we loaded.', tone: Tone.danger),
        if (vendor.isPending)
          _Banner(
            icon: Icons.hourglass_top_rounded,
            text: 'Your documents are under review. Some actions unlock once you are approved.',
            tone: Tone.warning,
            onTap: () => showPendingExplanation(context, vendor),
          ),
        Expanded(child: navigationShell),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) =>
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: CountBadge(count: newOrders, child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: CountBadge(count: newOrders, child: const Icon(Icons.receipt_long_rounded)),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu_rounded),
            label: 'Menu',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallet',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.tone, this.onTap});

  final IconData icon;
  final String text;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, tone);
    return Material(
      color: colors.background,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 18, color: colors.foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700)),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: colors.foreground),
            ]),
          ),
        ),
      ),
    );
  }
}
