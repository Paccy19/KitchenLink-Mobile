import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/components.dart';
import '../application/deliveries.dart';
import '../models/driver_notification.dart';

/// Tabs plus what belongs on every screen: the connection banner and the
/// alerts for new offers and trip updates (food ready, late, taken).
class DriverShell extends ConsumerWidget {
  const DriverShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectionProvider);
    final offers = ref.watch(offersProvider).value?.length ?? 0;
    final onTrip = ref.watch(activeTripProvider).value != null;
    // Keep these alive on every tab: GPS sharing and the notification feed.
    ref.watch(locationTrackerProvider);
    ref.watch(driverNotificationsProvider);

    ref.listen<OfferAlert?>(offerAlertProvider, (_, alert) {
      if (alert == null) return;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      _snack(
        context,
        icon: Icons.delivery_dining_rounded,
        text: 'New offer · ${alert.offer.vendor.name} · earn ${formatRwf(alert.offer.promisedEarningsRwf)}',
        action: 'VIEW',
        onAction: () => navigationShell.goBranch(0),
      );
    });

    ref.listen<DriverNotification?>(tripAlertProvider, (_, alert) {
      if (alert == null) return;
      HapticFeedback.mediumImpact();
      if (alert.type == 'delivery_ready' || alert.type == 'delivery_pickup_reminder') {
        SystemSound.play(SystemSoundType.alert);
      }
      _snack(
        context,
        icon: alert.endsTrip ? Icons.info_outline_rounded : Icons.notifications_active_rounded,
        text: alert.body.isNotEmpty ? alert.body : alert.title,
        action: alert.endsTrip ? null : 'OPEN',
        onAction: () => navigationShell.goBranch(1),
      );
    });

    return Scaffold(
      extendBody: true,
      body: Column(children: [
        if (!online)
          Material(
            color: toneColors(context, Tone.danger).background,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(Icons.wifi_off_rounded, size: 18, color: toneColors(context, Tone.danger).foreground),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No connection. Showing the last data we loaded.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: toneColors(context, Tone.danger).foreground,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        Expanded(child: navigationShell),
      ]),
      bottomNavigationBar: _GlassBar(
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
          },
          destinations: [
            NavigationDestination(
              icon: CountBadge(count: offers, child: const Icon(Icons.local_offer_outlined)),
              selectedIcon: CountBadge(count: offers, child: const Icon(Icons.local_offer_rounded)),
              label: 'Offers',
            ),
            NavigationDestination(
              icon: _Dot(on: onTrip, child: const Icon(Icons.route_outlined)),
              selectedIcon: _Dot(on: onTrip, child: const Icon(Icons.route_rounded)),
              label: 'Trip',
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Earnings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }

  void _snack(
    BuildContext context, {
    required IconData icon,
    required String text,
    String? action,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
        action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ));
  }
}

/// A translucent material the content scrolls under (solid when the phone
/// asks for more contrast).
class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final solid = MediaQuery.maybeHighContrastOf(context) ?? false;
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: solid ? 1 : 0.78),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: solid ? 1 : 0.6), width: 0.5)),
      ),
      child: child,
    );
    if (solid) return bar;
    return ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: bar),
    );
  }
}

/// A small dot on the Trip tab while a delivery is in progress.
class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        child,
        if (on)
          Positioned(
            right: -3,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
      ]);
}
