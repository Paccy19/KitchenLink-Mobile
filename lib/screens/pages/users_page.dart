import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/status_sheet.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'vendors_page.dart';

const _roleStatuses = {
  'customer': ['active', 'suspended'],
  'vendor': ['pending', 'approved', 'rejected', 'suspended'],
  'driver': ['pending', 'approved', 'rejected', 'suspended'],
};

/// Every customer, vendor and delivery worker in one place.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final session = context.read<AdminSession>();
  String role = '';
  String status = '';
  String search = '';
  int page = 1;
  // Bumped by Reset so the search box clears.
  int resets = 0;

  late final query = Query<Json>(
    () async => jmap(await session.api.listUsers({'role': role, 'status': status, 'search': search, 'page': page, 'limit': 20})),
    client: session.client,
  );

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

  Future<void> _changeStatus(Json user) async {
    final result = await showAppSheet<dynamic>(
      context,
      StatusSheet(
        title: 'Change status · ${jstr(user['name'])}',
        statuses: _roleStatuses[user['role']] ?? const ['active', 'suspended'],
        current: jstr(user['status']),
        onSubmit: (payload) => session.api.setUserStatus(jstr(user['id']), {'role': user['role'], ...payload}),
      ),
    );
    if (result != null && mounted) showToast(context, '${toTitle(user['role'])} status updated.');
  }

  Future<void> _erase(Json user) async {
    final done = await showAppSheet<bool>(context, _EraseSheet(user: user));
    if (done == true && mounted) showToast(context, 'Customer data erased. Their orders stay in the books without personal details.');
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final searchBox = WebSearchInput(key: ValueKey(resets), hint: 'Search by name or phone…', onSubmit: (value) => apply(() => search = value));
    final roleSelect = WebSelect<String>(
      value: role,
      options: const {'': 'All roles', 'customer': 'Customers', 'vendor': 'Vendors', 'driver': 'Delivery workers'},
      onChanged: (value) => apply(() => role = value),
    );
    final statusSelect = WebSelect<String>(
      value: status,
      options: const {'': 'All statuses', 'active': 'Active', 'suspended': 'Suspended', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected'},
      onChanged: (value) => apply(() => status = value),
    );

    return PageBody(onRefresh: query.load, children: [
      const PageHeader(title: 'Users', description: 'Every customer, vendor and delivery worker in one place.'),
      SectionCard(
        title: 'Filters',
        action: SmallButton(
          'Reset',
          ghost: true,
          onPressed: () => apply(() {
            role = '';
            status = '';
            search = '';
            resets++;
          }),
        ),
        padding: const EdgeInsets.all(16),
        // `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4`, search spanning two columns.
        child: viewport >= 1024
            ? Row(children: [
                Expanded(flex: 2, child: searchBox),
                const SizedBox(width: 12),
                Expanded(child: roleSelect),
                const SizedBox(width: 12),
                Expanded(child: statusSelect),
              ])
            : viewport >= 640
                ? Column(children: spaced([
                    Row(children: [Expanded(child: searchBox), const SizedBox(width: 12), Expanded(child: roleSelect)]),
                    Row(children: [Expanded(child: statusSelect), const SizedBox(width: 12), const Spacer()]),
                  ]))
                : Column(children: spaced([searchBox, roleSelect, statusSelect])),
      ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = jlist(data['items']);
            if (items.isEmpty) {
              return const EmptyState(icon: Icons.people_outline, title: 'No users found', description: 'Try a different role, status or search term.');
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WebTable(
                columns: const [
                  WebColumn('Name'),
                  WebColumn('Role'),
                  WebColumn('Contact'),
                  WebColumn('Last location', nowrap: true),
                  WebColumn('Status', nowrap: true),
                  WebColumn('Joined'),
                  WebColumn('', alignEnd: true),
                ],
                rows: [for (final user in items) _row(user)],
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

  List<Widget> _row(Json user) {
    final p = Palette.of(context);
    final name = jstr(user['name'], 'User');
    final avatar = jstr(user['avatar_url']);
    // Customer's last GPS position (recorded while they use "Use my location").
    final location = user['last_location'] is Map ? jmap(user['last_location']) : null;
    final initials = (name.length >= 2 ? name.substring(0, 2) : name).toUpperCase();
    // `w-8 h-8 rounded-full bg-stone-200 text-stone-600 text-[11px] font-black` when there is no photo.
    final fallback = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: p.stone200, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.textSecondary)),
    );
    return [
      Row(mainAxisSize: MainAxisSize.min, children: [
        avatar.isEmpty
            ? fallback
            : ClipOval(child: Image.network(avatar, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)),
        const SizedBox(width: 10),
        Flexible(child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(toTitle(user['role']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
        if (jstr(user['secondary']).isNotEmpty) Text(toTitle(user['secondary']), style: TextStyle(fontSize: 11, color: p.faint)),
      ]),
      Text(jstr(user['identifier'], '—'), style: TextStyle(fontSize: 14, color: p.textSecondary)),
      location == null
          ? Text('—', style: TextStyle(fontSize: 12, color: p.faint))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () => openMaps(location['latitude'], location['longitude']),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.place_outlined, size: 14, color: p.accent == Palette.light.accent ? AppColors.brown : p.accent),
                  const SizedBox(width: 4),
                  Text(
                    '${jnum(location['latitude']).toStringAsFixed(5)}, ${jnum(location['longitude']).toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent == Palette.light.accent ? AppColors.brown : p.accent),
                  ),
                ]),
              ),
              Text(
                '${formatDate(location['updated_at'])}${location['accuracy_m'] != null ? ' · ±${jstr(location['accuracy_m'])} m' : ''}',
                style: TextStyle(fontSize: 11, color: p.faint),
              ),
            ]),
      StatusBadge(jstr(user['status'])),
      Text(formatDate(user['created_at'], withTime: false), style: TextStyle(fontSize: 12, color: p.muted)),
      !session.can('users:write')
          ? const SizedBox.shrink()
          : user['status'] == 'erased'
              ? Text('Data erased', style: TextStyle(fontSize: 12, color: p.faint))
              // The labels wrap onto two lines when the table is short of room, as on the website.
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: SmallButton('Change status', onPressed: () => _changeStatus(user))),
                  if (user['role'] == 'customer') ...[
                    const SizedBox(width: 6),
                    Flexible(child: SmallButton('Erase data', danger: true, onPressed: () => _erase(user))),
                  ],
                ]),
    ];
  }
}

