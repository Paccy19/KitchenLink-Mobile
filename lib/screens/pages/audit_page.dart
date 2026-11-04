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
    final p = Palette.of(context);
    final actionBox = WebInput(hint: 'Filter by action (e.g. vendor.suspended)…', onChanged: (value) => apply(() => action = value.trim()));
    final targetBox = WebInput(hint: 'Filter by target type (vendor, order, payout…)', onChanged: (value) => apply(() => targetType = value.trim()));
    return PageBody(onRefresh: query.load, children: [
      const PageHeader(title: 'Audit Log', description: 'Every admin action, recorded for accountability.'),
      SectionCard(
        title: 'Filters',
        // `grid sm:grid-cols-2 gap-3`.
        child: isSm(context)
            ? Row(children: [Expanded(child: actionBox), const SizedBox(width: 12), Expanded(child: targetBox)])
            : Column(children: spaced([actionBox, targetBox])),
      ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No audit entries', description: 'Admin actions will appear here.');
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WebTable(
                columns: const [
                  WebColumn('Admin'),
                  WebColumn('Action', nowrap: true),
                  WebColumn('Target'),
                  WebColumn('IP', nowrap: true),
                  WebColumn('When'),
                ],
                rows: [
                  for (final log in items)
                    [
                      CellText(jstr(log['admin_name'], '—'), sub: jstr(log['admin_email'])),
                      ToneBadge(jstr(log['action']), tone: Tone.violet),
                      CellText(toTitle(log['target_type']), sub: jstr(log['target_label']), bold: false, color: p.textSecondary),
                      Text(jstr(log['ip'], '—'), style: TextStyle(fontSize: 12, color: p.muted)),
                      Text(formatDate(log['created_at']), style: TextStyle(fontSize: 14, color: p.textSecondary)),
                    ],
                ],
              ),
              Pager.of(data, defaultLimit: 25, onPage: (next) {
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
