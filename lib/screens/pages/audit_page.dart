import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Every admin action, recorded for accountability.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late final session = context.read<AdminSession>();
  String action = '';
  String targetType = '';
  int page = 1;
  Timer? _debounce;

  late final query = Query<Json>(
    () async => jmap(await session.api.listActions({'action': action, 'target_type': targetType, 'page': page, 'limit': 25})),
    client: session.client,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void apply(VoidCallback change) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        change();
        page = 1;
      });
      query.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: query.load, children: [
      const PageHeader(title: 'Audit Log', description: 'Every admin action, recorded for accountability.'),
      SectionCard(
        title: 'Filters',
        child: Column(children: spaced([
          SearchField(hint: 'Filter by action (e.g. vendor.suspended)…', live: true, onSubmit: (value) => apply(() => action = value)),
          SearchField(hint: 'Filter by target type (vendor, order, payout…)', live: true, onSubmit: (value) => apply(() => targetType = value)),
        ])),
      ),
      QueryView<Json>(
        query: query,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return const Card(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No audit entries', description: 'Admin actions will appear here.'));
          }
          return RecordList(
            footer: Pager.of(data, defaultLimit: 25, onPage: (next) {
              setState(() => page = next);
              query.load();
            }),
            children: [
              for (final log in items)
                RecordTile(
                  title: jstr(log['admin_name'], '—'),
                  subtitle: jstr(log['admin_email']),
                  badges: [ToneBadge(jstr(log['action']), tone: Tone.violet)],
                  lines: [
                    '${toTitle(log['target_type'])}${jstr(log['target_label']).isNotEmpty ? ' · ${jstr(log['target_label'])}' : ''}',
                    'IP ${jstr(log['ip'], '—')} · ${formatDate(log['created_at'])}',
                  ],
                ),
            ],
          );
        },
      ),
    ]);
  }
}
