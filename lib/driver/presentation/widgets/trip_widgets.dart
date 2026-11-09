import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../models/delivery.dart';

String _clock(Duration left) {
  final total = left.isNegative ? 0 : left.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Tabular figures, so a ticking countdown does not jitter.
const _tabular = [FontFeature.tabularFigures()];

/// Where the worker stands on collecting the food, using the admin's timing
/// rules: wait near the kitchen while it cooks, then a countdown to when the
/// pickup is late, then to when the order is given to another worker (if the
/// admin turned that on). Late pickups are never charged (the backend pays
/// the full delivery fee).
class PickupClock extends StatefulWidget {
  const PickupClock({super.key, required this.delivery});

  final Delivery delivery;

  @override
  State<PickupClock> createState() => _PickupClockState();
}

class _PickupClockState extends State<PickupClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  bool get _ticking =>
      widget.delivery.status == DeliveryStatus.assigned &&
      widget.delivery.kitchenReady &&
      widget.delivery.pickupDueAt != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PickupClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_ticking && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!_ticking) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final rules = delivery.pickupRules;
    final waiting = delivery.status == DeliveryStatus.assigned;

    if (!waiting) {
      final late = delivery.latePickup;
      if (late == null) return const SizedBox.shrink();
      final minutes = late.minutesLate;
      return _Panel(
        tone: Tone.danger,
        icon: Icons.warning_amber_rounded,
        title: 'Late pickup',
        message:
            'Collected${minutes != null ? ' $minutes minute${minutes == 1 ? '' : 's'}' : ''} late. You are still paid the full delivery fee.',
      );
    }

    if (!delivery.kitchenReady) {
      final ready = delivery.expectedReadyAt;
      final rulesText = rules == null
          ? ''
          : ' Once it is ready you have ${rules.chargeAfterMinutes} minutes to collect it'
              '${rules.reassignAfterMinutes != null ? '; after ${rules.reassignAfterMinutes} minutes it goes to another delivery worker' : ''}.';
      return _Panel(
        tone: Tone.warning,
        icon: Icons.soup_kitchen_rounded,
        title: 'The kitchen is preparing this order',
        message: 'Head to the kitchen now and wait nearby${ready != null ? '. It should be ready around ${formatTime(ready)}' : ''}.$rulesText',
      );
    }

    final due = delivery.pickupDueAt;
    if (due == null) {
      return const _Panel(
        tone: Tone.success,
        icon: Icons.check_circle_rounded,
        title: 'The food is ready',
        message: 'Collect it from the kitchen now.',
      );
    }
    final dueLeft = due.difference(_now);
    final reassignAt = delivery.pickupReassignAt;
    final late = delivery.latePickup != null || dueLeft.isNegative;

    if (late) {
      return _Panel(
        tone: Tone.danger,
        icon: Icons.warning_amber_rounded,
        title: 'Late. Collect it now',
        message: reassignAt != null
            ? 'If you have not collected it by ${formatTime(reassignAt)}, the order goes to another delivery worker.'
            : 'Support has been alerted.',
        figure: reassignAt != null ? _clock(reassignAt.difference(_now)) : null,
        figureCaption: reassignAt != null ? 'until reassigned' : null,
      );
    }

    final urgent = dueLeft <= const Duration(minutes: 5);
    return _Panel(
      tone: urgent ? Tone.danger : Tone.success,
      icon: Icons.timer_rounded,
      title: 'The food is ready. Collect it now',
      message: 'Pick it up by ${formatTime(due)}'
          '${reassignAt != null ? '; at ${formatTime(reassignAt)} it goes to another delivery worker' : ''}.',
      figure: _clock(dueLeft),
      figureCaption: 'to collect',
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    this.figure,
    this.figureCaption,
  });

  final Tone tone;
  final IconData icon;
  final String title;
  final String message;
  final String? figure;
  final String? figureCaption;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, tone);
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: figure != null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(20)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: colors.foreground, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.titleSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(message, style: text.bodySmall?.copyWith(color: colors.foreground, height: 1.35)),
            ]),
          ),
          if (figure != null) ...[
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                figure!,
                style: text.headlineSmall?.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  fontFeatures: _tabular,
                ),
              ),
              if (figureCaption != null)
                Text(
                  figureCaption!.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// To kitchen → Collected → On the way → Delivered.
class TripProgress extends StatelessWidget {
  const TripProgress({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = TripStage.of(status).index;
    return Semantics(
      label: 'Step ${current + 1} of ${TripStage.values.length}: ${TripStage.values[current].label}',
      excludeSemantics: true,
      child: Row(children: [
        for (final stage in TripStage.values) ...[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 4,
                decoration: BoxDecoration(
                  color: stage.index <= current ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stage.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  fontWeight: stage.index == current ? FontWeight.w800 : FontWeight.w600,
                  color: stage.index <= current ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ]),
          ),
          if (stage != TripStage.values.last) const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

/// A small caps label above a group, Apple-style (positive tracking at small sizes).
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

/// A big money figure with negative tracking (large type reads tighter).
class MoneyFigure extends StatelessWidget {
  const MoneyFigure(this.amountRwf, {super.key, this.size = 34, this.color, this.prefix = ''});

  final int amountRwf;
  final double size;
  final Color? color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.03 * size,
          height: 1.05,
          color: color,
          fontFeatures: _tabular,
        );
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$prefix${formatNumber(amountRwf)}'),
        TextSpan(
          text: ' RWF',
          style: style?.copyWith(fontSize: size * 0.42, letterSpacing: 0.2, fontWeight: FontWeight.w700),
        ),
      ]),
      style: style,
    );
  }
}
