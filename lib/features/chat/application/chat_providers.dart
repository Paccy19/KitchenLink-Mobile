import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../models/chat.dart';

class ChatListNotifier extends PolledNotifier<List<ChatConversation>> {
  @override
  Duration? get pollInterval => const Duration(seconds: 15);

  @override
  Future<List<ChatConversation>> fetch() => ref.read(chatRepositoryProvider).conversations();
}

final chatListProvider =
    AsyncNotifierProvider.autoDispose<ChatListNotifier, List<ChatConversation>>(ChatListNotifier.new);

/// Unread customer messages, for the badge. Polled while the shell is open.
class ChatUnreadNotifier extends PolledNotifier<int> {
  @override
  Duration? get pollInterval => const Duration(seconds: 20);

  @override
  Future<int> fetch() => ref.read(chatRepositoryProvider).unreadCount();
}

final chatUnreadProvider =
    AsyncNotifierProvider.autoDispose<ChatUnreadNotifier, int>(ChatUnreadNotifier.new);

/// One conversation. Opening it marks it read on the server; while it is open
/// only messages newer than the last one are fetched, every 5 seconds.
class ChatThreadNotifier extends PolledNotifier<ChatThread> {
  ChatThreadNotifier(this.id);
  final String id;

  @override
  Duration? get pollInterval => const Duration(seconds: 5);

  @override
  Future<ChatThread> fetch() async {
    final repo = ref.read(chatRepositoryProvider);
    final current = state.value;
    final last = current?.messages.isEmpty ?? true ? null : current!.messages.last.createdAt;
    if (current == null || last == null) return repo.thread(id);
    final newer = await repo.thread(id, after: last);
    return ChatThread(
      conversation: newer.conversation,
      messages: mergeMessages(current.messages, newer.messages),
      hasMore: current.hasMore,
      privacyNote: newer.privacyNote.isEmpty ? current.privacyNote : newer.privacyNote,
    );
  }

  /// Older messages, when the conversation is longer than one page.
  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.messages.isEmpty) return;
    final first = current.messages.first.createdAt;
    if (first == null) return;
    final older = await ref.read(chatRepositoryProvider).thread(id, before: first);
    if (!ref.mounted) return;
    put(ChatThread(
      conversation: current.conversation,
      messages: mergeMessages(current.messages, older.messages),
      hasMore: older.hasMore,
      privacyNote: current.privacyNote,
    ));
  }

  /// Sends a message; it appears in the thread once the backend accepted it.
  Future<void> send(String body) async {
    final message = await ref.read(chatRepositoryProvider).send(id, body);
    final current = state.value;
    if (!ref.mounted || current == null) return;
    put(ChatThread(
      conversation: current.conversation,
      messages: mergeMessages(current.messages, [message]),
      hasMore: current.hasMore,
      privacyNote: current.privacyNote,
    ));
    ref.invalidate(chatListProvider);
  }
}

final chatThreadProvider = AsyncNotifierProvider.autoDispose
    .family<ChatThreadNotifier, ChatThread, String>(ChatThreadNotifier.new);
