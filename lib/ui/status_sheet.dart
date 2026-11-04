import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'theme.dart';
import 'widgets.dart';

const _reasonStatuses = ['rejected', 'suspended'];
const _labels = {
  'pending': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'suspended': 'Suspended',
  'active': 'Active',
};

/// Changes a vendor / delivery worker / customer status, with the reason the
/// audit log keeps (required to reject or suspend). Same as the website's StatusModal.
class StatusSheet extends StatefulWidget {
  const StatusSheet({
    super.key,
    required this.title,
    required this.statuses,
    required this.current,
    required this.onSubmit,
    this.approveBlocked = false,
  });

  final String title;
  final List<String> statuses;
  final String? current;
  final bool approveBlocked;

  /// Saves `{status, reason}`; the result is passed back when the sheet closes.
  final Future<dynamic> Function(Json payload) onSubmit;

  @override
  State<StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<StatusSheet> with BusyState {
  late String status = widget.statuses.contains(widget.current) ? widget.current! : widget.statuses.first;
  final reason = TextEditingController();
  String error = '';

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  bool get reasonRequired => _reasonStatuses.contains(status);
  bool get blocked => status == 'approved' && widget.approveBlocked;

  Future<void> submit() async {
    if (blocked) {
      setState(() => error = "Review this vendor's verification documents before approving.");
      return;
    }
    if (reasonRequired && reason.text.trim().length < 3) {
      setState(() => error = 'A short reason is required for this status.');
      return;
    }
    setState(() => error = '');
    dynamic result;
    final ok = await run(() async => result = await widget.onSubmit({'status': status, 'reason': reason.text.trim()}));
    if (ok && mounted) Navigator.pop(context, result ?? true);
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.title,
      actions: [
        OutlinedButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(label: 'Save', busy: busy, onPressed: blocked ? null : submit),
      ],
      children: [
        Dropdown<String>(
          label: 'New status',
          value: status,
          options: {for (final value in widget.statuses) value: _labels[value] ?? value},
          onChanged: (value) => setState(() => status = value),
        ),
        if (blocked)
          const Note('Open this vendor and mark the verification documents as reviewed before approving.', tone: Tone.amber),
        TextField(
          controller: reason,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: reasonRequired ? 'Reason (required)' : 'Reason (optional)',
            hintText: 'Add context for this change…',
            helperText: 'This note is stored on the audit log and may be shown to the affected user.',
            helperMaxLines: 2,
          ),
        ),
        if (error.isNotEmpty) Note(error),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
