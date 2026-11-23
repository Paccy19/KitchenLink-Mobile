import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/json.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/special_delivery_providers.dart';

String _when(Object? iso) {
  final date = DateTime.tryParse(str(iso))?.toLocal();
  return date == null ? '' : DateFormat('EEE d MMM, HH:mm').format(date);
}

Tone _tone(String status) => switch (status) {
      'quotation_accepted' || 'delivery_confirmed' || 'completed' => Tone.success,
      'vendor_declined' || 'customer_cancelled' || 'disputed' || 'quotation_rejected' || 'quotation_expired' => Tone.danger,
      'pending_vendor_review' || 'quotation_revision_requested' => Tone.warning,
      _ => Tone.brand,
    };

/// More → Special deliveries (the website's Vendor → Special Deliveries):
/// customers' requests for big-event deliveries outside the kitchen's
/// coverage or above KitchenLink's automatic price.
class SpecialDeliveriesScreen extends ConsumerStatefulWidget {
  const SpecialDeliveriesScreen({super.key});

  @override
  ConsumerState<SpecialDeliveriesScreen> createState() => _SpecialDeliveriesScreenState();
}

class _SpecialDeliveriesScreenState extends ConsumerState<SpecialDeliveriesScreen> {
  String _scope = 'open';

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(specialDeliveriesProvider(_scope));
    return Scaffold(
      appBar: AppBar(title: const Text('Special deliveries')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'closed', label: Text('Closed')),
            ],
            selected: {_scope},
            onSelectionChanged: (value) => setState(() => _scope = value.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(specialDeliveriesProvider(_scope).future),
            child: requests.when(
              loading: () => const SkeletonList(count: 4),
              error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(specialDeliveriesProvider(_scope))),
              data: (items) => items.isEmpty
                  ? ListView(children: const [
                      EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'No special delivery requests',
                        message: 'When a customer asks you to deliver a big-event order outside your coverage, it shows up here.',
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final r = items[index];
                        final unread = intOf(r['unread_count']);
                        return AppCard(
                          onTap: () async {
                            await context.push('/special-deliveries/${str(r['id'])}');
                            ref.invalidate(specialDeliveriesProvider(_scope));
                          },
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  '${str(asJson(r['customer'])['name'], 'Customer')} · ${str(r['reference'])}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (unread > 0) ...[CountBadge(count: unread), const SizedBox(width: 6)],
                              StatusChip(label: str(r['status_label'], str(r['status'])), tone: _tone(str(r['status'])), dense: true),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              '${intOf(asJson(r['event'])['guests'])} guests · ${_when(r['requested_delivery_at'])}'
                              '${asJson(r['destination_district'])['name'] != null ? ' · ${asJson(r['destination_district'])['name']}' : ''}',
                            ),
                            if (r['agreed_fee_rwf'] != null)
                              Text('Agreed: ${formatRwf(intOf(r['agreed_fee_rwf']))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// One request for the kitchen: the customer's event and venue, the decision
/// (accept to negotiate / ask for information / decline), the formal
/// quotation (never edited: a revised one replaces it), and the chat. Every
/// button comes from the server's `allowed_actions`.
class SpecialDeliveryDetailScreen extends ConsumerStatefulWidget {
  const SpecialDeliveryDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<SpecialDeliveryDetailScreen> createState() => _SpecialDeliveryDetailScreenState();
}

class _SpecialDeliveryDetailScreenState extends ConsumerState<SpecialDeliveryDetailScreen> {
  final _message = TextEditingController();
  bool _busy = false;
  bool _showQuote = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => ref.invalidate(specialDeliveryProvider(widget.requestId)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _message.dispose();
    super.dispose();
  }

  Future<void> _act(Future<Object?> Function() action, String success) async {
    setState(() => _busy = true);
    final done = await runAction(context, action, success: success);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done != null) {
      _message.clear();
      ref.invalidate(specialDeliveryProvider(widget.requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(specialDeliveryProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(title: Text(str(request.asData?.value['reference'], 'Special delivery'))),
      body: request.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(count: 4),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(specialDeliveryProvider(widget.requestId))),
        data: (r) => _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, Json r) {
    final theme = Theme.of(context);
    final repo = ref.read(specialDeliveryRepositoryProvider);
    final id = str(r['id']);
    final actions = {for (final a in (r['allowed_actions'] is List ? r['allowed_actions'] as List : const [])) '$a'};
    final open = r['active_quotation'] is Map ? asJson(r['active_quotation']) : null;
    final reviewing = actions.contains('accept_negotiation') || actions.contains('request_information');
    final customer = asJson(r['customer']);
    final event = asJson(r['event']);
    final location = asJson(r['delivery_location']);
    final order = r['order'] is Map ? asJson(r['order']) : null;
    final earlier = asJsonList(r['quotations']).where((q) => q['id'] != open?['id']).toList();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(specialDeliveryProvider(widget.requestId).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(str(customer['name'], 'Customer'), style: theme.textTheme.titleMedium)),
              StatusChip(label: str(r['status_label'], str(r['status'])), tone: _tone(str(r['status']))),
            ]),
            if (str(customer['phone']).isNotEmpty) Text(str(customer['phone'])),
            const SizedBox(height: 10),
            _fact('Delivery', _when(r['requested_delivery_at'])),
            _fact('Guests', '${intOf(event['guests'])}'),
            _fact('Venue', '${str(location['address'])}${asJson(r['destination_district'])['name'] != null ? ' (${asJson(r['destination_district'])['name']} district)' : ''}'),
            if (asJson(r['route'])['distance_m'] != null)
              _fact('Distance', '${(intOf(asJson(r['route'])['distance_m']) / 1000).toStringAsFixed(1)} km by road'),
            if (r['calculated_fee_rwf'] != null) _fact('KitchenLink price', formatRwf(intOf(r['calculated_fee_rwf']))),
            _fact('Instructions', str(r['instructions'])),
            for (final reason in (r['trigger_messages'] is List ? r['trigger_messages'] as List : const []))
              Text('• $reason', style: theme.textTheme.bodySmall),
            if (r['agreed_fee_rwf'] != null) ...[
              const SizedBox(height: 8),
              NoteBox(message: 'Agreed delivery fee ${formatRwf(intOf(r['agreed_fee_rwf']))} · ${_when(r['agreed_at'])}', tone: Tone.success, icon: Icons.handshake_outlined),
            ],
            if (order != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () => context.push('/orders/${str(order['id'])}'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text('Order ${str(order['order_number'])} · ${str(order['status'])}'),
                ),
              ),
          ]),
        ),
        if (reviewing || actions.contains('decline')) ...[
          SectionHeader(reviewing ? 'Your decision' : 'Decline'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                label: reviewing ? 'Message: a question for the customer, or the reason you decline' : 'Reason for declining',
                controller: _message,
                maxLength: 1000,
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (actions.contains('accept_negotiation'))
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _act(() => repo.acceptNegotiation(id, _message.text.trim()), 'The chat with the customer is open.'),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Accept to negotiate'),
                  ),
                if (actions.contains('request_information'))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_message.text.trim().isEmpty) return showError(context, 'Write your question for the customer.');
                            _act(() => repo.requestInformation(id, _message.text.trim()), 'Question sent to the customer.');
                          },
                    child: const Text('Ask for more information'),
                  ),
                if (actions.contains('decline'))
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (_message.text.trim().isEmpty) return showError(context, 'Write the reason you decline.');
                            if (await confirm(context, title: 'Decline this request?', message: 'The customer will see your reason.', confirmLabel: 'Decline', destructive: true)) {
                              _act(() => repo.decline(id, _message.text.trim()), 'Request declined.');
                            }
                          },
                    child: const Text('Decline'),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('Asking for information and declining need a message.', style: theme.textTheme.bodySmall),
            ]),
          ),
        ],
        if (open != null) ...[
          const SectionHeader('Open quotation'),
          _QuotationCard(
            quotation: open,
            action: actions.contains('withdraw_quotation')
                ? TextButton(
                    onPressed: _busy ? null : () => _act(() => repo.withdrawQuotation(id, str(open['id'])), 'Quotation withdrawn.'),
                    child: const Text('Withdraw quotation'),
                  )
                : null,
          ),
        ],
        if (actions.contains('submit_quotation') || actions.contains('revise_quotation')) ...[
          const SizedBox(height: 12),
          if (_showQuote)
            _QuotationForm(
              request: r,
              revising: open != null,
              onCancel: () => setState(() => _showQuote = false),
              onSubmit: (payload) async {
                setState(() => _busy = true);
                final sent = await runAction(context, () => repo.submitQuotation(id, payload), success: open != null ? 'Revised quotation sent.' : 'Quotation sent to the customer.');
                if (!mounted) return;
                setState(() {
                  _busy = false;
                  if (sent != null) _showQuote = false;
                });
                if (sent != null) ref.invalidate(specialDeliveryProvider(widget.requestId));
              },
            )
          else
            FilledButton(
              onPressed: () => setState(() => _showQuote = true),
              child: Text(open != null ? 'Revise the quotation' : 'Send a formal quotation'),
            ),
        ],
        const SectionHeader('Chat with the customer'),
        _Chat(requestId: id, open: r['chat_open'] == true),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: Text('Earlier quotations (${earlier.length})'),
            children: [for (final q in earlier) Padding(padding: const EdgeInsets.only(bottom: 8), child: _QuotationCard(quotation: q))],
          ),
        ],
        if (actions.contains('dispute'))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final reason = await _askReason(context);
                      if (reason != null && reason.isNotEmpty) _act(() => repo.dispute(id, reason), 'Support will review it.');
                    },
              child: const Text('Report a problem'),
            ),
          ),
      ]),
    );
  }

  Widget _fact(String label, String value) => value.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ]),
        );

  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What went wrong with this delivery?'),
        content: TextField(controller: controller, maxLines: 3, maxLength: 1000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }
}

