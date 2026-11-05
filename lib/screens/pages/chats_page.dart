import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/vendor_types.dart';
import '../../ui/widgets.dart';

/// Support: customer–kitchen chats, READ ONLY. Used when handling a complaint
/// or a refund to see what was agreed. Support never writes in these chats.
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, this.focusId});

  final String? focusId;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final session = context.read<AdminSession>();
  String applied = '';
  int page = 1;

  late final query = Query<Json>(
    () async => jmap(await session.api.listChats({'search': applied, 'page': page, 'limit': 20})),
    client: session.client,
    poll: const Duration(seconds: 30),
  );

  @override
  void initState() {
    super.initState();
    if (widget.focusId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.focusId!));
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PageBody(onRefresh: query.load, children: [
      const PageHeader(
        title: 'Customer–Kitchen Chats',
        description: 'Read the conversations between customers and kitchens when handling a complaint or refund. '
            'Read only — support cannot write in these chats.',
      ),
      SectionCard(
        padding: const EdgeInsets.all(16),
        // `relative max-w-md`.
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: WebSearchInput(
              hint: 'Search by customer or kitchen name or phone…',
              onSubmit: (value) {
                setState(() {
                  applied = value;
                  page = 1;
                });
                query.load();
              },
            ),
          ),
        ),
      ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.forum_outlined,
                title: 'No chats found',
                description: applied.isNotEmpty ? 'Try another name or phone.' : 'No customer has messaged a kitchen yet.',
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WebTable(
                columns: const [
                  WebColumn('Customer'),
                  WebColumn('Kitchen'),
                  WebColumn('Last message', nowrap: true),
                  WebColumn('Messages', nowrap: true),
                  WebColumn('', alignEnd: true, nowrap: true),
                ],
                rows: [
                  for (final chat in items)
                    [
                      CellText(jstr(jmap(chat['customer'])['name']), sub: jstr(jmap(chat['customer'])['phone'])),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(jstr(jmap(chat['vendor'])['name']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                        if (jmap(chat['vendor'])['vendor_type'] != null) ...[
                          const SizedBox(height: 4),
                          VendorTypeBadge(jmap(chat['vendor'])['vendor_type'], small: true),
                        ],
                      ]),
                      // `max-w-xs` with the preview cut to one line.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: chat['last_message_role'] == 'vendor' ? 'Kitchen: ' : 'Customer: ', style: TextStyle(color: p.faint)),
                              TextSpan(text: jstr(chat['last_message_preview'])),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: p.textSecondary),
                          ),
                          Text(formatDate(chat['last_message_at']), style: TextStyle(fontSize: 11, color: p.faint)),
                        ]),
                      ),
                      Text('${jint(chat['messages_count'])}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textSecondary)),
                      SmallButton('Read', icon: Icons.visibility_outlined, ghost: true, onPressed: () => _open(jstr(chat['id']))),
                    ],
                ],
              ),
              Pager.of(data, onPage: (next) {
                setState(() => page = next);
                query.load();
              }),
            ]);
          },
        ),
      ),
    ]);
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.getChat(widget.chatId, {'limit': 200})));

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final chat = jmap(query.data?['conversation']);
        return Scaffold(
          appBar: AppBar(
            title: Text(chat.isEmpty ? 'Chat' : '${jstr(jmap(chat['customer'])['name'])} ↔ ${jstr(jmap(chat['vendor'])['name'])}'),
          ),
          body: QueryView<Json>(query: query, builder: (context, data) => _body(data)),
        );
      },
    );
  }

  Widget _body(Json data) {
    final chat = jmap(data['conversation']);
    final customer = jmap(chat['customer']);
    final vendor = jmap(chat['vendor']);
    final messages = jlist(data['messages']);
    final scheme = Theme.of(context).colorScheme;
    return PageBody(children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const ToneBadge('Read only'),
        Hint('Customer: ${jstr(customer['name'])}${jstr(customer['phone']).isNotEmpty ? ' · ${jstr(customer['phone'])}' : ''}'),
        Hint('Kitchen: ${jstr(vendor['name'])}${jstr(vendor['phone']).isNotEmpty ? ' · ${jstr(vendor['phone'])}' : ''}'),
      ]),
      if (data['has_more'] == true) const Hint('Showing the latest 200 messages.'),
      for (final message in messages)
        Align(
          alignment: message['author_role'] == 'vendor' ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: message['author_role'] == 'vendor' ? scheme.surface : const Color(0xFF0284C7).withValues(alpha: 0.10),
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                (message['author_role'] == 'vendor' ? jstr(vendor['name']) : jstr(customer['name'])).toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.onSurfaceVariant),
              ),
              Text(jstr(message['body'])),
              Align(alignment: Alignment.centerRight, child: Hint(formatDate(message['created_at']))),
            ]),
          ),
        ),
    ]);
  }
}
