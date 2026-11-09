import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../application/deliveries.dart';
import '../models/delivery.dart';
import '../models/navigation.dart';
import 'confirm_delivery_sheet.dart';
import 'widgets/route_map.dart';
import 'widgets/slide_to_confirm.dart';
import 'widgets/trip_widgets.dart';

/// The delivery in progress: where to go, what to collect, who to call, and
/// the one next step, pinned to the bottom.
class TripScreen extends ConsumerWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(activeTripProvider);
    return Scaffold(
      body: trip.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const SafeArea(child: Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3, height: 140))),
        error: (error, _) => SafeArea(
          child: ErrorState(error: error, onRetry: () => ref.read(activeTripProvider.notifier).reload(silent: false)),
        ),
        data: (delivery) => delivery == null ? const _NoTrip() : _Trip(delivery: delivery),
      ),
    );
  }
}

class _NoTrip extends ConsumerWidget {
  const _NoTrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
        onRefresh: () => ref.read(activeTripProvider.notifier).reload(silent: false).catchError((_) {}),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: EmptyState(
                icon: Icons.route_rounded,
                title: 'No delivery in progress',
                message: 'Accept an offer and your trip appears here: the route, the pickup clock and the customer’s details.',
                action: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                  onPressed: () => StatefulNavigationShell.of(context).goBranch(0),
                  icon: const Icon(Icons.local_offer_rounded),
                  label: const Text('See offers'),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Trip extends ConsumerWidget {
  const _Trip({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nav = ref.watch(tripNavigationProvider(delivery.id));
    final fix = ref.watch(lastFixProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final action = delivery.nextAction;
    final toKitchen = delivery.status == DeliveryStatus.assigned;

    return Stack(children: [
      RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: () async {
          await Future.wait([
            ref.read(activeTripProvider.notifier).reload(silent: false),
            ref.read(tripNavigationProvider(delivery.id).notifier).reload(silent: false),
          ]).catchError((_) => const <void>[]);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, bottom + 190),
          children: [
            // Title block: where am I in this delivery?
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'ORDER ${delivery.orderNumber}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toKitchen ? 'To the kitchen' : 'To the customer',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  MoneyFigure(delivery.promisedEarningsRwf, size: 22, color: theme.colorScheme.primary),
                  Text('your payout', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            TripProgress(status: delivery.status),
            const SizedBox(height: 16),
            PickupClock(delivery: delivery),
            if (delivery.status == DeliveryStatus.assigned || delivery.latePickup != null) const SizedBox(height: 12),
            _Navigation(delivery: delivery, nav: nav, rider: fix == null ? null : GeoPoint(fix.latitude, fix.longitude)),
            const GroupLabel('Pickup'),
            _PlaceCard(
              icon: Icons.storefront_rounded,
              color: const Color(0xFFB7791F),
              title: delivery.vendor.name,
              point: delivery.pickup,
              phone: delivery.vendor.phone,
              callLabel: 'Call kitchen',
              done: !toKitchen,
            ),
            const GroupLabel('Drop-off'),
            _PlaceCard(
              icon: Icons.person_rounded,
              color: const Color(0xFF047857),
              title: delivery.customer.name,
              point: delivery.dropoff,
              phone: delivery.customer.phone,
              callLabel: 'Call customer',
              canText: true,
            ),
            GroupLabel(
              'Order contents',
              trailing: Text('${delivery.itemCount} item${delivery.itemCount == 1 ? '' : 's'}', style: theme.textTheme.labelMedium),
            ),
            _Items(items: delivery.items),
            if (delivery.progress.isNotEmpty) ...[
              const GroupLabel('What the customer sees'),
              _Timeline(entries: delivery.progress),
            ],
          ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _ActionPanel(delivery: delivery, action: action, bottomInset: bottom),
      ),
    ]);
  }
}

/// Map, next turn and ETA, with a hand-off to the phone's maps app.
class _Navigation extends StatelessWidget {
  const _Navigation({required this.delivery, required this.nav, this.rider});

  final Delivery delivery;
  final AsyncValue<TripNavigation> nav;
  final GeoPoint? rider;

  Future<void> _openMaps(BuildContext context, TripPoint point) async {
    if (!point.hasPosition) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${point.latitude},${point.longitude}&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showError(context, 'Could not open the maps app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = delivery.status == DeliveryStatus.assigned ? delivery.pickup : delivery.dropoff;
    final data = nav.value;

    return AppCard(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data != null)
          RouteMap(navigation: data, rider: rider)
        else
          Container(
            height: 240,
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: nav.hasError
                ? Text('The route could not be loaded.', style: theme.textTheme.bodySmall)
                : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  data?.nextStep?.instruction.isNotEmpty == true ? data!.nextStep!.instruction : (data?.phaseLabel ?? 'Route'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (data?.distanceM != null) _distance(data!.distanceM!),
                    if (data?.durationS != null) '${(data!.durationS! / 60).ceil()} min',
                    if (data?.etaAt != null) 'arrive ${formatTime(data!.etaAt)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: target.hasPosition ? () => _openMaps(context, target) : null,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Navigate'),
            ),
          ]),
        ),
      ]),
    );
  }

