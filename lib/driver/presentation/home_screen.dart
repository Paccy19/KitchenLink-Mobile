import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../application/deliveries.dart';
import '../application/location.dart';
import '../application/session.dart';
import '../models/delivery.dart';
import '../models/driver_account.dart';
import 'widgets/motion.dart';
import 'widgets/offer_card.dart';
import 'widgets/trip_widgets.dart';

/// Offers: go on duty, see today at a glance, and take deliveries.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.read(offersProvider.notifier).reload(silent: false),
      ref.read(driverStatsProvider.notifier).reload(silent: false),
      ref.read(activeTripProvider.notifier).reload(silent: false),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = ref.watch(driverProvider);
    final stats = ref.watch(driverStatsProvider);
    final offers = ref.watch(offersProvider);
    final trip = ref.watch(activeTripProvider).value;
    final tracking = ref.watch(locationTrackerProvider);
    final unread = ref.watch(driverNotificationsProvider).value?.unreadCount ?? 0;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref).catchError((_) {}),
        edgeOffset: MediaQuery.paddingOf(context).top,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: _Header(driver: driver, unread: unread),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(children: [
                _DutyCard(driver: driver, onTrip: trip != null),
                if (tracking.message != null && driver.isOnline) ...[
                  const SizedBox(height: 12),
                  _LocationNotice(state: tracking),
                ],
                if (trip != null) ...[
                  const SizedBox(height: 12),
                  _ContinueTrip(trip: trip),
                ],
                const SizedBox(height: 12),
                _Today(stats: stats.value),
                GroupLabel(
                  driver.isOnline ? 'Offers near you' : 'Offers',
                  trailing: driver.isOnline
                      ? Text(
                          'First to accept wins',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        )
                      : null,
                ),
              ]),
            ),
            ..._offers(context, ref, driver, offers, trip),
            SliverToBoxAdapter(child: SizedBox(height: bottom + 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _offers(
    BuildContext context,
    WidgetRef ref,
    DriverAccount driver,
    AsyncValue<List<Delivery>> offers,
    Delivery? trip,
  ) {
    if (!driver.isOnline) {
      return const [
        SliverToBoxAdapter(
          child: _BoardEmpty(
            icon: Icons.power_settings_new_rounded,
            title: 'You are off duty',
            message: 'Go online and offers from kitchens near you will appear here the moment they are placed.',
          ),
        ),
      ];
    }
    if (offers.hasError && !offers.hasValue) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorState(error: offers.error!, onRetry: () => ref.read(offersProvider.notifier).reload(silent: false)),
          ),
        ),
      ];
    }
    final list = offers.value;
    if (list == null) {
      return const [SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SkeletonList(count: 2, height: 220)))];
    }
    if (list.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: _BoardEmpty(
            icon: Icons.radar_rounded,
            title: 'No offers right now',
            message: 'Orders from kitchens within a few kilometres of you show up here. The board refreshes on its own.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => OfferCard(
            key: ValueKey(list[index].id),
            delivery: list[index],
            // One trip at a time keeps pickups on schedule.
            blockedReason: trip != null ? 'Finish your current delivery first' : null,
          ),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.driver, required this.unread});

  final DriverAccount driver;
  final int unread;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _greeting,
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              driver.firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
            ),
          ]),
        ),
        IconButton(
          tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: CountBadge(count: unread, child: const Icon(Icons.notifications_none_rounded, size: 28)),
        ),
      ]),
    );
  }
}

/// The on/off duty switch: the biggest thing on the screen, because it is
/// the one decision that changes everything else.
class _DutyCard extends ConsumerStatefulWidget {
  const _DutyCard({required this.driver, required this.onTrip});

  final DriverAccount driver;
  final bool onTrip;

  @override
  ConsumerState<_DutyCard> createState() => _DutyCardState();
}

