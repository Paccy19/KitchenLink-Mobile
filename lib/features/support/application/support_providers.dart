import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../models/support.dart';

class SupportListNotifier extends PolledNotifier<SupportList> {
  @override
  Duration? get pollInterval => const Duration(seconds: 30);

  @override
  Future<SupportList> fetch() => ref.read(supportRepositoryProvider).list();
}

final supportListProvider =
    AsyncNotifierProvider.autoDispose<SupportListNotifier, SupportList>(SupportListNotifier.new);

class SupportUnreadNotifier extends PolledNotifier<int> {
  @override
  Duration? get pollInterval => const Duration(seconds: 30);

  @override
  Future<int> fetch() => ref.read(supportRepositoryProvider).unreadCount();
}

final supportUnreadProvider =
    AsyncNotifierProvider.autoDispose<SupportUnreadNotifier, int>(SupportUnreadNotifier.new);

class SupportTicketNotifier extends PolledNotifier<SupportTicket> {
  SupportTicketNotifier(this.id);
  final String id;

  @override
  Duration? get pollInterval => const Duration(seconds: 10);

  @override
  Future<SupportTicket> fetch() => ref.read(supportRepositoryProvider).ticket(id);

  Future<void> reply(String message) async {
    final ticket = await ref.read(supportRepositoryProvider).reply(id, message);
    put(ticket);
    ref.invalidate(supportListProvider);
  }
}

final supportTicketProvider = AsyncNotifierProvider.autoDispose
    .family<SupportTicketNotifier, SupportTicket, String>(SupportTicketNotifier.new);

class SupportActions {
  SupportActions(this._ref);
  final Ref _ref;

  Future<SupportTicket> create({
    required String subject,
    required String message,
    required String category,
    String? orderId,
  }) async {
    final ticket = await _ref
        .read(supportRepositoryProvider)
        .create(subject: subject, message: message, category: category, orderId: orderId);
    _ref.invalidate(supportListProvider);
    _ref.invalidate(supportUnreadProvider);
    return ticket;
  }
}

final supportActionsProvider = Provider<SupportActions>(SupportActions.new);
