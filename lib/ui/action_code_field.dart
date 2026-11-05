import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/admin_session.dart';
import 'format.dart';
import 'theme.dart';
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
    final p = Palette.of(context);
    // The website's Field + Input (`tracking-[0.3em] font-bold`) + secondary "Send code" button.
    return WebField(
      label: widget.label,
      hint: sentTo.isNotEmpty
          ? Text('Code sent to $sentTo.${devCode.isNotEmpty ? ' Development code: $devCode' : ''}', style: TextStyle(fontSize: 11, color: p.muted))
          : error.isNotEmpty
              ? Text(error, style: const TextStyle(fontSize: 11, color: AppColors.red600))
              : null,
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: TextStyle(fontSize: 14, letterSpacing: 4.2, fontWeight: FontWeight.w700, color: p.text),
            decoration: webInputDecoration(context, hint: '6-digit code').copyWith(hintStyle: TextStyle(fontSize: 14, letterSpacing: 4.2, fontWeight: FontWeight.w700, color: p.faint)),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: p.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : request,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smartphone, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Text(busy ? 'Sending…' : sentTo.isNotEmpty ? 'Resend' : 'Send code',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textSecondary)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
