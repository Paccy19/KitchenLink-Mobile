import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/action_code_field.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/validation.dart';
import '../../ui/widgets.dart';

const _statusTone = {'active': Tone.green, 'invited': Tone.amber, 'invite_expired': Tone.red, 'deactivated': Tone.slate};
const _statusLabel = {'active': 'Active', 'invited': 'Invitation sent', 'invite_expired': 'Invitation expired', 'deactivated': 'Deactivated'};

/// The owner's team. Only the owner (super admin) can invite a member by email
/// and role; the system emails an invitation and the member sets their own
/// password. Changes that need it are confirmed with the owner's SMS code.
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.listTeam()), client: session.client);
  String inviteLink = '';
  bool showRoles = false;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  List<Json> get roles => jlist(query.data?['roles']);

  Future<void> after(dynamic result, String message) async {
    if (result == null || !mounted) return;
    final link = jstr(jmap(result)['invite_url']);
    setState(() => inviteLink = link);
    showToast(context, link.isNotEmpty && message != 'Invitation sent.' ? 'New link ready — share it above.' : message);
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(onRefresh: query.load, children: [
      PageHeader(
        title: 'Team',
        description: 'Invite staff by email, give them a role, and the system sends the invitation to set their own password.',
        action: FilledButton.icon(
          onPressed: () async {
            setState(() => inviteLink = '');
            after(await showAppSheet<dynamic>(context, _InviteSheet(roles: roles)), 'Invitation sent.');
          },
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Invite'),
        ),
      ),
      if (inviteLink.isNotEmpty)
        SectionCard(
          title: 'Share this invitation link',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            const Hint('The email could not be sent automatically. Send this link to the member yourself; it lets them set their password.'),
            SelectableText(inviteLink, style: const TextStyle(fontSize: 12)),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inviteLink));
                showToast(context, 'Copied');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ], 8)),
        ),
      QueryView<Json>(
        query: query,
        builder: (context, data) {
          final members = jlist(data['members']);
          if (members.isEmpty) {
            return const Card(child: EmptyState(icon: Icons.groups_outlined, title: 'No team members', description: 'Invite your first team member.'));
          }
          return RecordList(children: [for (final member in members) _memberRow(member)]);
        },
      ),
      ListenableBuilder(
        listenable: query,
        builder: (context, _) => SectionCard(
          title: 'Roles & permissions',
          description: 'What each role may do. The owner (super admin) can do everything.',
          action: TextButton(onPressed: () => setState(() => showRoles = !showRoles), child: Text(showRoles ? 'Hide' : 'Show')),
          child: showRoles ? _roleReference(query.data ?? const {}) : const SizedBox.shrink(),
        ),
      ),
    ]);
  }

  Widget _memberRow(Json member) {
    final status = jstr(member['status']);
    final isOwner = member['is_owner'] == true;
    Future<void> confirm(String type) async => after(await showAppSheet<dynamic>(context, _ConfirmSheet(type: type, member: member)), _confirmMeta[type]!.message);
    return RecordTile(
      title: jstr(member['name'], '—'),
      subtitle: jstr(member['email']),
      badges: [
        ToneBadge(jstr(member['role_label'])),
        if (isOwner) const ToneBadge('Owner', tone: Tone.violet),
        ToneBadge(_statusLabel[status] ?? toTitle(status), tone: _statusTone[status] ?? Tone.slate),
        if (member['two_factor_enabled'] == true) const ToneBadge('SMS codes', tone: Tone.green, icon: Icons.verified_user_outlined),
      ],
      lines: [
        if (status == 'invited' && member['invite_expires_at'] != null) 'Expires ${formatDate(member['invite_expires_at'], withTime: false)}',
        if (member['two_factor_enabled'] != true) jstr(member['phone'], 'No phone yet'),
        'Last login: ${member['last_login_at'] != null ? formatDate(member['last_login_at']) : 'Never'}',
      ],
      actions: isOwner
          ? const [Hint('Owner account')]
          : [
              if (status == 'deactivated')
                OutlinedButton.icon(onPressed: () => confirm('reactivate'), icon: const Icon(Icons.how_to_reg_outlined, size: 16), label: const Text('Reactivate'))
              else ...[
                OutlinedButton.icon(
                  onPressed: () async => after(await showAppSheet<dynamic>(context, _RoleSheet(member: member, roles: roles)), 'Role updated.'),
                  icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                  label: const Text('Role'),
                ),
                OutlinedButton.icon(onPressed: () => confirm('resend'), icon: const Icon(Icons.refresh, size: 16), label: const Text('New link')),
                OutlinedButton.icon(onPressed: () => confirm('deactivate'), icon: const Icon(Icons.person_off_outlined, size: 16), label: const Text('Deactivate')),
              ],
              IconButton(onPressed: () => confirm('remove'), icon: const Icon(Icons.delete_outline)),
            ],
    );
  }

  /// The roles, grouped by the same categories as the panel (owner reference).
  Widget _roleReference(Json data) {
    final categories = jlist(data['categories']);
    final permissions = jlist(data['permissions']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
      for (final role in jlist(data['roles']))
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(jstr(role['label']), style: const TextStyle(fontWeight: FontWeight.w900)),
            Hint(jstr(role['description'])),
            const SizedBox(height: 8),
            for (final category in categories)
              Builder(builder: (context) {
                final owned = ((role['permissions'] as List?) ?? const []).map((e) => e.toString()).toSet();
                final allowed = permissions.where((p) => p['category'] == category['id'] && owned.contains(jstr(p['id']))).toList();
                if (allowed.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Hint(jstr(category['label']).toUpperCase()),
                    const SizedBox(height: 3),
                    Wrap(spacing: 4, runSpacing: 4, children: [for (final p in allowed) ToneBadge(jstr(p['label']))]),
                  ]),
                );
              }),
          ]),
        ),
    ]));
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.roles});

  final List<Json> roles;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> with BusyState {
  final email = TextEditingController();
  final name = TextEditingController();
  late String role = widget.roles.isEmpty ? '' : jstr(widget.roles.first['id']);

  @override
  void dispose() {
    email.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final selected = widget.roles.where((r) => jstr(r['id']) == role).firstOrNull;
    final emailInvalid = email.text.contains('@') && email.text.length > 3 && !isValidEmail(email.text);
    return SheetScaffold(
      title: 'Invite a team member',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Send invitation',
          busyLabel: 'Sending…',
          busy: busy,
          onPressed: !isValidEmail(email.text) || role.isEmpty
              ? null
              : () async {
                  dynamic result;
                  final ok = await run(() async => result = await api.inviteMember({'email': email.text.trim(), 'name': name.text.trim(), 'role': role}));
                  if (ok && context.mounted) Navigator.pop(context, result ?? {});
                },
        ),
      ],
      children: [
        const Text('We email them a link to set their own password. They then sign in at the admin sign-in page with that email and password.'),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: sanitizeEmailInput(next.text)))],
          decoration: InputDecoration(labelText: 'Email address', hintText: 'name@example.com', errorText: emailInvalid ? emailError : null),
        ),
        TextField(
          controller: name,
          inputFormatters: [TextInputFormatter.withFunction((_, next) => next.copyWith(text: formatNameInput(next.text)))],
          decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'e.g. Aline Uwase'),
        ),
        Dropdown<String>(
          label: 'Role',
          value: role,
          options: {for (final r in widget.roles) jstr(r['id']): jstr(r['label'])},
          onChanged: (value) => setState(() => role = value),
        ),
        if (selected != null) Hint(jstr(selected['description'])),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

