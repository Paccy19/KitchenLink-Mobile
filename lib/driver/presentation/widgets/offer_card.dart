import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../application/deliveries.dart';
import '../../models/delivery.dart';
import 'motion.dart';
import 'trip_widgets.dart';

/// One offer on the board. The pay is the biggest figure; the route reads
/// top to bottom (kitchen, then customer); Accept is the primary action.
class OfferCard extends ConsumerStatefulWidget {
  const OfferCard({super.key, required this.delivery, this.blockedReason});

  final Delivery delivery;

  /// Why this offer cannot be accepted right now (null = it can).
  final String? blockedReason;

  @override
  ConsumerState<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<OfferCard> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(driverActionsProvider).accept(widget.delivery.id);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showSuccess(context, 'Delivery accepted. Head to ${widget.delivery.vendor.name}.');
      // The Trip tab: StatefulShellRoute branch 1.
      context.go('/trip');
    } on ApiException catch (error) {
      // e.g. another delivery worker accepted first.
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await ref.read(driverActionsProvider).decline(widget.delivery.id);
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.delivery;
    final blocked = widget.blockedReason;
    final rules = d.pickupRules;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                d.vendor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
              ),
              const SizedBox(height: 4),
              StatusChip(
                dense: true,
                tone: d.kitchenReady ? Tone.success : Tone.warning,
                icon: d.kitchenReady ? Icons.check_rounded : Icons.soup_kitchen_rounded,
                label: d.kitchenReady
                    ? 'Ready for pickup'
                    : d.expectedReadyAt != null
                        ? 'Cooking · ready ~${formatTime(d.expectedReadyAt)}'
                        : 'Kitchen preparing',
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            MoneyFigure(d.promisedEarningsRwf, size: 26, color: theme.colorScheme.primary),
            Text('you earn', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ]),
        const SizedBox(height: 16),
        _Route(pickup: d.pickup, dropoff: d.dropoff),
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 6, children: [
          if (d.distanceFromDriverKm != null)
            _Meta(icon: Icons.near_me_rounded, text: '${d.distanceFromDriverKm!.toStringAsFixed(1)} km to kitchen'),
          if (d.routeDistanceKm != null && d.routeDistanceKm! > 0)
            _Meta(icon: Icons.route_rounded, text: '${d.routeDistanceKm!.toStringAsFixed(1)} km trip'),
          if (d.itemCount > 0) _Meta(icon: Icons.shopping_bag_outlined, text: '${d.itemCount} item${d.itemCount == 1 ? '' : 's'}'),
        ]),
        if (rules != null) ...[
          const SizedBox(height: 12),
          Text(
            'Collect within ${rules.chargeAfterMinutes} min of the food being ready'
            '${rules.reassignAfterMinutes != null ? '. After ${rules.reassignAfterMinutes} min it goes to another worker' : ''}.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
          ),
        ],
        const SizedBox(height: 14),
        if (blocked != null)
          Text(blocked, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: _busy ? null : _decline, child: const Text('Decline')),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PressScale(
                enabled: !_busy,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _accept,
                  icon: _busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: theme.colorScheme.onPrimary),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Accept'),
                ),
              ),
            ),
          ]),
      ]),
    );
  }
}

class _Route extends StatelessWidget {
  const _Route({required this.pickup, required this.dropoff});

  final TripPoint pickup;
  final TripPoint dropoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stop(Color color, IconData icon, String title, String subtitle) => Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle.isNotEmpty)
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]);

    return Column(children: [
      stop(const Color(0xFFB7791F), Icons.storefront_rounded, pickup.address.isEmpty ? 'Kitchen' : pickup.address, pickup.neighborhood),
      Padding(
        padding: const EdgeInsets.only(left: 13),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(width: 2, height: 14, color: theme.colorScheme.outlineVariant),
        ),
      ),
      stop(const Color(0xFF047857), Icons.location_on_rounded, dropoff.address.isEmpty ? 'Customer' : dropoff.address, dropoff.neighborhood),
    ]);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: theme.colorScheme.primary),
      const SizedBox(width: 4),
      Text(text, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