class _DutyCardState extends ConsumerState<_DutyCard> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final goOnline = !widget.driver.isOnline;
    if (!goOnline && widget.onTrip) {
      final ok = await confirm(
        context,
        title: 'Go offline?',
        message: 'Your current delivery will be handed to another delivery worker.',
        confirmLabel: 'Go offline',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final change = await ref.read(driverActionsProvider).setOnline(goOnline);
      if (!mounted) return;
      if (change.online && !change.locationShared) {
        final access = ref.read(locationTrackerProvider).access;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('You are online, but your location is off, so offers may not be near you.'),
          action: access == null || access == LocationAccess.granted
              ? null
              : SnackBarAction(label: 'SETTINGS', onPressed: () => ref.read(locationServiceProvider).openSettings(access)),
        ));
      } else if (!change.online && change.reassigned > 0) {
        showSuccess(
          context,
          change.reassigned == 1
              ? 'You are offline. 1 delivery was handed to another worker.'
              : 'You are offline. ${change.reassigned} deliveries were handed to other workers.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = widget.driver.isOnline;
    final fg = online ? Colors.white : theme.colorScheme.onSurface;
    final sub = online ? Colors.white.withValues(alpha: 0.82) : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      child: AnimatedContainer(
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: online
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2F7D46), DriverColors.moss900],
                )
              : null,
          color: online ? null : theme.colorScheme.surface,
          border: online ? null : Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: online
              ? [BoxShadow(color: DriverColors.moss900.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10))]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? const Color(0xFF86EFAC) : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              online ? (widget.onTrip ? 'ON A DELIVERY' : 'ONLINE') : 'OFFLINE',
              style: theme.textTheme.labelSmall?.copyWith(color: sub, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            online ? 'You’re receiving offers' : 'Go online to start earning',
            style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15),
          ),
          const SizedBox(height: 4),
          Text(
            online
                ? 'Stay near kitchens. New orders appear below and ring this phone.'
                : 'Accept, collect and deliver. Earnings are credited the moment you hand over.',
            style: theme.textTheme.bodyMedium?.copyWith(color: sub, height: 1.35),
          ),
          const SizedBox(height: 18),
          PressScale(
            enabled: !_busy,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: online ? Colors.white.withValues(alpha: 0.16) : theme.colorScheme.primary,
                  foregroundColor: online ? Colors.white : theme.colorScheme.onPrimary,
                  side: online ? BorderSide(color: Colors.white.withValues(alpha: 0.4)) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onPressed: _busy ? null : _toggle,
                icon: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: online ? Colors.white : theme.colorScheme.onPrimary),
                      )
                    : const Icon(Icons.power_settings_new_rounded),
                label: Text(online ? 'Go offline' : 'Go online'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LocationNotice extends ConsumerWidget {
  const _LocationNotice({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = toneColors(context, Tone.warning);
    final access = state.access;
    final fixable = access != null && access != LocationAccess.granted;
    return AppCard(
      color: colors.background,
      borderColor: Colors.transparent,
      onTap: fixable
          ? () async {
              final tracker = ref.read(locationTrackerProvider.notifier);
              if (access == LocationAccess.denied) {
                await tracker.recheck();
              } else {
                await ref.read(locationServiceProvider).openSettings(access);
              }
            }
          : null,
      child: Row(children: [
        Icon(Icons.location_off_rounded, color: colors.foreground),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            state.message!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700),
          ),
        ),
        if (fixable) ...[
          const SizedBox(width: 8),
          Text(
            access == LocationAccess.denied ? 'Allow' : 'Settings',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.foreground),
          ),
        ],
      ]),
    );
  }
}

class _ContinueTrip extends StatelessWidget {
  const _ContinueTrip({required this.trip});

  final Delivery trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = trip.status == DeliveryStatus.assigned ? trip.vendor.name : trip.customer.name;
    return PressScale(
      child: AppCard(
        onTap: () => StatefulNavigationShell.of(context).goBranch(1),
        borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.route_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delivery in progress', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
              Text(
                '${TripStage.of(trip.status).label} · $heading',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.stats});

  final DriverStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String value, String label) => Expanded(
          child: Column(children: [
            Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        );
    final s = stats;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(children: [
          cell(s == null ? '—' : formatNumber(s.earningsTodayRwf), 'RWF today'),
          VerticalDivider(color: theme.colorScheme.outlineVariant, width: 1),
          cell(s == null ? '—' : '${s.completedToday}', s?.completedToday == 1 ? 'delivery' : 'deliveries'),
          VerticalDivider(color: theme.colorScheme.outlineVariant, width: 1),
          cell(s == null ? '—' : s.rating.toStringAsFixed(1), 'rating'),
        ]),
      ),
    );
  }
}

class _BoardEmpty extends StatelessWidget {
  const _BoardEmpty({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
          child: Icon(icon, color: theme.colorScheme.primary, size: 30),
        ),
        const SizedBox(height: 14),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
        ),
      ]),
    );
  }
}
