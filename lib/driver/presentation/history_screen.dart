import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../application/deliveries.dart';
import 'earnings_screen.dart';

/// Every past delivery, newest first, loaded page by page.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery history')),
      body: AsyncBody<HistoryState>(
        value: history,
        onRefresh: () => ref.read(historyProvider.notifier).reload(),
        builder: (context, state) {
          if (state.items.isEmpty) {
            return const RefreshableEmpty(
              icon: Icons.history_rounded,
              title: 'No deliveries yet',
              message: 'Your completed and cancelled deliveries will be listed here.',
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 400 && state.hasMore && !state.loadingMore) {
                ref.read(historyProvider.notifier).loadMore().catchError((Object error) {
                  if (context.mounted) showError(context, error);
                });
              }
              return false;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.paddingOf(context).bottom + 24),
              itemCount: state.items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: state.loadingMore
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : Text(
                              state.hasMore ? '' : 'That’s everything',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                    ),
                  );
                }
                return AppCard(padding: EdgeInsets.zero, child: DeliveryRow(delivery: state.items[index]));
              },
            ),
          );
        },
      ),
    );
  }
}
