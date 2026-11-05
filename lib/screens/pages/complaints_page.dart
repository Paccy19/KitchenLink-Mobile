import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/validation.dart';
import '../../ui/widgets.dart';

const _statuses = ['open', 'in_review', 'resolved', 'rejected'];
const _priorities = ['low', 'medium', 'high', 'urgent'];
const _categories = ['order', 'delivery', 'payment', 'refund', 'vendor', 'driver', 'account', 'app', 'other'];
const _roleLabel = {'customer': 'Customer', 'vendor': 'Vendor', 'driver': 'Delivery worker', 'admin': 'Admin', 'guest': 'Guest'};
const _roleTone = {'customer': Tone.blue, 'vendor': Tone.violet, 'driver': Tone.green};
const _priorityTone = {'low': Tone.slate, 'medium': Tone.blue, 'high': Tone.amber, 'urgent': Tone.red};

/// Conversations with customers, vendors and delivery workers who need help.
class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key, this.focusId});

  final String? focusId;

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  late final session = context.read<AdminSession>();
  String status = '';
  String category = '';
  String priority = '';
  String search = '';
  int page = 1;

  late final query = Query<Json>(
    () async => jmap(await session.api.listComplaints({
      'status': status,
      'category': category,
      'priority': priority,
      'search': search,
      'page': page,
      'limit': 20,
    })),
    client: session.client,
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

  void apply(VoidCallback change) {
    setState(() {
      change();
      page = 1;
    });
    query.load();
  }

  void _open(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintDetailScreen(complaintId: id)));

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final p = Palette.of(context);
    final filters = [
      WebSearchInput(hint: 'Search subject or reference…', onSubmit: (value) => apply(() => search = value)),
      WebSelect<String>(
        value: status,
        options: {'': 'All statuses', for (final s in _statuses) s: toTitle(s)},
        onChanged: (value) => apply(() => status = value),
      ),
      WebSelect<String>(
        value: category,
        options: {'': 'All categories', for (final c in _categories) c: toTitle(c)},
        onChanged: (value) => apply(() => category = value),
      ),
      WebSelect<String>(
        value: priority,
        options: {'': 'All priorities', for (final pr in _priorities) pr: toTitle(pr)},
        onChanged: (value) => apply(() => priority = value),
      ),
    ];

    return PageBody(onRefresh: query.load, children: [
      PageHeader(
        title: 'Support & Complaints',
        description: 'Conversations with customers, vendors and delivery workers who need help. Unread ones are on top.',
        action: session.can('complaints:write')
            ? WebButton(label: 'Log complaint', icon: Icons.add, onPressed: () => showAppSheet(context, const _CreateSheet()))
            : null,
      ),
      ListenableBuilder(
        listenable: query,
        builder: (context, _) {
          final counts = jmap(query.data?['counts']);
          // `grid-cols-2 lg:grid-cols-5 gap-3`.
          return ResponsiveGrid(minWidth: 1, maxColumns: viewport >= 1024 ? 5 : 2, children: [
            StatCard(label: 'New messages', value: formatNumber(counts['unread'])),
            for (final s in _statuses) StatCard(label: toTitle(s), value: formatNumber(counts[s])),
          ]);
        },
      ),
      SectionCard(
        title: 'Filters',
        padding: const EdgeInsets.all(16),
        // `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3`.
        child: ResponsiveGrid(minWidth: 1, maxColumns: viewport >= 1024 ? 4 : viewport >= 640 ? 2 : 1, equalHeights: false, children: filters),
      ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const EmptyState(icon: Icons.report_outlined, title: 'No complaints', description: 'All clear for now.');
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WebTable(
                columns: const [
                  WebColumn('Subject'),
                  WebColumn('From'),
                  WebColumn('Category'),
                  WebColumn('Priority', nowrap: true),
                  WebColumn('Status', nowrap: true),
                  WebColumn('Last activity'),
                  WebColumn('', alignEnd: true, nowrap: true),
                ],
                rows: [
                  for (final row in items)
                    [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (row['unread'] == true) ...[
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.red500, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                          ],
                          Flexible(child: Text(jstr(row['subject']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
                        ]),
                        Text(
                          '${jstr(row['reference'])}${jlist(row['messages']).isNotEmpty ? ' · ${jlist(row['messages']).length} message${jlist(row['messages']).length > 1 ? 's' : ''}' : ''}',
                          style: TextStyle(fontSize: 11, color: p.faint),
                        ),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        ToneBadge(_roleLabel[jmap(row['raised_by'])['role']] ?? 'Guest', tone: _roleTone[jmap(row['raised_by'])['role']] ?? Tone.slate),
                        const SizedBox(height: 2),
                        Text(jstr(jmap(row['raised_by'])['name'], jstr(jmap(row['raised_by'])['phone'])), style: TextStyle(fontSize: 11, color: p.muted)),
                      ]),
                      Text(toTitle(row['category']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                      ToneBadge(toTitle(row['priority']), tone: _priorityTone[row['priority']] ?? Tone.slate),
                      StatusBadge(jstr(row['status'])),
                      Text(formatDate(row['last_message_at'] ?? row['created_at']), style: TextStyle(fontSize: 12, color: p.muted)),
                      SmallButton(row['unread'] == true ? 'Reply' : 'Open', primary: row['unread'] == true, onPressed: () => _open(jstr(row['id']))),
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

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> with BusyState {
  final subject = TextEditingController();
  final description = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  String category = 'other';
  String priority = 'medium';

  @override
  void dispose() {
    for (final c in [subject, description, name, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get valid => subject.text.trim().length >= 3 && (phone.text.isEmpty || isValidRwandaPhone(phone.text));

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return SheetScaffold(
      title: 'Log a complaint',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Create',
          busy: busy,
          onPressed: !valid
              ? null
              : () async {
                  final ok = await run(() => api.createComplaint({
                        'subject': subject.text.trim(),
                        'description': description.text.trim(),
                        'category': category,
                        'priority': priority,
                        'name': name.text.trim(),
                        'phone': phone.text.trim(),
                      }));
                  if (ok && context.mounted) Navigator.pop(context);
                },
        ),
      ],
      children: [
        TextField(controller: subject, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Subject', hintText: 'Brief summary')),
        TextField(controller: description, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Description')),
        Row(children: [
          Expanded(
            child: Dropdown<String>(
              label: 'Category',
              value: category,
              options: {for (final c in _categories) c: toTitle(c)},
              onChanged: (value) => setState(() => category = value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Dropdown<String>(
              label: 'Priority',
              value: priority,
              options: {for (final p in _priorities) p: toTitle(p)},
              onChanged: (value) => setState(() => priority = value),
            ),
          ),
        ]),
        TextField(
          controller: name,
          inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: formatNameInput(next.text)))],
          decoration: const InputDecoration(labelText: 'Reporter name (optional)'),
        ),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizePhoneInput(next.text)))],
          decoration: InputDecoration(
            labelText: 'Reporter phone (optional)',
            hintText: phonePlaceholder,
            errorText: phone.text.isNotEmpty && !isValidRwandaPhone(phone.text) ? phoneError : null,
            errorMaxLines: 2,
          ),
        ),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

/// One complaint: the conversation, a reply the user sees, internal notes,
/// and status / priority changes.
class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});

  final String complaintId;

  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> with BusyState {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.getComplaint(widget.complaintId)), client: session.client);
  String status = '';
  String priority = '';
  final note = TextEditingController();
  final reply = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    note.dispose();
    reply.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final payload = <String, dynamic>{
      if (status.isNotEmpty) 'status': status,
      if (priority.isNotEmpty) 'priority': priority,
      if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
      if (reply.text.trim().isNotEmpty) 'reply': reply.text.trim(),
    };
    final ok = await run(() => session.api.updateComplaint(widget.complaintId, payload));
    if (ok && mounted) {
      setState(() {
        status = '';
        priority = '';
        note.clear();
        reply.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(jstr(jmap(query.data?['complaint'])['reference'], 'Complaint'))),
        body: QueryView<Json>(query: query, builder: (context, data) => _body(jmap(data['complaint']))),
      ),
    );
  }

  Widget _body(Json complaint) {
    final raisedBy = jmap(complaint['raised_by']);
    final messages = jlist(complaint['messages']);
    final notes = jlist(complaint['notes']);
    final canWrite = session.can('complaints:write');
    final canReply = raisedBy['user_id'] != null && const ['customer', 'vendor', 'driver'].contains(raisedBy['role']);
    final scheme = Theme.of(context).colorScheme;

    return PageBody(onRefresh: query.load, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          StatusBadge(jstr(complaint['status'])),
          ToneBadge(toTitle(complaint['priority']), tone: _priorityTone[complaint['priority']] ?? Tone.slate),
          ToneBadge(toTitle(complaint['category']), tone: Tone.violet),
        ]),
        const SizedBox(height: 8),
        Text(jstr(complaint['subject']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        if (messages.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(jstr(complaint['description'], '—'))),
        const SizedBox(height: 6),
        Hint('Raised by ${_roleLabel[raisedBy['role']] ?? 'Guest'} ${jstr(raisedBy['name'])}'
            '${jstr(raisedBy['phone']).isNotEmpty ? ' · ${jstr(raisedBy['phone'])}' : ''} · ${formatDate(complaint['created_at'])}'),
      ]),
      if (messages.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionLabel('Conversation'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              for (final message in messages) _bubble(message),
            ]),
          ),
        ]),
      if (canReply && canWrite)
        TextField(
          controller: reply,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Reply to ${jstr(raisedBy['name'], 'the user')} (they see this and get notified)',
            hintText: 'Write your answer…',
            alignLabelWithHint: true,
          ),
        ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('Internal notes (only the support team sees these)'),
        if (notes.isEmpty) const Hint('No notes yet.'),
        for (final entry in notes)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(jstr(entry['body'])),
              Hint('${jstr(entry['author_name'])} · ${formatDate(entry['at'])}'),
            ]),
          ),
      ]),
      if (canWrite)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
          const Divider(),
          Row(children: [
            Expanded(
              child: Dropdown<String>(
                label: 'Status',
                value: status,
                options: {'': 'No change', for (final s in _statuses) s: toTitle(s)},
                onChanged: (value) => setState(() => status = value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Dropdown<String>(
                label: 'Priority',
                value: priority,
                options: {'': 'No change', for (final p in _priorities) p: toTitle(p)},
                onChanged: (value) => setState(() => priority = value),
              ),
            ),
          ]),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Add an internal note', hintText: 'Internal resolution notes…', alignLabelWithHint: true),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(label: reply.text.trim().isNotEmpty ? 'Send reply' : 'Save changes', busy: busy, onPressed: save),
          ),
          if (actionError != null) ErrorNote(error: actionError),
        ])),
    ]);
  }

  Widget _bubble(Json message) {
    final fromSupport = message['author_role'] == 'admin';
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromSupport ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fromSupport ? AppColors.brown : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: fromSupport ? null : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            fromSupport ? 'Support · ${jstr(message['author_name'])}' : jstr(message['author_name'], _roleLabel[message['author_role']] ?? ''),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: fromSupport ? Colors.white70 : AppColors.brown),
          ),
          Text(jstr(message['body']), style: TextStyle(color: fromSupport ? Colors.white : null)),
          Text(formatDate(message['at']), style: TextStyle(fontSize: 10, color: fromSupport ? Colors.white60 : scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
