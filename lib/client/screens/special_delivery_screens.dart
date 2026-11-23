import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart' show Json;
import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';

/// What each step means for the customer (the website's SpecialDeliveryPage).
const _statusHelp = {
  'pending_vendor_review': 'The kitchen has your request and will accept to discuss it, ask for details, or decline.',
  'awaiting_customer_information': 'The kitchen needs more details before it can decide. Answer below.',
  'negotiation_accepted': 'The kitchen is open to arranging this delivery. Discuss it in the chat; they will send a formal quotation.',
  'negotiating': 'Discuss the delivery in the chat. The kitchen will send a formal quotation with the price.',
  'quotation_submitted': 'The kitchen sent a quotation. Review it and accept, ask for another price, or reject it.',
  'quotation_revision_requested': 'You asked for another price. The kitchen can send a revised quotation.',
  'quotation_rejected': 'You rejected the quotation. Keep talking in the chat, or cancel the request.',
  'quotation_expired': 'The quotation expired. Ask the kitchen for a new one in the chat.',
  'quotation_accepted': 'Price agreed and locked. Book your event to pay with this delivery fee.',
  'delivery_confirmed': 'Your event order is booked and paid with the agreed delivery fee.',
  'completed': 'Delivered. Thank you!',
  'vendor_declined': 'The kitchen declined this delivery. You can pick the food up, or ask another kitchen.',
  'customer_cancelled': 'This request is closed.',
  'disputed': 'Our support team is reviewing a problem with this delivery.',
};

Json _map(Object? value) => value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _list(Object? value) => value is List ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

String _when(Object? iso) {
  final date = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  return date == null ? '' : DateFormat('EEE d MMM, HH:mm').format(date);
}

/// The status chip (green when agreed or done, red when closed, brown otherwise).
Widget _statusPill(String status, String label) {
  final good = const {'quotation_accepted', 'delivery_confirmed', 'completed'}.contains(status);
  final bad = const {'vendor_declined', 'customer_cancelled', 'disputed', 'quotation_rejected', 'quotation_expired'}.contains(status);
  return StatusPill(
    label,
    background: K.tone(good ? const Color(0xFFD1FAE5) : bad ? const Color(0xFFFEE2E2) : const Color(0xFFF5EBE1)),
    foreground: K.tone(good ? const Color(0xFF065F46) : bad ? const Color(0xFF991B1B) : const Color(0xFF3D1B0C)),
  );
}

/// The customer's special delivery requests (the website's /special-deliveries).
class SpecialDeliveriesScreen extends StatefulWidget {
  const SpecialDeliveriesScreen({super.key});

  @override
  State<SpecialDeliveriesScreen> createState() => _SpecialDeliveriesScreenState();
}

class _SpecialDeliveriesScreenState extends State<SpecialDeliveriesScreen> {
  List<Json>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<CustomerApi>().specialDeliveries();
      if (mounted) {
        setState(() {
        _items = items;
        _error = null;
      });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<CustomerSession>().isSignedIn;
    final items = _items;
    return MarketPage(
      title: 'Special deliveries',
      subtitle: 'Big-event deliveries you arranged with kitchens',
      body: !signedIn
          ? SignInPrompt(
              icon: Icons.local_shipping_outlined,
              title: 'Sign in to see your special deliveries',
              message: 'Requests you send kitchens for big-event deliveries show up here.',
              onSignIn: () => MarketNav.requireSignIn(context).then((_) => _load()),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_error != null && items == null)
                  ErrorCard(title: 'Your requests could not load', message: _error, onRetry: _load)
                else if (items == null)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (items.isEmpty)
                  EmptyCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'No special deliveries yet',
                    message: "When a big-event venue is outside a kitchen's delivery area, you can ask it for a special delivery from the event order page.",
                    actionLabel: 'Explore Big Events',
                    onAction: () => MarketNav.bigEvent(context),
                  )
                else
                  for (final r in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: K.surface,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => MarketNav.specialDelivery(context, '${r['id']}').then((_) => _load()),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${_map(r['vendor'])['name'] ?? 'Kitchen'}', style: kText(15, weight: w900))),
                                if (_num(r['unread_count']) > 0)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: K.strong, borderRadius: BorderRadius.circular(99)),
                                    child: Text('${r['unread_count']}', style: kText(11, weight: w900, color: K.onStrong)),
                                  ),
                                _statusPill('${r['status']}', '${r['status_label'] ?? r['status']}'),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                '${r['reference'] ?? ''} · ${_map(r['event'])['guests'] ?? '?'} guests · ${_when(r['requested_delivery_at'])}',
                                style: kText(12, color: K.stone500),
                              ),
                              if (r['agreed_fee_rwf'] != null)
                                Text('Agreed delivery fee: ${rwf(_num(r['agreed_fee_rwf']))}', style: kText(12, weight: FontWeight.w700, color: K.tone(const Color(0xFF065F46)))),
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

