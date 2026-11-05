import '../../../core/network/json.dart';

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.customerName,
    this.customerId,
    this.avatarUrl,
    this.lastMessageAt,
    this.preview = '',
    this.lastMessageMine = false,
    this.unreadCount = 0,
  });

  factory ChatConversation.fromJson(Json json) {
    final counterpart = asJson(json['with']);
    return ChatConversation(
      id: str(json['id']),
      customerId: strOrNull(counterpart['id']),
      customerName: str(counterpart['name'], 'Customer'),
      avatarUrl: strOrNull(counterpart['avatar_url']),
      lastMessageAt: dateOrNull(json['last_message_at']),
      preview: str(json['last_message_preview']),
      lastMessageMine: boolOf(json['last_message_mine']),
      unreadCount: intOf(json['unread_count']),
    );
  }

  final String id;
  final String? customerId;
  final String customerName;
  final String? avatarUrl;
  final DateTime? lastMessageAt;
  final String preview;
  final bool lastMessageMine;
  final int unreadCount;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    this.authorRole = '',
    this.createdAt,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
        id: str(json['id']),
        body: str(json['body']),
        mine: boolOf(json['mine']),
        authorRole: str(json['author_role']),
        createdAt: dateOrNull(json['created_at']),
      );

  final String id;
  final String body;

  /// Written by this kitchen (the API sets `mine` for the signed-in side).
  final bool mine;
  final String authorRole;
  final DateTime? createdAt;
}

class ChatThread {
  const ChatThread({
    required this.conversation,
    required this.messages,
    this.hasMore = false,
    this.privacyNote = '',
  });

  factory ChatThread.fromJson(Object? payload) {
    final map = asJson(payload);
    return ChatThread(
      conversation: ChatConversation.fromJson(asJson(map['conversation'])),
      // The API returns the newest messages first or last depending on the
      // query; always show oldest → newest.
      messages: _chronological([for (final item in asJsonList(map['messages'])) ChatMessage.fromJson(item)]),
      hasMore: boolOf(map['has_more']),
      privacyNote: str(map['privacy_note']),
    );
  }

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasMore;
  final String privacyNote;
}

List<ChatMessage> _chronological(List<ChatMessage> messages) {
  final sorted = [...messages];
  sorted.sort((a, b) {
    final left = a.createdAt, right = b.createdAt;
    if (left == null || right == null) return 0;
    return left.compareTo(right);
  });
  return sorted;
}

/// Messages from two loads, oldest first, each message once.
List<ChatMessage> mergeMessages(List<ChatMessage> existing, List<ChatMessage> incoming) {
  final byId = <String, ChatMessage>{for (final message in existing) message.id: message};
  for (final message in incoming) {
    byId[message.id] = message;
  }
  return _chronological(byId.values.toList());
}
