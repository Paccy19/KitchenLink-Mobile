import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

/// A track with a knob the worker slides to the end to commit a trip step
/// that cannot be undone (pickup, start, hand-over).
///
/// It follows the finger 1:1 from where it was grabbed, resists past the
/// ends, and on release projects the flick forward: a quick short flick
/// commits, a slow drag that stops halfway springs back. The spring starts
/// at the finger's own velocity, so there is no seam between drag and motion.
/// A tap nudges the knob toward the end to show which way to slide; screen
/// readers get a plain "activate" action.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.icon = Icons.arrow_forward_rounded,
    this.disabledLabel,
  });

  final String label;

  /// Runs when the knob reaches the end. The knob waits there (with a
  /// spinner) until it completes, then returns to the start.
  final Future<void> Function() onConfirmed;
  final bool enabled;
  final IconData icon;

  /// Shown instead of [label] while disabled (e.g. "Waiting for the kitchen").
  final String? disabledLabel;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with SingleTickerProviderStateMixin {
  static const double _height = 64;
  static const double _pad = 4;
  static const double _knob = _height - _pad * 2;

  late final AnimationController _x = AnimationController.unbounded(vsync: this);
  double _travel = 1;
  double _grabOffset = 0;
  bool _busy = false;

  double get _progress => (_x.value / _travel).clamp(0.0, 1.0);

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  void _animateTo(double target, {double velocity = 0, SpringDescription? description}) {
    if (reduceMotion(context)) {
      _x.value = target;
      return;
    }
    _x.animateWith(SpringSimulation(description ?? settleSpring, _x.value, target, velocity));
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _busy) return;
    _x.stop(); // Grab it mid-flight: it stays under the finger.
    _grabOffset = details.localPosition.dx - _pad - _x.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _busy) return;
    final raw = details.localPosition.dx - _pad - _grabOffset;
    if (raw < 0) {
      _x.value = rubberBand(raw, _travel);
    } else if (raw > _travel) {
      _x.value = _travel + rubberBand(raw - _travel, _travel);
    } else {
      _x.value = raw;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _busy) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final projected = _x.value + projectMomentum(velocity);
    // Decide on where the gesture was going, not where the finger let go.
    if (projected >= _travel * 0.85 && velocity >= -50) {
      _commit(velocity);
    } else {
      _animateTo(0, velocity: velocity);
    }
  }

  Future<void> _commit([double velocity = 0]) async {
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    _animateTo(_travel, velocity: velocity);
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _animateTo(0);
      }
    }
  }

  void _nudge() {
    if (!widget.enabled || _busy || reduceMotion(context)) return;
    // Hint in the direction of the gesture: a small push that springs back.
    _x.animateWith(SpringSimulation(flickSpring, _x.value, 0, 900));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    final track = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final onTrack = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final text = enabled ? widget.label : (widget.disabledLabel ?? widget.label);

    return Semantics(
      button: true,
      enabled: enabled && !_busy,
      label: text,
      onTap: enabled && !_busy ? _commit : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        _travel = (constraints.maxWidth - _knob - _pad * 2).clamp(1.0, double.infinity);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _nudge,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _height,
            decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(_height / 2)),
            child: AnimatedBuilder(
              animation: _x,
              builder: (context, _) {
                final progress = _progress;
                return Stack(alignment: Alignment.centerLeft, children: [
                  // The filled part behind the knob shows how far there is to go.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (_x.value.clamp(0.0, _travel)) + _knob + _pad * 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: onTrack.withValues(alpha: enabled ? 0.14 : 0),
                        borderRadius: BorderRadius.circular(_height / 2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: _knob + 20, right: 20),
                    child: Opacity(
                      opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: onTrack,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.1,
                            ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _pad + _x.value,
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: BoxDecoration(
                        color: enabled ? scheme.onPrimary : scheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: _busy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.6, color: scheme.primary),
                            )
                          : Icon(
                              enabled ? widget.icon : Icons.hourglass_top_rounded,
                              color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        );
      }),
    );
  }
}