class _RoleSheet extends StatefulWidget {
  const _RoleSheet({required this.member, required this.roles});

  final Json member;
  final List<Json> roles;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> with BusyState {
  late String role = jstr(widget.member['role']);
  String code = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final selected = widget.roles.where((r) => jstr(r['id']) == role).firstOrNull;
    return SheetScaffold(
      title: 'Change role · ${jstr(widget.member['name'], jstr(widget.member['email']))}',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: 'Save role',
          busy: busy,
          onPressed: code.length != 6 || role == widget.member['role']
              ? null
              : () async {
                  dynamic result;
                  final ok = await run(() async => result = await api.changeMemberRole(jstr(widget.member['id']), {'role': role, 'action_code': code}));
                  if (ok && context.mounted) Navigator.pop(context, result ?? {});
                },
        ),
      ],
      children: [
        const Text('Their access changes immediately; the next request they make is checked against the new role.'),
        Dropdown<String>(
          label: 'Role',
          value: role,
          options: {for (final r in widget.roles) jstr(r['id']): jstr(r['label'])},
          onChanged: (value) => setState(() => role = value),
        ),
        if (selected != null) Hint(jstr(selected['description'])),
        ActionCodeField(purpose: 'team_change', onChanged: (value) => setState(() => code = value)),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}

class _ConfirmMeta {
  const _ConfirmMeta(this.title, this.confirm, this.message, {this.needsCode = false, this.danger = false});

  final String title;
  final String confirm;
  final String message;
  final bool needsCode;
  final bool danger;
}

const _confirmMeta = {
  'resend': _ConfirmMeta('Send a new invitation', 'Send a new invitation link', 'Invitation re-sent.'),
  'deactivate': _ConfirmMeta('Deactivate member', 'Deactivate access', 'Member deactivated.', danger: true),
  'reactivate': _ConfirmMeta('Reactivate member', 'Restore access', 'Member reactivated.', needsCode: true),
  'remove': _ConfirmMeta('Remove member', 'Remove from team', 'Member removed.', danger: true),
};

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({required this.type, required this.member});

  final String type;
  final Json member;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> with BusyState {
  String code = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final meta = _confirmMeta[widget.type]!;
    final id = jstr(widget.member['id']);
    final who = jstr(widget.member['name'], jstr(widget.member['email']));
    final text = switch (widget.type) {
      'remove' => '$who loses access immediately. Their past actions stay in the audit log.',
      'deactivate' => '$who is signed out and cannot sign in until reactivated.',
      'reactivate' => 'Restore access for $who.',
      _ => 'A fresh link is emailed to ${jstr(widget.member['email'])}.',
    };
    return SheetScaffold(
      title: meta.title,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(
          label: meta.confirm,
          busyLabel: 'Working…',
          danger: meta.danger,
          busy: busy,
          onPressed: meta.needsCode && code.length != 6
              ? null
              : () async {
                  dynamic result;
                  final ok = await run(() async => result = await switch (widget.type) {
                        'resend' => api.resendInvitation(id),
                        'deactivate' => api.deactivateMember(id),
                        'reactivate' => api.reactivateMember(id, {'action_code': code}),
                        _ => api.removeMember(id),
                      });
                  if (ok && context.mounted) Navigator.pop(context, result ?? {});
                },
        ),
      ],
      children: [
        Text(text),
        if (meta.needsCode) ActionCodeField(purpose: 'team_change', onChanged: (value) => setState(() => code = value)),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
