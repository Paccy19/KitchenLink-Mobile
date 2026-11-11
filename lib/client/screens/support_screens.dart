import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';

const _categoryLabels = {
  'order': 'An order',
  'delivery': 'Delivery',
  'payment': 'Payment',
  'refund': 'Refund',
  'vendor': 'A kitchen',
  'driver': 'A delivery worker',
  'account': 'My account',
  'app': 'Problem using the app',
  'other': 'Something else',
};

(Color, Color) _statusTone(String status) => switch (status) {
      'open' => (K.tone(const Color(0xFFFFFBEB)), K.tone(const Color(0xFFB45309))),
      'in_review' => (K.tone(const Color(0xFFF0F9FF)), K.tone(const Color(0xFF0369A1))),
      'resolved' => (K.tone(const Color(0xFFECFDF5)), K.tone(const Color(0xFF047857))),
      _ => (K.stone100, K.stone600),
    };

String _when(dynamic iso) {
  final date = parseIso(iso);
  if (date == null) return '';
  final now = DateTime.now();
  return date.year == now.year && date.month == now.month && date.day == now.day ? DateFormat('HH:mm').format(date) : DateFormat('d MMM').format(date);
}

/// Help & Support (the website's `/support`): conversations with the support
/// team and "New request". With [orderId] the new-request form opens about
/// that order (from an order page's "Get help").
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<Json>? _tickets;
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
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    if (widget.orderId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _newRequest(orderId: widget.orderId));
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
      final tickets = await context.read<CustomerApi>().tickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _newRequest({String? orderId}) async {
    if (!await MarketNav.requireSignIn(context) || !mounted) return;
    final ticket = await Navigator.of(context).push<Json>(MaterialPageRoute(builder: (_) => _NewRequestScreen(orderId: orderId)));
    await _load();
    if (ticket != null && mounted) _openTicket('${ticket['id']}');
  }

  Future<void> _openTicket(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketScreen(ticketId: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSession>();
    if (!session.isSignedIn) {
      return MarketPage(
        title: 'Help & Support',
        body: SignInPrompt(
          icon: Icons.support_agent,
          title: 'Help & Support',
          message: 'Sign in so our support team can see your orders and reply to you.',
          onSignIn: () async {
            if (await MarketNav.requireSignIn(context)) _load();
          },
        ),
      );
    }
    final tickets = _tickets;
    final unread = tickets?.where((t) => t['unread'] == true).length ?? 0;
    return MarketPage(
      title: 'Help & Support',
      subtitle: 'Replies show up here and in your notifications${unread > 0 ? ' · $unread new repl${unread > 1 ? 'ies' : 'y'}' : ''}',
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: GradientButton(label: 'New request', icon: Icons.add_comment_outlined, onTap: () => _newRequest()),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Having a problem? Write to our support team.', style: kText(13, color: K.stone600)),
          const SizedBox(height: 12),
          if (_error != null && tickets == null)
            ErrorCard(title: 'Could not load your requests', message: _error, onRetry: _load)
          else if (tickets == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (tickets.isEmpty)
            const EmptyCard(icon: Icons.headset_mic_outlined, title: 'No conversations yet', message: 'Tap “New request” to tell us what went wrong.')
          else
            for (final ticket in tickets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: K.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: K.stone200)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openTicket('${ticket['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${ticket['subject'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14, weight: w900))),
                          if (ticket['unread'] == true) Container(width: 8, height: 8, decoration: const BoxDecoration(color: K.red500, shape: BoxShape.circle)),
                        ]),
                        if (ticket['last_message'] is Map)
                          Text(
                            '${(ticket['last_message'] as Map)['from'] == 'support' ? 'Support: ' : 'You: '}${(ticket['last_message'] as Map)['body'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: kText(12, color: K.stone500),
                          ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Builder(builder: (_) {
                            final (bg, fg) = _statusTone('${ticket['status']}');
                            return StatusPill('${ticket['status_label'] ?? ticket['status'] ?? ''}', background: bg, foreground: fg);
                          }),
                          const Spacer(),
                          Text(_when(ticket['last_message_at']), style: kText(11, color: K.stone400)),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

class _NewRequestScreen extends StatefulWidget {
  const _NewRequestScreen({this.orderId});

  final String? orderId;

  @override
  State<_NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<_NewRequestScreen> {
  static const _categories = ['order', 'delivery', 'payment', 'refund', 'vendor', 'driver', 'account', 'app', 'other'];
  late String _category = widget.orderId != null ? 'order' : _categories.first;
  late String _orderId = widget.orderId ?? '';
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().length < 3) return setState(() => _error = 'Add a short subject (at least 3 characters).');
    if (_message.text.trim().isEmpty) return setState(() => _error = 'Tell us what happened.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await context.read<CustomerApi>().createTicket({
        'subject': _subject.text.trim(),
        'category': _category,
        'message': _message.text.trim(),
        if (_orderId.isNotEmpty) 'order_id': _orderId,
      });
      if (mounted) Navigator.pop(context, ticket);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<Orders>().orders.take(30).toList();
    return MarketPage(
      title: 'New support request',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const FieldLabel('What is it about?'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: marketInput(''),
          items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(_categoryLabels[c]!))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        if (orders.isNotEmpty) ...[
          const SizedBox(height: 12),
          const FieldLabel('Order (optional)'),
          DropdownButtonFormField<String>(
            initialValue: orders.any((o) => o.id == _orderId) ? _orderId : '',
            isExpanded: true,
            decoration: marketInput(''),
            items: [
              const DropdownMenuItem(value: '', child: Text('Not about a specific order')),
              for (final o in orders) DropdownMenuItem(value: o.id, child: Text('${o.orderNumber} · ${o.vendorName}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _orderId = v ?? ''),
          ),
        ],
        const SizedBox(height: 12),
        const FieldLabel('Subject'),
        TextField(controller: _subject, maxLength: 120, decoration: marketInput('e.g. My order arrived cold')),
        const SizedBox(height: 4),
        const FieldLabel('Tell us what happened'),
        TextField(controller: _message, maxLength: 2000, minLines: 5, maxLines: 10, decoration: marketInput('Give as many details as you can.')),
        if (_error != null) ...[const SizedBox(height: 8), Notice(_error!)],
        const SizedBox(height: 14),
        GradientButton(label: _busy ? 'Sending…' : 'Send to support', icon: Icons.send, onTap: _busy ? null : _submit),
      ]),
    );
  }
}

/// One conversation with the support team, and the reply box.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  Json? _ticket;
  String? _error;
  bool _busy = false;
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _show(Json ticket) {
    final count = (ticket['messages'] is List) ? (ticket['messages'] as List).length : 0;
    setState(() => _ticket = ticket);
    if (count != _shown) {
      _shown = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  Future<void> _load() async {
    try {
      final ticket = await context.read<CustomerApi>().ticket(widget.ticketId);
      if (mounted) _show(ticket);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await context.read<CustomerApi>().replyTicket(widget.ticketId, text);
      _reply.clear();
      if (mounted) _show(ticket);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final messages = (ticket?['messages'] is List ? ticket!['messages'] as List : const []).whereType<Map>().toList();
    return MarketPage(
      title: '${ticket?['subject'] ?? 'Support request'}',
      subtitle: ticket == null ? null : '${ticket['reference'] ?? ''} · ${_categoryLabels['${ticket['category']}'] ?? ticket['category'] ?? ''} · ${ticket['status_label'] ?? ''}',
      body: Column(children: [
        Expanded(
          child: ticket == null
              ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(20), child: Notice(_error!)) : const CircularProgressIndicator())
              : ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                  for (final message in messages)
                    Builder(builder: (context) {
                      final mine = message['from'] == 'you';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: mine ? K.buttonGradient : null,
                              color: mine ? null : K.surface,
                              border: mine ? null : Border.all(color: K.stone200),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (!mine) Text('${message['author_name'] ?? 'Support'}', style: kText(11, weight: FontWeight.w700, color: K.brown500)),
                              SelectableText('${message['body'] ?? ''}', style: kText(13.5, color: mine ? Colors.white : K.gray900, height: 1.4)),
                              Text(_when(message['at']), style: kText(10, color: mine ? K.brown300 : K.stone400)),
                            ]),
                          ),
                        ),
                      );
                    }),
                  if (ticket['status'] == 'resolved')
                    const Notice('Marked resolved. Write again if you still need help.', tone: NoticeTone.success, icon: Icons.check_circle_outline),
                ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(color: K.surface, border: Border(top: BorderSide(color: K.stone200))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_error != null && ticket != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Notice(_error!)),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    decoration: marketInput('Write a message…').copyWith(counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  style: IconButton.styleFrom(backgroundColor: K.fillBrown700),
                  onPressed: _busy || _reply.text.trim().isEmpty || ticket == null ? null : _send,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
