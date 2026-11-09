import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/chat.dart';

class ChatRepository {
  const ChatRepository(this._api);
  final ApiClient _api;

  Future<List<ChatConversation>> conversations() async => [
        for (final item in unwrapList(await _api.get('/vendor/chats'), ['conversations']))
          ChatConversation.fromJson(item),
      ];

  Future<int> unreadCount() async =>
      intOf(asJson(await _api.get('/vendor/chats/unread-count'))['unread_count']);

  /// A conversation with its latest messages. Opening it marks it read.
  /// [after] returns only newer messages (for polling), [before] older ones.
  Future<ChatThread> thread(String id, {DateTime? after, DateTime? before, int limit = 50}) async =>
      ChatThread.fromJson(
        await _api.get('/vendor/chats/$id', query: {
          if (after != null) 'after': after.toUtc().toIso8601String(),
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'limit': limit,
        }),
      );

  Future<ChatMessage> send(String id, String body) async {
    final json = asJson(await _api.post('/vendor/chats/$id/messages', data: {'body': body.trim()}));
    return ChatMessage.fromJson(asJson(json['message']));
  }

  Future<void> markRead(String id) => _api.post('/vendor/chats/$id/read');
}
