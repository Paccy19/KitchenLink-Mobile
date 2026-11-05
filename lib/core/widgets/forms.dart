import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/validators.dart';
import 'feedback.dart';

/// A text field with the app's look. All the app's forms use this.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.enabled = true,
    this.prefix,
    this.suffix,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
    this.initialValue,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final bool obscure;
  final bool enabled;
  final Widget? prefix;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        enabled: enabled,
        validator: validator,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        maxLength: maxLength,
        maxLines: obscure ? 1 : maxLines,
        minLines: minLines,
        obscureText: obscure,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        autofocus: autofocus,
        readOnly: readOnly,
        onTap: onTap,
        autofillHints: autofillHints,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          counterText: '',
          prefixIcon: prefix,
          suffixIcon: suffix,
          alignLabelWithHint: maxLines > 1,
        ),
      );
}

/// A Rwandan phone field (07XXXXXXXX or +2507XXXXXXXX).
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.label = 'Phone number',
    this.enabled = true,
    this.onSubmitted,
    this.autofocus = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => AppTextField(
        label: label,
        hint: '07XXXXXXXX',
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        prefix: const Icon(Icons.phone_rounded),
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
          LengthLimitingTextInputFormatter(13),
        ],
        validator: validator ?? Validators.phone,
        onSubmitted: onSubmitted,
      );
}

/// A filled button that shows progress and ignores taps while it works, so a
/// request can never be sent twice by a double tap.
class AsyncButton extends StatefulWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.destructive = false,
    this.minimumSize,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool destructive;
  final Size? minimumSize;

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (error) {
      if (mounted) await reportFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null && !_busy;
    final spinnerColor = widget.outlined ? scheme.primary : (widget.destructive ? scheme.onError : scheme.onPrimary);
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (_busy)
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: spinnerColor))
      else if (widget.icon != null)
        Icon(widget.icon, size: 20),
      if (_busy || widget.icon != null) const SizedBox(width: 10),
      Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
    ]);
    if (widget.outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: widget.minimumSize,
          foregroundColor: widget.destructive ? scheme.error : null,
        ),
        onPressed: enabled ? _run : null,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: widget.minimumSize,
        backgroundColor: widget.destructive ? scheme.error : null,
        foregroundColor: widget.destructive ? scheme.onError : null,
      ),
      onPressed: enabled ? _run : null,
      child: child,
    );
  }
}

/// A labelled switch row.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
}

/// Pages that are a form: scrolls, keeps clear of the keyboard, and keeps
/// phones and tablets readable with a maximum width.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, this.padding = const EdgeInsets.all(16)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: padding,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: children,
          ),
        ),
      );
}

/// A small coloured note box: information, warning or success.
class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.message, this.tone = Tone.info, this.icon, this.title});

  final String message;
  final String? title;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, tone);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? Icons.info_outline_rounded, color: colors.foreground, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Text(title!, style: theme.textTheme.titleSmall?.copyWith(color: colors.foreground)),
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.foreground)),
          ]),
        ),
      ]),
    );
  }
}