/// Erasing a customer's personal data on their request (cannot be undone).
class _EraseSheet extends StatefulWidget {
  const _EraseSheet({required this.user});

  final Json user;

  @override
  State<_EraseSheet> createState() => _EraseSheetState();
}

class _EraseSheetState extends State<_EraseSheet> with BusyState {
  String confirm = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return SheetScaffold(
      title: 'Erase data · ${jstr(widget.user['name'])}',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Keep data')),
        BusyButton(
          label: 'Erase for good',
          busyLabel: 'Erasing…',
          danger: true,
          busy: busy,
          onPressed: confirm != 'ERASE'
              ? null
              : () async {
                  final ok = await run(() => api.eraseCustomer(jstr(widget.user['id'])));
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
        ),
      ],
      children: [
        const Text.rich(TextSpan(children: [
          TextSpan(text: 'Use this when the customer asks for their data to be deleted. It '),
          TextSpan(text: 'cannot be undone', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ':'),
        ])),
        const Text(
          '• Name, phone, email, photo and location are removed; the account is closed and signed out.\n'
          '• Their chats, notifications, cart and wishlist are deleted.\n'
          '• Orders and payments stay for the accounts, without address or payer details.\n'
          '• Complaints stay for support history, with their name and own messages removed.',
          style: TextStyle(fontSize: 12.5, height: 1.5),
        ),
        const Hint('Not possible while they have an order in progress or a refund still owed.'),
        TextField(
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Type ERASE to confirm', hintText: 'ERASE'),
          onChanged: (value) => setState(() => confirm = value.trim().toUpperCase()),
        ),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
