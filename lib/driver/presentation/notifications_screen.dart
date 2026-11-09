import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/feedback.dart';
import '../application/deliveries.dart';
import '../models/driver_notification.dart';

class DriverNotificationsScreen extends ConsumerWidget {
  const DriverNotificationsScreen({super.key});

  IconData _icon(DriverNotification n) {
    if (n.isOffer) return Icons.delivery_dining_rounded;
    if (n.type == 'delivery_ready') return Icons.check_circle_rounded;
    if (n.type == 'delivery_pickup_reminder' || n.type == 'delivery_late') return Icons.timer_rounded;
    if (n.endsTrip) return Icons.cancel_rounded;
    if (n.isMoney) return Icons.payments_rounded;
    return Icons.notifications_rounded;
  }

  void _open(BuildContext context, WidgetRef ref, DriverNotification n) {
    if (!n.read) {
      ref.read(driverNotificationsProvider.notifier).markRead(n.id).catchError((_) {});
    }
    if (n.isOffer) {
      context.go('/home');
    } else if (n.isTripUpdate) {
      context.go('/trip');
    } else if (n.isMoney) {
      context.go('/earnings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverNotificationsProvider);
    final theme = Theme.of(context);
    final unread = state.value?.unreadCount ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => runAction(context, () => ref.read(driverNotificationsProvider.notifier).markAllRead()),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: AsyncBody<DriverNotificationList>(
        value: state,
        onRefresh: () => ref.read(driverNotificationsProvider.notifier).reload(silent: false),
        builder: (context, list) {
          if (list.items.isEmpty) {
            return const RefreshableEmpty(
              icon: Icons.notifications_none_rounded,
              title: 'All quiet',
              message: 'New offers, food-ready alerts and payout updates show up here.',
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.items.length,
            separatorBuilder: (_, _) => Divider(indent: 72, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, index) {
              final n = list.items[index];
              return ListTile(
                onTap: () => _open(context, ref, n),
                leading: CircleAvatar(
                  backgroundColor: n.read ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primaryContainer,
                  foregroundColor: n.read ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
                  child: Icon(_icon(n), size: 20),
                ),
                title: Text(
                  n.title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w800),
                ),
                subtitle: Text('${n.body}\n${timeAgo(n.createdAt)}', maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: n.read
                    ? null
                    : Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
