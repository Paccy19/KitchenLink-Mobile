import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion rules for every part of the app, from Apple's fluid-interface
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
/// back when it lifts. With a mouse or trackpad (web, tablets, desktops) it
/// also lifts slightly while hovered and shows the hand cursor. Wrap
/// tappable cards and big buttons.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true, this.pressedScale = 0.97, this.hoverScale = 1.015});

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final double hoverScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);
  bool _hovered = false;
  bool _pressed = false;

  void _update() {
    final target = !widget.enabled ? 1.0 : (_pressed ? widget.pressedScale : (_hovered ? widget.hoverScale : 1.0));
    if (reduceMotion(context)) {
      _scale.value = 1;
      return;
    }
    // From the value on screen now, carrying its velocity: interruptible.
    _scale.animateWith(SpringSimulation(spring(response: _pressed ? 0.22 : 0.32), _scale.value, target, _scale.velocity));
  }

  void _press(bool down) {
    _pressed = down;
    _update();
  }

  void _hover(bool over) {
    _hovered = over;
    _update();
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: Listener(
          onPointerDown: widget.enabled ? (_) => _press(true) : null,
          onPointerUp: (_) => _press(false),
          onPointerCancel: (_) => _press(false),
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
            child: widget.child,
          ),
        ),
      );
}

/// Fades and rises into place once, the first time it is built: sections of
/// a screen arriving in sequence ([index] staggers them by 60 ms). With
/// reduce motion on, a plain short fade.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.distance = 18});

  final Widget child;
  final int index;
  final double distance;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // The stagger is the start of one animation (no timers): the first
  // [delay] of it is held still.
  int get _delay => 60 * widget.index.clamp(0, 8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 520 + _delay))..forward();
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Interval(_delay / (520 + _delay), 1, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: still ? child : Transform.translate(offset: Offset(0, (1 - _t.value) * widget.distance), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Gives its child a quick spring "bump" whenever [value] changes (the basket
/// count after an add, a saved heart). Nothing moves with reduce motion on.
class Bump extends StatefulWidget {
  const Bump({super.key, required this.value, required this.child, this.scale = 1.22});

  final Object? value;
  final Widget child;
  final double scale;

  @override
  State<Bump> createState() => _BumpState();
}

class _BumpState extends State<Bump> with SingleTickerProviderStateMixin {
  late final AnimationController _s = AnimationController.unbounded(vsync: this, value: 1);

  @override
  void didUpdateWidget(Bump old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value || reduceMotion(context)) return;
    // Kick outward with velocity and let a slightly bouncy spring settle it.
    _s.value = widget.scale;
    _s.animateWith(SpringSimulation(spring(dampingRatio: 0.55, response: 0.3), widget.scale, 1, 0));
  }

  @override
  void dispose() {
    _s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _s,
        builder: (context, child) => Transform.scale(scale: _s.value, child: child),
        child: widget.child,
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