/// One special delivery request: what the kitchen needs, its quotations
/// (accept / ask for another price / reject), the negotiation chat, and, once
/// a price is agreed, booking the event with that delivery fee. Every button
/// comes from the server's `allowed_actions`.
class SpecialDeliveryScreen extends StatefulWidget {
  const SpecialDeliveryScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<SpecialDeliveryScreen> createState() => _SpecialDeliveryScreenState();
}

class _SpecialDeliveryScreenState extends State<SpecialDeliveryScreen> {
  late final CustomerApi _api = context.read<CustomerApi>();
  Json? _request;
  String? _error;
  String _busy = '';
  String? _actionError;
  final _answer = TextEditingController();
  final _note = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _answer.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.specialDelivery(widget.requestId);
      if (mounted) {
        setState(() {
        _request = data;
        _error = null;
      });
      }
    } catch (e) {
      if (mounted && _request == null) setState(() => _error = e.toString());
    }
  }

  Future<void> _act(String key, Future<Json> Function() action, {String? done}) async {
    setState(() {
      _busy = key;
      _actionError = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _request = updated.isEmpty ? _request : updated);
      _note.clear();
      if (done != null) showMarketSnack(context, done);
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
      _load();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<String?> _ask(String title, String hint, {bool required = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, maxLines: 3, maxLength: 500, decoration: marketInput(hint)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Back')),
          FilledButton(
            onPressed: () {
              if (required && controller.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Yes')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) {
      return MarketPage(
        title: 'Special delivery',
        body: _error != null
            ? Padding(padding: const EdgeInsets.all(16), child: ErrorCard(title: 'This request could not load', message: _error, onRetry: _load))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final id = '${request['id']}';
    final status = '${request['status']}';
    final actions = (request['allowed_actions'] is List ? request['allowed_actions'] as List : const []).map((a) => '$a').toSet();
    final open = request['active_quotation'] is Map ? _map(request['active_quotation']) : null;
    final vendor = _map(request['vendor']);
    final order = request['order'] is Map ? _map(request['order']) : null;
    final earlier = _list(request['quotations']).where((q) => q['id'] != open?['id']).toList();

    return MarketPage(
      title: '${vendor['name'] ?? 'Special delivery'}',
      subtitle: 'Special delivery ${request['reference'] ?? ''}',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: Alignment.centerLeft, child: _statusPill(status, '${request['status_label'] ?? status}')),
              const SizedBox(height: 10),
              Text(_statusHelp[status] ?? '', style: kText(13, color: K.stone700, height: 1.45)),
              if ('${request['decline_reason'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Notice("Kitchen's reason: ${request['decline_reason']}"),
              ],
              if (actions.contains('provide_information')) ...[
                const SizedBox(height: 12),
                Text('The kitchen asks: “${request['info_request'] ?? ''}”', style: kText(13, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(controller: _answer, maxLines: 3, maxLength: 1000, decoration: marketInput('Your answer')),
                OutlineAction(
                  label: _busy == 'info' ? 'Sending…' : 'Send answer',
                  icon: Icons.send_outlined,
                  color: K.brown700,
                  onTap: _busy.isNotEmpty
                      ? null
                      : () {
                          if (_answer.text.trim().isEmpty) return;
                          _act('info', () => _api.provideSpecialDeliveryInformation(id, _answer.text.trim()), done: 'Answer sent.')
                              .then((_) => _answer.clear());
                        },
                ),
              ],
              if (request['agreed_fee_rwf'] != null) ...[
                const SizedBox(height: 12),
                Notice(
                  'Agreed delivery fee: ${rwf(_num(request['agreed_fee_rwf']))}. Locked on ${_when(request['agreed_at'])}. Added to your order total separately from the food.',
                  tone: NoticeTone.success,
                  icon: Icons.handshake_outlined,
                ),
              ],
              if (request['can_checkout'] == true) ...[
                const SizedBox(height: 12),
                GradientButton(
                  label: 'Book the event with this delivery fee',
                  onTap: () => MarketNav.eventOrder(
                    context,
                    vendorId: '${vendor['id']}',
                    packageId: '${_map(request['event'])['package_id'] ?? ''}'.isEmpty ? null : '${_map(request['event'])['package_id']}',
                    guests: (_map(request['event'])['guests'] as num?)?.toInt(),
                    agreementId: id,
                  ),
                ),
              ],
              if (order != null) ...[
                const SizedBox(height: 10),
                OutlineAction(
                  label: 'Order ${order['order_number']} · ${order['status']}',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => MarketNav.order(context, '${order['id']}'),
                ),
              ],
              for (final refund in _list(request['refunds']))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Refund ${rwf(_num(refund['amount_rwf']))} (${'${refund['kind_label'] ?? ''}'.toLowerCase()}): ${refund['status_label'] ?? refund['status']}',
                    style: kText(12, color: K.stone700),
                  ),
                ),
              if (_actionError != null) ...[const SizedBox(height: 10), Notice(_actionError!)],
            ]),
          ),
          if (open != null) ...[
            const SizedBox(height: 14),
            _QuotationCard(
              quotation: open,
              highlight: true,
              actions: actions.contains('accept_quotation')
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 10),
                      TextField(
                        controller: _note,
                        maxLines: 2,
                        maxLength: 500,
                        decoration: marketInput('Note for the kitchen (optional, e.g. the price you hoped for)'),
                      ),
                      GradientButton(
                        label: _busy == 'accept' ? 'Accepting…' : 'Accept ${rwf(_num(open['fee_rwf']))}',
                        onTap: _busy.isNotEmpty
                            ? null
                            : () async {
                                if (await _confirm('Accept ${rwf(_num(open['fee_rwf']))} for delivery? This price will be locked for your order.')) {
                                  _act('accept', () => _api.acceptQuotation(id, '${open['id']}'), done: 'Price agreed.');
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlineAction(
                          label: 'Ask for another price',
                          onTap: _busy.isNotEmpty ? null : () => _act('revise', () => _api.requestQuotationRevision(id, '${open['id']}', _note.text.trim())),
                        ),
                        OutlineAction(
                          label: 'Reject',
                          color: K.tone(const Color(0xFFB91C1C)),
                          onTap: _busy.isNotEmpty ? null : () => _act('reject', () => _api.rejectQuotation(id, '${open['id']}', _note.text.trim())),
                        ),
                      ]),
                    ])
                  : null,
            ),
          ],
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('YOUR REQUEST', style: kText(11, weight: FontWeight.w800, color: K.stone400, spacing: 0.6)),
              const SizedBox(height: 8),
              _Facts(request: request),
            ]),
          ),
          if (earlier.isNotEmpty) ...[
            const SizedBox(height: 14),
            ExpansionTile(
              title: Text('Earlier quotations (${earlier.length})', style: kText(13, weight: FontWeight.w700)),
              children: [for (final q in earlier) Padding(padding: const EdgeInsets.only(bottom: 8), child: _QuotationCard(quotation: q))],
            ),
          ],
          const SizedBox(height: 14),
          _NegotiationChat(requestId: id, open: request['chat_open'] == true, onActivity: _load),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (actions.contains('cancel'))
              OutlineAction(
                label: 'Cancel request',
                color: K.tone(const Color(0xFFB91C1C)),
                onTap: _busy.isNotEmpty
                    ? null
                    : () async {
                        final reason = await _ask('Cancel this special delivery request?', 'You can tell the kitchen why (optional)');
                        if (reason != null) _act('cancel', () => _api.cancelSpecialDelivery(id, reason), done: 'Request cancelled.');
                      },
              ),
            if (actions.contains('dispute'))
              OutlineAction(
                label: 'Report a problem',
                onTap: _busy.isNotEmpty
                    ? null
                    : () async {
                        final reason = await _ask('What went wrong with this delivery?', 'Describe the problem', required: true);
                        if (reason != null && reason.isNotEmpty) _act('dispute', () => _api.disputeSpecialDelivery(id, reason), done: 'Support will review it.');
                      },
              ),
          ]),
        ]),
      ),
    );
  }
}