class _QuotationCard extends StatelessWidget {
  const _QuotationCard({required this.quotation, this.action});

  final Json quotation;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrangements = asJsonList(quotation['arrangements']).map((a) => str(a['label'], str(a['code']))).join(', ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quotation ${str(quotation['reference'])} · v${intOf(quotation['version'], 1)} · ${quotation['expired'] == true ? 'expired' : str(quotation['status'])}', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text('${formatRwf(intOf(quotation['fee_rwf']))} delivery fee', style: theme.textTheme.titleLarge),
        if (_when(quotation['proposed_delivery_at']).isNotEmpty) Text('Delivery: ${_when(quotation['proposed_delivery_at'])}'),
        if (arrangements.isNotEmpty) Text('How: $arrangements'),
        if (str(quotation['arrangement_description']).isNotEmpty) Text(str(quotation['arrangement_description'])),
        if (str(quotation['conditions']).isNotEmpty) Text('Conditions: ${str(quotation['conditions'])}'),
        if (_when(quotation['valid_until']).isNotEmpty) Text('Valid until ${_when(quotation['valid_until'])}', style: theme.textTheme.bodySmall),
        if (str(quotation['decision_note']).isNotEmpty) Text("Customer's note: ${str(quotation['decision_note'])}", style: theme.textTheme.bodySmall),
        ?action,
      ]),
    );
  }
}

