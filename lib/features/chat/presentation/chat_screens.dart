import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../application/chat_providers.dart';
import '../models/chat.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: AsyncBody<List<ChatConversation>>(
        value: state,
        onRefresh: () => ref.read(chatListProvider.notifier).reload(silent: false),
        builder: (context, list) {
          if (list.isEmpty) {
            return const RefreshableEmpty(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No messages yet',
              message: 'Customers who have ordered from you can message you here.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final chat = list[index];
              return AppCard(
                onTap: () => context.push('/messages/${chat.id}'),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(initials(chat.customerName), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(chat.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                        Text(timeAgo(chat.lastMessageAt), style: theme.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        '${chat.lastMessageMine ? 'You: ' : ''}${chat.preview}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: chat.unreadCount > 0 ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                          fontWeight: chat.unreadCount > 0 ? FontWeight.w700 : null,
                        ),
                      ),
                    ]),
                  ),
                  if (chat.unreadCount > 0) ...[const SizedBox(width: 8), CountBadge(count: chat.unreadCount)],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      await ref.read(chatThreadProvider(widget.conversationId).notifier).send(text);
      return true;
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok == true) _controller.clear();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = chatThreadProvider(widget.conversationId);
    final state = ref.watch(provider);
    final thread = state.value;
    if (thread != null && thread.messages.length != _lastCount) {
      _lastCount = thread.messages.length;
      _scrollToEnd();
    }
    return Scaffold(
      appBar: AppBar(title: Text(thread?.conversation.customerName ?? 'Conversation')),
      body: Column(children: [
        Expanded(
          child: AsyncBody<ChatThread>(
            value: state,
            onRefresh: () => ref.read(provider.notifier).reload(silent: false),
            builder: (context, data) => ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                if (data.hasMore)
                  TextButton(
                    onPressed: () => runAction(context, () => ref.read(provider.notifier).loadOlder()),
                    child: const Text('Load earlier messages'),
                  ),
                if (data.privacyNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(data.privacyNote, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  ),
                if (data.messages.isEmpty)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No messages yet.'))),
                for (final message in data.messages) _Bubble(message: message),
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
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write a message', counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(message.body, style: TextStyle(color: mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(
            formatTime(message.createdAt),
            style: TextStyle(fontSize: 10.5, color: (mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface).withValues(alpha: 0.65)),
          ),
        ]),
      ),
    );
  }
}
