import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'components.dart';

/// The standard body of a data screen: skeleton while loading, an error with
/// "Try again", pull-to-refresh, and the content centred on wide screens.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    required this.onRefresh,
    this.skeleton,
    this.maxWidth = 640,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final Future<void> Function() onRefresh;
  final Widget? skeleton;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // Keep showing old data while a refresh fails in the background.
    if (value.hasValue && !value.hasError) return _content(context, value.requireValue);
    if (value.hasError) {
      return ErrorState(error: value.error!, onRetry: () => onRefresh().catchError((_) {}));
    }
    return skeleton ?? const SkeletonList();
  }

  Widget _content(BuildContext context, T data) => RefreshIndicator(
        onRefresh: onRefresh,
        child: Center(
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: builder(context, data)),
        ),
      );
}

/// A pull-to-refresh friendly empty state (the scroll view is always scrollable).
class RefreshableEmpty extends StatelessWidget {
  const RefreshableEmpty({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: EmptyState(icon: icon, title: title, message: message, action: action),
          ),
        ),
      );
}