  String _distance(double metres) => metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.point,
    required this.phone,
    required this.callLabel,
    this.canText = false,
    this.done = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final TripPoint point;
  final String phone;
  final String callLabel;
  final bool canText;
  final bool done;

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri) && context.mounted) showError(context, 'This phone cannot open $uri.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
            child: Icon(done ? Icons.check_rounded : icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (point.address.isNotEmpty) Text(point.address, style: theme.textTheme.bodyMedium),
              if (point.neighborhood.isNotEmpty)
                Text(point.neighborhood, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        if (point.note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(12)),
            child: Text('“${point.note}”', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _launch(context, Uri(scheme: 'tel', path: phone)),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text(callLabel),
              ),
            ),
            if (canText) ...[
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Send a text message',
                onPressed: () => _launch(context, Uri(scheme: 'sms', path: phone)),
                icon: const Icon(Icons.sms_rounded, size: 20),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.items});

  final List<DeliveryItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return AppCard(child: Text('No item details for this order.', style: theme.textTheme.bodyMedium));
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(indent: 56, color: theme.colorScheme.outlineVariant),
          ListTile(
            leading: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
              child: Text('${items[i].quantity}×', style: theme.textTheme.labelLarge),
            ),
            title: Text(items[i].name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: items[i].options.isEmpty ? null : Text(items[i].options),
          ),
        ],
      ]),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<ProgressEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(children: [
        for (var i = 0; i < entries.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: i == entries.length - 1 ? theme.colorScheme.primary : theme.colorScheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
              if (i < entries.length - 1) Container(width: 2, height: 30, color: theme.colorScheme.outlineVariant),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entries[i].label,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: i == entries.length - 1 ? FontWeight.w800 : FontWeight.w500),
              ),
            ),
            Text(
              formatTime(entries[i].at),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ]),
      ]),
    );
  }
}

/// The next step on a translucent panel the trip scrolls under.
class _ActionPanel extends ConsumerWidget {
  const _ActionPanel({required this.delivery, required this.action, required this.bottomInset});

  final Delivery delivery;
  final TripAction? action;
  final double bottomInset;

  Future<void> _run(BuildContext context, WidgetRef ref, TripAction action) async {
    if (action.kind == TripActionKind.handOver) {
      // Completing clears this trip (and this widget), so the result is shown
      // from the root navigator, which stays mounted.
      final root = Navigator.of(context, rootNavigator: true).context;
      final completion = await showConfirmDeliverySheet(context, delivery);
      if (completion != null && root.mounted) await showDeliveredDialog(root, completion);
      return;
    }
    try {
      await ref.read(driverActionsProvider).advance(delivery, action.toStatus!);
      HapticFeedback.heavyImpact();
      if (context.mounted) {
        showSuccess(context, action.kind == TripActionKind.confirmPickup ? 'Pickup confirmed.' : 'On your way. The customer can follow you.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waiting = delivery.waitingForKitchen;
    final solid = MediaQuery.maybeHighContrastOf(context) ?? false;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset + 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (action != null) ...[
          Text(waiting ? 'Wait near the kitchen' : action!.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            waiting
                ? 'You can confirm pickup as soon as the kitchen marks the food ready.'
                : action!.hint,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SlideToConfirm(
            key: ValueKey('${delivery.id}-${delivery.status}'),
            label: action!.slideLabel,
            disabledLabel: 'Waiting for the kitchen…',
            enabled: !waiting,
            icon: action!.kind == TripActionKind.handOver ? Icons.pin_rounded : Icons.arrow_forward_rounded,
            onConfirmed: () => _run(context, ref, action!),
          ),
        ] else
          Row(children: [
            Icon(Icons.hourglass_top_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waiting for the server to allow the next step. Pull down to refresh.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ]),
      ]),
    );

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: solid ? 1 : 0.86),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.5)),
      ),
      child: content,
    );
    if (solid) return panel;
    return ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: panel));
  }
}
