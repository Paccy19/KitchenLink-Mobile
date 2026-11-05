import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../models/app_notification.dart';

/// The kitchen's notifications. The backend has no push service yet, so they
/// are polled every 15 seconds while the app is open.
class NotificationsNotifier extends PolledNotifier<NotificationPage> {
  @override
  Duration? get pollInterval => const Duration(seconds: 15);

  @override
  Future<NotificationPage> fetch() => ref.read(notificationsRepositoryProvider).list();

  /// Marks one read: shown at once, then confirmed by the backend. If the
  /// backend refuses, the list is reloaded so it never shows a false state.
  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    final target = current.items.where((item) => item.id == id && !item.read);
    if (target.isEmpty) return;
    put(NotificationPage(
      items: [for (final item in current.items) item.id == id ? item.markRead() : item],
      unreadCount: (current.unreadCount - 1).clamp(0, 1 << 30),
    ));
    try {
      await ref.read(notificationsRepositoryProvider).markRead(id);
    } catch (_) {
      await reload();
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    await ref.read(notificationsRepositoryProvider).markAllRead();
    put(NotificationPage(
      items: [for (final item in current.items) item.markRead()],
      unreadCount: 0,
    ));
  }
}

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsNotifier, NotificationPage>(NotificationsNotifier.new);
