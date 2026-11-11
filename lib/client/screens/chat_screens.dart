import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';

String _when(dynamic iso) {
  final date = parseIso(iso);
  if (date == null) return '';
  final now = DateTime.now();
  final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
  return sameDay ? DateFormat('HH:mm').format(date) : DateFormat('d MMM').format(date);
}

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEE d MMM').format(date);
}

/// Messages (the website's `/messages`): the customer's chats with kitchens.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Json>? _chats;
  String? _error;
  Timer? _timer;
  late final CustomerSession _session;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _session = context.read<CustomerSession>()..addListener(_onSession);
    _wasSignedIn = _session.isSignedIn;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session.removeListener(_onSession);
    super.dispose();
  }

  /// The saved sign-in finishes loading after the page opens, or the customer signs in here.
  void _onSession() {
    if (_session.isSignedIn && !_wasSignedIn) _load();
    _wasSignedIn = _session.isSignedIn;
  }

  Future<void> _load() async {
    if (!_session.isSignedIn) return;
    try {
      final chats = await context.read<CustomerApi>().chats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSession>();
    final media = context.read<CustomerApi>().media;
    if (!session.isSignedIn) {
      return MarketPage(
        title: 'Messages',
        body: SignInPrompt(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          message: 'Sign in to chat with kitchens.',
          onSignIn: () async {
            if (await MarketNav.requireSignIn(context)) _load();
          },
        ),
      );
    }
    final chats = _chats;
    return MarketPage(
      title: 'Messages',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null && chats == null)
            ErrorCard(title: 'Could not load your chats', message: _error, onRetry: _load)
          else if (chats == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (chats.isEmpty)
            const EmptyCard(icon: Icons.chat_bubble_outline, title: 'No chats yet', message: 'Open a kitchen you ordered from and tap “Message kitchen” to ask about a dish, an order or delivery.')
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final chat in chats) _ChatRow(chat: chat, media: media, onOpen: () async {
                  await MarketNav.chat(context, '${chat['id']}');
                  _load();
                }),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.media, required this.onOpen});

  final Json chat;
  final String? Function(String) media;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final other = chat['with'] is Map ? (chat['with'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final unread = (chat['unread_count'] as num?)?.toInt() ?? 0;
    final avatar = media('${other['avatar_url'] ?? ''}');
    return ListTile(
      onTap: onOpen,
      leading: CircleAvatar(backgroundColor: K.brown50, backgroundImage: avatar == null ? null : NetworkImage(avatar), child: avatar == null ? Icon(Icons.storefront_outlined, color: K.brown700) : null),
      title: Row(children: [
        Expanded(child: Text('${other['name'] ?? 'Kitchen'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14, weight: w900))),
        Text(_when(chat['last_message_at']), style: kText(11, color: K.stone400)),
      ]),
      subtitle: Row(children: [
        Expanded(
          child: Text(
            '${chat['last_message_mine'] == true ? 'You: ' : ''}${chat['last_message_preview'] ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kText(12, weight: unread > 0 ? FontWeight.w700 : FontWeight.w400, color: unread > 0 ? K.gray900 : K.stone500),
          ),
        ),
        if (unread > 0) Badge(label: Text('$unread'), backgroundColor: K.fillBrown700),
      ]),
    );
  }
}

/// One conversation with a kitchen: messages by day, older ones on demand,
/// new ones every 4 seconds, and the composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxLength = 1000;
  late final CustomerApi _api;
  Json? _conversation;
  final List<Json> _messages = [];
  String _note = '';
  String? _error;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _sending = false;
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _api = context.read<CustomerApi>();
    _open();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _latest => _messages.isEmpty ? null : '${_messages.last['created_at']}';

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _open() async {
    try {
      final data = await _api.chat(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = data['conversation'] is Map ? (data['conversation'] as Map).cast<String, dynamic>() : {};
        _messages
          ..clear()
          ..addAll((data['messages'] is List ? data['messages'] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()));
        _hasMore = data['has_more'] == true;
        _note = '${data['privacy_note'] ?? ''}';
      });
      _toEnd();
      _api.markChatRead(widget.conversationId).ignore();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Only messages newer than the last one on screen.
  Future<void> _poll() async {
    try {
      final data = await _api.chat(widget.conversationId, after: _latest);
      final fresh = (data['messages'] is List ? data['messages'] as List : const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .where((m) => !_messages.any((old) => old['id'] == m['id']))
          .toList();
      if (fresh.isEmpty || !mounted) return;
      final atEnd = !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.offset < 80;
      setState(() => _messages.addAll(fresh));
      if (atEnd) _toEnd();
      _api.markChatRead(widget.conversationId).ignore();
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final data = await _api.chat(widget.conversationId, before: '${_messages.first['created_at']}');
      final older = (data['messages'] is List ? data['messages'] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (mounted) {
        setState(() {
          _messages.insertAll(0, older);
          _hasMore = data['has_more'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final data = await _api.sendChat(widget.conversationId, text);
      final message = data['message'];
      if (mounted && message is Map) {
        setState(() => _messages.add(message.cast<String, dynamic>()));
        _draft.clear();
        _toEnd();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _conversation?['with'] is Map ? (_conversation!['with'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final otherId = '${other['id'] ?? ''}';
    return MarketPage(
      title: '${other['name'] ?? (_conversation == null ? 'Chat' : 'Kitchen')}',
      subtitle: other['is_open'] == false ? 'Closed now' : (other['vendor_type'] != null ? vendorTypeOf(other['vendor_type']).label : null),
      actions: [
        if (otherId.isNotEmpty) IconButton(tooltip: 'Open kitchen', onPressed: () => MarketNav.kitchen(context, otherId), icon: const Icon(Icons.storefront_outlined)),
      ],
      body: Column(children: [
        Expanded(
          child: _conversation == null
              ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(20), child: Notice(_error!)) : const CircularProgressIndicator())
              : ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                  if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Notice(_note, tone: NoticeTone.info, icon: Icons.verified_user_outlined)),
                  if (_hasMore)
                    Center(child: TextButton(onPressed: _loadingOlder ? null : _loadOlder, child: Text(_loadingOlder ? 'Loading…' : 'Load older messages'))),
                  if (_messages.isEmpty)
                    Padding(padding: const EdgeInsets.all(24), child: Text('Ask the kitchen anything — about a dish, an order or delivery.', textAlign: TextAlign.center, style: kText(13, color: K.stone500))),
                  for (var i = 0; i < _messages.length; i++) ..._bubble(i),
                ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.stone200))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_error != null && _conversation != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Notice(_error!)),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: _maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: marketInput('Write a message…').copyWith(counterText: _draft.text.length > _maxLength - 100 ? '${_draft.text.length}/$_maxLength' : ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send message',
                  style: IconButton.styleFrom(backgroundColor: K.fillBrown700),
                  onPressed: _draft.text.trim().isEmpty || _sending || _conversation == null ? null : _send,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _bubble(int i) {
    final message = _messages[i];
    final at = parseIso(message['created_at']);
    final prev = i == 0 ? null : parseIso(_messages[i - 1]['created_at']);
    final newDay = at != null && (prev == null || prev.year != at.year || prev.month != at.month || prev.day != at.day);
    final mine = message['mine'] == true;
    return [
      if (newDay) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: Text(_dayLabel(at), style: kText(11, weight: FontWeight.w700, color: K.stone400)))),
      Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: mine ? K.buttonGradient : null,
              color: mine ? null : K.surface,
              border: mine ? null : Border.all(color: K.stone200),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              SelectableText('${message['body'] ?? ''}', style: kText(13.5, weight: FontWeight.w500, color: mine ? Colors.white : K.gray900, height: 1.4)),
              if (at != null) Text(DateFormat('HH:mm').format(at), style: kText(10, color: mine ? K.brown300 : K.stone400)),
            ]),
          ),
        ),
      ),
    ];
  }
}
