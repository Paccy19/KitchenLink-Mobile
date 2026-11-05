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
    final p = Palette.of(context);
    return PageBody(onRefresh: query.load, children: [
      PageHeader(
        title: 'Team',
        description: 'Invite staff by email, give them a role, and the system sends the invitation to set their own password.',
        action: WebButton(
          label: 'Invite member',
          icon: Icons.person_add_alt,
          onPressed: () async {
            setState(() => inviteLink = '');
            after(await showAppSheet<dynamic>(context, _InviteSheet(roles: roles)), 'Invitation sent.');
          },
        ),
      ),
      if (inviteLink.isNotEmpty)
        SectionCard(
          title: 'Share this invitation link',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'The email could not be sent automatically. Send this link to the member yourself; it lets them set their password.',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
            const SizedBox(height: 8),
            // Read-only link with a Copy button.
            Row(children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: inviteLink),
                  readOnly: true,
                  style: TextStyle(fontSize: 12, color: p.text),
                  decoration: webInputDecoration(context),
                ),
              ),
              const SizedBox(width: 8),
              SmallButton('Copy', icon: Icons.copy, onPressed: () {
                Clipboard.setData(ClipboardData(text: inviteLink));
                showToast(context, 'Copied');
              }),
            ]),
          ]),
        ),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final members = jlist(data['members']);
            if (members.isEmpty) {
              return const EmptyState(icon: Icons.groups_outlined, title: 'No team members', description: 'Invite your first team member.');
            }
            return WebTable(
              columns: const [
                WebColumn('Member'),
                WebColumn('Role'),
                WebColumn('Status'),
                WebColumn('Sign-in'),
                WebColumn('Last login'),
                WebColumn('', alignEnd: true),
              ],
              rows: [for (final member in members) _memberRow(member)],
            );
          },
        ),
      ),
      ListenableBuilder(
        listenable: query,
        builder: (context, _) => SectionCard(
          title: 'Roles & permissions',
          description: 'What each role may do. The owner (super admin) can do everything.',
          action: SmallButton(showRoles ? 'Hide' : 'Show', ghost: true, onPressed: () => setState(() => showRoles = !showRoles)),
          child: showRoles ? _roleReference(query.data ?? const {}) : const SizedBox.shrink(),
        ),
      ),
    ]);
  }

  List<Widget> _memberRow(Json member) {
    final p = Palette.of(context);
    final status = jstr(member['status']);
    final isOwner = member['is_owner'] == true;
    Future<void> confirm(String type) async => after(await showAppSheet<dynamic>(context, _ConfirmSheet(type: type, member: member)), _confirmMeta[type]!.message);
    return [
      CellText(jstr(member['name'], '—'), sub: jstr(member['email'])),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(jstr(member['role_label']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
        if (isOwner) const ToneBadge('Owner', tone: Tone.violet),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ToneBadge(_statusLabel[status] ?? toTitle(status), tone: _statusTone[status] ?? Tone.slate),
        if (status == 'invited' && member['invite_expires_at'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Expires ${formatDate(member['invite_expires_at'], withTime: false)}', style: TextStyle(fontSize: 11, color: p.faint)),
          ),
      ]),
      member['two_factor_enabled'] == true
          ? const ToneBadge('SMS codes', tone: Tone.green, icon: Icons.verified_user_outlined)
          : Text(jstr(member['phone'], 'No phone yet'), style: TextStyle(fontSize: 11, color: p.faint)),
      Text(member['last_login_at'] != null ? formatDate(member['last_login_at']) : 'Never', style: TextStyle(fontSize: 12, color: p.muted)),
      isOwner
          ? Text('Owner account', style: TextStyle(fontSize: 11, color: p.faint))
          // `flex flex-wrap justify-end gap-1.5`, kept to two lines at most.
          : ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 172),
              child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
              if (status == 'deactivated')
                SmallButton('Reactivate', icon: Icons.how_to_reg_outlined, onPressed: () => confirm('reactivate'))
              else ...[
                SmallButton(
                  'Role',
                  icon: Icons.manage_accounts_outlined,
                  onPressed: () async => after(await showAppSheet<dynamic>(context, _RoleSheet(member: member, roles: roles)), 'Role updated.'),
                ),
                SmallButton('New link', icon: Icons.refresh, onPressed: () => confirm('resend')),
                SmallButton('Deactivate', icon: Icons.person_off_outlined, onPressed: () => confirm('deactivate')),
              ],
              SmallButton('', icon: Icons.delete_outline, ghost: true, onPressed: () => confirm('remove')),
              ]),
            ),
    ];
  }

  /// The roles, grouped by the same categories as the panel (owner reference):
  /// `grid lg:grid-cols-2 gap-4` of `rounded-xl border p-4` boxes.
  Widget _roleReference(Json data) {
    final p = Palette.of(context);
    final categories = jlist(data['categories']);
    final permissions = jlist(data['permissions']);
    return ResponsiveGrid(minWidth: 1, maxColumns: MediaQuery.sizeOf(context).width >= 1024 ? 2 : 1, spacing: 16, equalHeights: false, children: [
      for (final role in jlist(data['roles']))
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(jstr(role['label']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 2),
            Text(jstr(role['description']), style: TextStyle(fontSize: 11, height: 1.35, color: p.muted)),
            const SizedBox(height: 12),
            for (final category in categories)
              Builder(builder: (context) {
                final owned = ((role['permissions'] as List?) ?? const []).map((e) => e.toString()).toSet();
                final allowed = permissions.where((perm) => perm['category'] == category['id'] && owned.contains(jstr(perm['id']))).toList();
                if (allowed.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(jstr(category['label']).toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: p.faint)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, runSpacing: 4, children: [for (final perm in allowed) ToneBadge(jstr(perm['label']))]),
                  ]),
                );
              }),
          ]),
        ),
    ]);
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