/// A formal quotation: the fee, when, how the kitchen delivers, conditions
/// and how long it stays valid. Once sent it cannot be edited.
class _QuotationForm extends StatefulWidget {
  const _QuotationForm({required this.request, required this.revising, required this.onSubmit, required this.onCancel});

  final Json request;
  final bool revising;
  final Future<void> Function(Json payload) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_QuotationForm> createState() => _QuotationFormState();
}

class _QuotationFormState extends State<_QuotationForm> {
  late final _fee = TextEditingController(
    text: widget.revising && widget.request['active_quotation'] is Map ? '${intOf(asJson(widget.request['active_quotation'])['fee_rwf'])}' : '',
  );
  late DateTime? _when = DateTime.tryParse(str(widget.request['requested_delivery_at']))?.toLocal();
  final Set<String> _arrangements = {};
  final _description = TextEditingController();
  final _conditions = TextEditingController();
  late final int _maxHours = intOf(widget.request['quotation_max_valid_hours'], 48);
  late final _hours = TextEditingController(text: '${_maxHours < 48 ? _maxHours : 48}');
  bool _sending = false;

  @override
  void dispose() {
    for (final c in [_fee, _description, _conditions, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: _when ?? now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? now));
    if (time == null) return;
    setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    final fee = int.tryParse(_fee.text.trim());
    if (fee == null || fee < 1) return showError(context, 'Enter the delivery fee as a whole number of RWF.');
    if (_when == null) return showError(context, 'Choose the delivery date and time.');
    if (_arrangements.isEmpty) return showError(context, 'Say how you will deliver.');
    if (_description.text.trim().isEmpty) return showError(context, 'Describe the delivery arrangement.');
    setState(() => _sending = true);
    await widget.onSubmit({
      'fee_rwf': fee,
      'proposed_delivery_at': _when!.toUtc().toIso8601String(),
      'arrangements': _arrangements.toList(),
      'arrangement_description': _description.text.trim(),
      'conditions': _conditions.text.trim(),
      'valid_hours': int.tryParse(_hours.text.trim()) ?? 48,
    });
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.revising ? 'Revised quotation' : 'Formal delivery quotation', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${widget.revising ? 'Your open quotation will be replaced (kept in the history). The customer must approve the new one.' : 'Once sent it cannot be edited: to change the price, send a revised quotation.'} '
          "You don't need to share your supplier or vehicle costs.",
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        AppTextField(label: 'Delivery fee (RWF)', controller: _fee, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickWhen,
          icon: const Icon(Icons.event_rounded),
          label: Text(_when == null ? 'Delivery date and time' : DateFormat('EEE d MMM yyyy, HH:mm').format(_when!)),
        ),
        const SizedBox(height: 10),
        Text("How you'll deliver", style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final option in asJsonList(widget.request['arrangement_options']))
            FilterChip(
              label: Text(str(option['label'], str(option['code']))),
              selected: _arrangements.contains(str(option['code'])),
              onSelected: (on) => setState(() => on ? _arrangements.add(str(option['code'])) : _arrangements.remove(str(option['code']))),
            ),
        ]),
        const SizedBox(height: 10),
        AppTextField(label: 'Describe the arrangement', controller: _description, maxLength: 1000, maxLines: 3, minLines: 2),
        AppTextField(label: 'Conditions (optional)', controller: _conditions, maxLength: 1000, maxLines: 2),
        AppTextField(
          label: 'Valid for (hours)',
          helper: 'Up to $_maxHours h, never past the delivery.',
          controller: _hours,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton(onPressed: _sending ? null : _submit, child: Text(_sending ? 'Sending…' : 'Send quotation'))),
          const SizedBox(width: 8),
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ]),
      ]),
    );
  }
}

