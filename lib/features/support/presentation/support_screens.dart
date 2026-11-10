import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/support_providers.dart';
import '../models/support.dart';

Tone _toneFor(String status) => switch (status) {
      'resolved' => Tone.success,
      'rejected' => Tone.neutral,
      'in_review' => Tone.info,
      _ => Tone.warning,
    };

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(supportListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/support/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      body: AsyncBody<SupportList>(
        value: state,
        onRefresh: () => ref.read(supportListProvider.notifier).reload(silent: false),
        builder: (context, list) {
          if (list.tickets.isEmpty) {
            return RefreshableEmpty(
              icon: Icons.support_agent_rounded,
              title: 'No support requests',
              message: 'Need help with an order, a payout or your account? Our team will answer here.',
              action: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                onPressed: () => context.push('/support/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Contact support'),
              ),
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: list.tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ticket = list.tickets[index];
              return AppCard(
                onTap: () => context.push('/support/${ticket.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(ticket.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                    if (ticket.unread) Container(width: 9, height: 9, decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 4),
                  Text(ticket.lastMessagePreview, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    StatusChip(label: ticket.statusLabel, tone: _toneFor(ticket.status), dense: true),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${ticket.reference} · ${timeAgo(ticket.lastMessageAt)}', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class NewSupportRequestScreen extends ConsumerStatefulWidget {
  const NewSupportRequestScreen({super.key});

  @override
  ConsumerState<NewSupportRequestScreen> createState() => _NewSupportRequestScreenState();
}

class _NewSupportRequestScreenState extends ConsumerState<NewSupportRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'other';
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  static const _fallbackCategories = ['order', 'payment', 'account', 'app', 'other'];

  /// The server's categories; the built-in list while they load, or if the
  /// server sent none (an empty list would crash the dropdown).
  static List<String> _categoriesOf(SupportList? list) {
    final fromServer = list?.categories ?? const <String>[];
    return fromServer.isEmpty ? _fallbackCategories : fromServer;
  }

  /// The category the dropdown shows, which is the one sent.
  String _selected(List<String> categories) => categories.contains(_category) ? _category : categories.first;

  Future<void> _send() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final category = _selected(_categoriesOf(ref.read(supportListProvider).value));
    final ticket = await runAction(
      context,
      () => ref.read(supportActionsProvider).create(subject: _subject.text, message: _message.text, category: category),
      success: 'Your request was sent. We will reply here.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ticket != null) context.pushReplacement('/support/${ticket.id}');
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categoriesOf(ref.watch(supportListProvider).value);
    return Scaffold(
      appBar: AppBar(title: const Text('New support request')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: FormPage(children: [
            DropdownButtonFormField<String>(
              initialValue: _selected(categories),
              decoration: const InputDecoration(labelText: 'What is it about?'),
              items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(humanize(c)))],
              onChanged: (value) => setState(() => _category = value ?? 'other'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Subject',
              controller: _subject,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => Validators.length(value, 'Subject', min: 3, max: 120),
            ),
            const SizedBox(height: 6),
            AppTextField(
              label: 'Tell us what happened',
              controller: _message,
              maxLength: 2000,
              maxLines: 7,
              minLines: 5,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => Validators.length(value, 'Message', min: 2, max: 2000),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _send,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Send request'),
            ),
          ]),
        ),
      ),
    );
  }
}

class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reply() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      await ref.read(supportTicketProvider(widget.ticketId).notifier).reply(text);
      return true;
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok == true) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = supportTicketProvider(widget.ticketId);
    final state = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(state.value?.reference ?? 'Support request')),
      body: Column(children: [
        Expanded(
          child: AsyncBody<SupportTicket>(
            value: state,
            onRefresh: () => ref.read(provider.notifier).reload(silent: false),
            builder: (context, ticket) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(children: [
                  Expanded(child: Text(ticket.subject, style: theme.textTheme.titleLarge)),
                  StatusChip(label: ticket.statusLabel, tone: _toneFor(ticket.status)),
                ]),
                const SizedBox(height: 14),
                for (final message in ticket.messages)
                  Align(
                    alignment: message.fromSupport ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: message.fromSupport ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(message.fromSupport ? 'Support team' : 'You', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(message.body),
                        const SizedBox(height: 4),
                        Text(formatDateTime(message.at), style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                if (ticket.isClosed)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: NoteBox(message: 'This request is closed. Replying will re-open it.', icon: Icons.lock_open_rounded),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write a reply', counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _reply,
                icon: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
