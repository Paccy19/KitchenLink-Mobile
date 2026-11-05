import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/admin_session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Accepting a team invitation: paste the emailed link (`/admin-invite?token=…`)
/// or its token, choose a password, then sign in normally.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> with BusyState {
  final link = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  String token = '';
  Json? invitation;
  bool checking = false;
  String problem = '';
  String error = '';
  bool done = false;

  @override
  void dispose() {
    link.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  /// The token from a full invitation link, or the text itself.
  String _tokenFrom(String text) {
    final trimmed = text.trim();
    final uri = Uri.tryParse(trimmed);
    return uri?.queryParameters['token'] ?? trimmed;
  }

  Future<void> check() async {
    final next = _tokenFrom(link.text);
    if (next.isEmpty) {
      setState(() => problem = 'This link is missing its invitation token. Open the link exactly as it was emailed to you.');
      return;
    }
    setState(() {
      checking = true;
      problem = '';
      token = next;
    });
    try {
      final result = jmap(await context.read<AdminSession>().api.getInvitation(next));
      setState(() => invitation = jmap(result['invitation']));
    } catch (err) {
      final message = ErrorNote.messageOf(err);
      setState(() => problem = message.isEmpty ? 'This invitation link is not valid.' : message);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> accept() async {
    final value = password.text;
    if (value.length < 8 || !RegExp(r'[a-zA-Z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      setState(() => error = 'Use at least 8 characters with letters and numbers.');
      return;
    }
    if (value != confirm.text) {
      setState(() => error = 'Passwords do not match.');
      return;
    }
    setState(() => error = '');
    final ok = await run(() => context.read<AdminSession>().api.acceptInvitation(token, {'password': value}));
    if (ok && mounted) setState(() => done = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join the admin team')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(child: Padding(padding: const EdgeInsets.all(20), child: _body())),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (done) {
      return Column(children: spaced([
        const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 40),
        const Text("You're all set", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text('Your password is saved. Sign in with ${jstr(invitation?['email'])}.', textAlign: TextAlign.center),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go to admin sign in')),
      ]));
    }
    if (invitation == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
        const Text('Paste the invitation link from your email.'),
        TextField(
          controller: link,
          keyboardType: TextInputType.url,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Invitation link', hintText: 'https://…/admin-invite?token=…'),
        ),
        if (problem.isNotEmpty) ...[
          Note(problem, tone: Tone.amber, icon: Icons.warning_amber_rounded),
          const Hint('Ask the owner to send you a new invitation.'),
        ],
        BusyButton(label: 'Check invitation', busyLabel: 'Checking your invitation…', busy: checking, onPressed: check),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
      InfoTile('You were invited as', '', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(jstr(invitation!['role_label']), style: const TextStyle(fontWeight: FontWeight.w900)),
        Hint(jstr(invitation!['role_description'])),
        Hint('for ${jstr(invitation!['email'])}'),
      ])),
      TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Create new password', hintText: 'At least 8 characters, letters and numbers'),
      ),
      TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', hintText: 'Repeat your password')),
      if (error.isNotEmpty) Note(error),
      if (actionError != null) ErrorNote(error: actionError),
      BusyButton(label: 'Create my account', busyLabel: 'Finishing…', busy: busy, onPressed: accept),
    ]));
  }
}