/// The negotiation chat (text) with the customer.
class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.requestId, required this.open});

  final String requestId;
  final bool open;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _text = TextEditingController();
  List<Json> _messages = const [];
  String _privacy = '';
  bool _sending = false;
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
      final data = await ref.read(specialDeliveryRepositoryProvider).messages(widget.requestId);
      if (!mounted) return;
      final messages = asJsonList(data['messages']);
      final grew = messages.length != _messages.length;
      setState(() {
        _messages = messages;
        _privacy = str(data['privacy_note']);
      });
      if (grew && messages.isNotEmpty) ref.read(specialDeliveryRepositoryProvider).markRead(widget.requestId).ignore();
    } catch (_) {
      // Keep the last messages; the next poll tries again.
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await runAction(context, () async {
      await ref.read(specialDeliveryRepositoryProvider).sendMessage(widget.requestId, body);
      return true;
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent == true) {
      _text.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_privacy.isNotEmpty) Text(_privacy, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (_messages.isEmpty)
          Text(widget.open ? 'No messages yet.' : 'The chat opens once you accept to negotiate.', style: theme.textTheme.bodySmall),
        for (final m in _messages)
          Align(
            alignment: m['author_role'] == 'system' ? Alignment.center : m['mine'] == true ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: m['mine'] == true ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  switch (str(m['kind'], 'text')) {
                    'location' => '📍 Shared a location${str(asJson(m['location'])['label']).isNotEmpty ? ': ${str(asJson(m['location'])['label'])}' : ''}',
                    'image' => '🖼 Sent a photo${str(m['body']).isNotEmpty ? ': ${str(m['body'])}' : ''}',
                    _ => str(m['body']),
                  },
                  style: TextStyle(color: m['mine'] == true ? scheme.onPrimary : scheme.onSurface),
                ),
                Text(_when(m['created_at']), style: theme.textTheme.labelSmall?.copyWith(color: m['mine'] == true ? scheme.onPrimary.withValues(alpha: 0.7) : null)),
              ]),
            ),
          ),
        if (widget.open) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AppTextField(label: 'Write a message', controller: _text, maxLength: 2000, maxLines: 3, minLines: 1, onSubmitted: (_) => _send())),
            IconButton(tooltip: 'Send', onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
          ]),
        ],
      ]),
    );
  }
}
