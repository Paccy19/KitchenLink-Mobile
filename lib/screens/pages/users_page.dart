import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/status_sheet.dart';
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
    return PageBody(onRefresh: query.load, children: [
      const PageHeader(title: 'Users', description: 'Every customer, vendor and delivery worker in one place.'),
      SectionCard(
        title: 'Filters',
        action: TextButton(
          onPressed: () => apply(() {
            role = '';
            status = '';
            search = '';
            resets++;
          }),
          child: const Text('Reset'),
        ),
        child: Column(children: spaced([
          SearchField(key: ValueKey(resets), hint: 'Search by name or phone…', onSubmit: (value) => apply(() => search = value)),
          Row(children: [
            Expanded(
              child: Dropdown<String>(
                value: role,
                options: const {'': 'All roles', 'customer': 'Customers', 'vendor': 'Vendors', 'driver': 'Delivery workers'},
                onChanged: (value) => apply(() => role = value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Dropdown<String>(
                value: status,
                options: const {
                  '': 'All statuses',
                  'active': 'Active',
                  'suspended': 'Suspended',
                  'pending': 'Pending',
                  'approved': 'Approved',
                  'rejected': 'Rejected',
                },
                onChanged: (value) => apply(() => status = value),
              ),
            ),
          ]),
        ])),
      ),
      QueryView<Json>(
        query: query,
        builder: (context, data) {
          final items = jlist(data['items']);
          if (items.isEmpty) {
            return const Card(
              child: EmptyState(icon: Icons.people_outline, title: 'No users found', description: 'Try a different role, status or search term.'),
            );
          }
          return RecordList(
            footer: Pager.of(data, onPage: (next) {
              setState(() => page = next);
              query.load();
            }),
            children: [for (final user in items) _row(user)],
          );
        },
      ),
    ]);
  }

  Widget _row(Json user) {
    final name = jstr(user['name'], 'User');
    final avatar = jstr(user['avatar_url']);
    // Customer's last GPS position (recorded while they use "Use my location").
    final location = user['last_location'] is Map ? jmap(user['last_location']) : null;
    final initials = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    return RecordTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
        child: avatar.isEmpty ? Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)) : null,
      ),
      title: name,
      subtitle: '${toTitle(user['role'])}${jstr(user['secondary']).isNotEmpty ? ' · ${toTitle(user['secondary'])}' : ''}',
      badges: [StatusBadge(jstr(user['status']))],
      lines: [
        jstr(user['identifier'], '—'),
        'Joined ${formatDate(user['created_at'], withTime: false)}',
        if (location != null)
          'Last location ${formatDate(location['updated_at'])}${location['accuracy_m'] != null ? ' · ±${jstr(location['accuracy_m'])} m' : ''}',
      ],
      actions: [
        if (location != null)
          TextButton.icon(
            onPressed: () => openMaps(location['latitude'], location['longitude']),
            icon: const Icon(Icons.place_outlined, size: 16),
            label: Text('${jnum(location['latitude']).toStringAsFixed(5)}, ${jnum(location['longitude']).toStringAsFixed(5)}'),
          ),
        if (session.can('users:write'))
          if (user['status'] == 'erased')
            const Hint('Data erased')
          else ...[
            OutlinedButton(onPressed: () => _changeStatus(user), child: const Text('Change status')),
            if (user['role'] == 'customer')
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                onPressed: () => _erase(user),
                child: const Text('Erase data'),
              ),
          ],
      ],
    );
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
