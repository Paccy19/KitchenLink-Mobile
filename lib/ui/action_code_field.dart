import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/admin_session.dart';
import 'format.dart';
import 'widgets.dart';

/// "Send code" + 6-digit input confirming one money/security action. The code
/// is bound to [purpose] on the server, so it cannot approve anything else.
/// [send] overrides how the code is requested (e.g. SMS-code setup).
class ActionCodeField extends StatefulWidget {
  const ActionCodeField({
    super.key,
    this.purpose,
    required this.onChanged,
    this.send,
    this.label = 'Code sent to your phone',
  });

  final String? purpose;
  final ValueChanged<String> onChanged;
  final Future<dynamic> Function()? send;
  final String label;

  @override
  State<ActionCodeField> createState() => _ActionCodeFieldState();
}

class _ActionCodeFieldState extends State<ActionCodeField> {
  final controller = TextEditingController();
  String sentTo = '';
  String devCode = '';
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> request() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final api = context.read<AdminSession>().api;
      final result = jmap(widget.send != null ? await widget.send!() : await api.sendActionCode(widget.purpose!));
      setState(() {
        sentTo = jstr(result['sent_to'], 'your phone');
        devCode = jstr(result['dev_otp']);
      });
    } on ApiException catch (err) {
      setState(() => error = err.message);
    } catch (err) {
      setState(() => error = err is String ? err : err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: widget.label, hintText: '6-digit code', counterText: ''),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: busy ? null : request,
            icon: const Icon(Icons.smartphone, size: 16),
            label: Text(busy ? 'Sending…' : sentTo.isNotEmpty ? 'Resend' : 'Send code'),
          ),
        ),
      ]),
      if (sentTo.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Hint('Code sent to $sentTo.${devCode.isNotEmpty ? ' Development code: $devCode' : ''}'),
        ),
      if (error.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Hint(error, color: const Color(0xFFDC2626))),
    ]);
  }
}