/// A formal quotation (the website's QuotationCard).
class _QuotationCard extends StatelessWidget {
  const _QuotationCard({required this.quotation, this.highlight = false, this.actions});

  final Json quotation;
  final bool highlight;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final arrangements = _list(quotation['arrangements']).map((a) => '${a['label'] ?? a['code']}').join(', ');
    return Panel(
      color: highlight ? K.brown50 : null,
      border: highlight ? K.brown200 : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              'Quotation ${quotation['reference'] ?? ''} · v${quotation['version'] ?? 1}',
              style: kText(11, weight: FontWeight.w800, color: K.stone500),
            ),
          ),
          if (quotation['expired'] == true)
            Text('Expired', style: kText(11, weight: FontWeight.w800, color: K.tone(const Color(0xFFB91C1C))))
          else
            Text('${quotation['status'] ?? ''}', style: kText(11, weight: FontWeight.w800, color: K.stone500)),
        ]),
        const SizedBox(height: 6),
        Text('${rwf(_num(quotation['fee_rwf']))} delivery fee', style: kText(22, weight: w900)),
        if (_when(quotation['proposed_delivery_at']).isNotEmpty)
          Text('Delivery: ${_when(quotation['proposed_delivery_at'])}', style: kText(12, color: K.stone600)),
        if (arrangements.isNotEmpty) Text('How: $arrangements', style: kText(12, color: K.stone600)),
        if ('${quotation['arrangement_description'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${quotation['arrangement_description']}', style: kText(12.5, color: K.stone700, height: 1.4))),
        if ('${quotation['conditions'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Conditions: ${quotation['conditions']}', style: kText(12, color: K.stone600))),
        if (_when(quotation['valid_until']).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Valid until ${_when(quotation['valid_until'])}', style: kText(11, color: K.stone400))),
        ?actions,
      ]),
    );
  }
}

