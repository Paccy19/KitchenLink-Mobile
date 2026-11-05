import '../../../core/network/json.dart';

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.body,
    required this.fromSupport,
    this.authorName = '',
    this.at,
  });

  factory SupportMessage.fromJson(Json json) => SupportMessage(
        id: str(json['id']),
        body: str(json['body']),
        fromSupport: str(json['from']) == 'support',
        authorName: str(json['author_name']),
        at: dateOrNull(json['at']),
      );

  final String id;
  final String body;
  final bool fromSupport;
  final String authorName;
  final DateTime? at;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.status,
    required this.statusLabel,
    this.category = 'other',
    this.orderId,
    this.unread = false,
    this.lastMessagePreview = '',
    this.messageCount = 0,
    this.lastMessageAt,
    this.messages = const [],
  });

  factory SupportTicket.fromJson(Json json) {
    final last = asJson(json['last_message']);
    return SupportTicket(
      id: str(json['id']),
      reference: str(json['reference']),
      subject: str(json['subject']),
      status: str(json['status']),
      statusLabel: str(json['status_label'], str(json['status'])),
      category: str(json['category'], 'other'),
      orderId: strOrNull(json['order_id']),
      unread: boolOf(json['unread']),
      lastMessagePreview: str(last['body']),
      messageCount: intOf(json['message_count']),
      lastMessageAt: dateOrNull(json['last_message_at']),
      messages: [for (final message in asJsonList(json['messages'])) SupportMessage.fromJson(message)],
    );
  }

  final String id;
  final String reference;
  final String subject;

  /// `open`, `in_review`, `resolved` or `rejected`.
  final String status;
  final String statusLabel;
  final String category;
  final String? orderId;
  final bool unread;
  final String lastMessagePreview;
  final int messageCount;
  final DateTime? lastMessageAt;
  final List<SupportMessage> messages;

  bool get isClosed => status == 'resolved' || status == 'rejected';
}

class SupportList {
  const SupportList({this.tickets = const [], this.unreadCount = 0, this.categories = const []});

  factory SupportList.fromJson(Object? payload) {
    final map = asJson(payload);
    return SupportList(
      tickets: [for (final ticket in unwrapList(payload, ['tickets'])) SupportTicket.fromJson(ticket)],
      unreadCount: intOf(map['unread_count']),
      categories: stringList(map['categories']),
    );
  }

  final List<SupportTicket> tickets;
  final int unreadCount;

  /// Ticket categories the backend accepts (`COMPLAINT_CATEGORIES`).
  final List<String> categories;
}
