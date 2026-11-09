import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion rules for the delivery worker app, from Apple's fluid-interface
/// guidance: springs (not fixed-duration curves) for anything a finger
/// touches, critically damped by default, a little bounce only after a flick,
/// and a cross-fade instead of movement when the phone asks for less motion.

/// A spring described the way designers think: [dampingRatio] (1 = no
/// overshoot) and [response] (seconds to reach the target; not a duration).
SpringDescription spring({double dampingRatio = 1.0, double response = 0.35}) {
  final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
  final damping = 4 * math.pi * dampingRatio / response;
  return SpringDescription(mass: 1, stiffness: stiffness, damping: damping);
}

/// Default for UI: no bounce.
final SpringDescription settleSpring = spring();

/// After a flick that carried momentum: a slight bounce feels physical.
final SpringDescription flickSpring = spring(dampingRatio: 0.8, response: 0.3);

/// Where a flick would come to rest, like scroll deceleration
/// (Apple's projection: `v / 1000 × d / (1 − d)`).
double projectMomentum(double velocityPerSecond, {double decelerationRate = 0.998}) =>
    (velocityPerSecond / 1000) * decelerationRate / (1 - decelerationRate);

/// Resistance past an edge: the further it is pulled, the less it follows.
double rubberBand(double overshoot, double dimension, {double constant = 0.55}) =>
    (overshoot * dimension * constant) / (dimension + constant * overshoot.abs());

/// The phone's "reduce motion" setting.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Shrinks a little the moment a finger lands (not on release) and springs
/// back when it lifts. Wrap tappable cards and big buttons.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true, this.pressedScale = 0.97});

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target) {
    if (reduceMotion(context)) {
      _scale.value = 1;
      return;
    }
    // From the value on screen now, carrying its velocity: interruptible.
    _scale.animateWith(SpringSimulation(spring(response: 0.25), _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) => _to(widget.pressedScale) : null,
        onPointerUp: (_) => _to(1),
        onPointerCancel: (_) => _to(1),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: widget.child,
        ),
      );
}

/// Switches between two states with a short cross-fade (and a small rise
/// unless the phone asks for reduced motion).
class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (still) return FadeTransition(opacity: animation, child: child);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