/// The request's facts: event, venue, guests and why a special delivery was needed.
class _Facts extends StatelessWidget {
  const _Facts({required this.request});

  final Json request;

  @override
  Widget build(BuildContext context) {
    final event = _map(request['event']);
    final location = _map(request['delivery_location']);
    final district = request['destination_district'] is Map ? '${_map(request['destination_district'])['name']}' : '';
    Widget row(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: Text(label, style: kText(12, color: K.stone500))),
              Expanded(child: Text(value, style: kText(12.5, weight: FontWeight.w600))),
            ]),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Delivery', _when(request['requested_delivery_at'])),
      row('Guests', '${event['guests'] ?? ''}'),
      row('Venue', '${location['address'] ?? ''}${district.isNotEmpty ? ' ($district district)' : ''}'),
      if (request['route'] is Map && _map(request['route'])['distance_m'] != null)
        row('Distance', '${(_num(_map(request['route'])['distance_m']) / 1000).toStringAsFixed(1)} km by road'),
      row('Instructions', '${request['instructions'] ?? ''}'),
      for (final reason in (request['trigger_messages'] is List ? request['trigger_messages'] as List : const []))
        Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $reason', style: kText(12, color: K.stone500))),
    ]);
  }
}

/// The negotiation chat (text), on the same chat messages as the website.
class _NegotiationChat extends StatefulWidget {
  const _NegotiationChat({required this.requestId, required this.open, required this.onActivity});

  final String requestId;
  final bool open;
  final VoidCallback onActivity;

  @override
  State<_NegotiationChat> createState() => _NegotiationChatState();
}

class _NegotiationChatState extends State<_NegotiationChat> {
  late final CustomerApi _api = context.read<CustomerApi>();
  final _text = TextEditingController();
  List<Json> _messages = const [];
  String _privacy = '';
  bool _sending = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.specialDeliveryMessages(widget.requestId);
      if (!mounted) return;
      final messages = _list(data['messages']);
      final grew = messages.length != _messages.length;
      setState(() {
        _messages = messages;
        _privacy = '${data['privacy_note'] ?? ''}';
      });
      if (grew && messages.isNotEmpty) _api.markSpecialDeliveryRead(widget.requestId).ignore();
    } catch (_) {
      // Keep the last messages; the next poll tries again.
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.sendSpecialDeliveryMessage(widget.requestId, body);
      _text.clear();
      await _load();
      widget.onActivity();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Chat with the kitchen', style: kText(15, weight: w900)),
        if (_privacy.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_privacy, style: kText(11, color: K.stone400))),
        const SizedBox(height: 10),
        if (_messages.isEmpty)
          Text(
            widget.open ? 'No messages yet. Say hello, or share details about the venue.' : 'The chat opens once the kitchen accepts to discuss your request.',
            style: kText(12, color: K.stone500),
          ),
        for (final m in _messages) _bubble(m),
        if (widget.open) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: 3,
                minLines: 1,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: marketInput('Write a message').copyWith(counterText: ''),
              ),
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
            ),
          ]),
          if (_error != null) Notice(_error!),
        ],
      ]),
    );
  }

  Widget _bubble(Json m) {
    final mine = m['mine'] == true;
    final kind = '${m['kind'] ?? 'text'}';
    final system = m['author_role'] == 'system';
    final location = _map(m['location']);
    final text = switch (kind) {
      'location' => '📍 Shared a location${'${location['label'] ?? ''}'.isNotEmpty ? ': ${location['label']}' : ''}',
      'image' => '🖼 Sent a photo${'${m['body'] ?? ''}'.isNotEmpty ? ': ${m['body']}' : ''}',
      _ => '${m['body'] ?? ''}',
    };
    return Align(
      alignment: system ? Alignment.center : mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: system ? K.stone100 : mine ? K.strong : K.brown50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: kText(13, color: mine && !system ? K.onStrong : K.gray900, height: 1.35)),
          Text(_when(m['created_at']), style: kText(10, color: mine && !system ? K.onStrong.withValues(alpha: 0.7) : K.stone400)),
        ]),
      ),
    );
  }
}
