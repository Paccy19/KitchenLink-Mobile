import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../application/notifications_providers.dart';
import '../models/app_notification.dart';

(IconData, Tone) _metaFor(String type) => switch (type) {
      'order_placed' => (Icons.shopping_bag_rounded, Tone.success),
      'order_update' => (Icons.receipt_long_rounded, Tone.info),
      'payout_update' => (Icons.account_balance_wallet_rounded, Tone.brand),
      'account_update' => (Icons.verified_user_rounded, Tone.warning),
      'support_message' => (Icons.support_agent_rounded, Tone.danger),
      'chat_message' => (Icons.chat_bubble_rounded, Tone.info),
      'pickup_code' || 'delivery_code' => (Icons.pin_rounded, Tone.warning),
      _ => (Icons.notifications_rounded, Tone.neutral),
    };

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification item) async {
    if (!item.read) {
      // Opening it marks it read; a failed mark must not block navigation.
      ref.read(notificationsProvider.notifier).markRead(item.id).catchError((_) {});
    }
    final route = item.route;
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final unread = state.value?.unreadCount ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => runAction(context, () => ref.read(notificationsProvider.notifier).markAllRead(), success: 'All marked as read.'),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: AsyncBody<NotificationPage>(
        value: state,
        onRefresh: () => ref.read(notificationsProvider.notifier).reload(silent: false),
        builder: (context, page) {
          if (page.items.isEmpty) {
            return const RefreshableEmpty(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message: 'New orders, payouts and messages from support will show up here.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: page.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = page.items[index];
              final (icon, tone) = _metaFor(item.type);
              final colors = toneColors(context, tone);
              return AppCard(
                onTap: () => _open(context, ref, item),
                color: item.read ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 20, color: colors.foreground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(item.title, style: theme.textTheme.titleSmall)),
                        if (!item.read) Container(width: 9, height: 9, decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle)),
                      ]),
                      const SizedBox(height: 2),
                      Text(item.body, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(timeAgo(item.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
