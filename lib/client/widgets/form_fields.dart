import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../client_theme.dart';

/// `text-xs font-bold text-stone-500 block mb-1.5`.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: kText(12, weight: FontWeight.w700, color: K.stone500),
    ),
  );
}

/// `text-[11px] text-red-500 font-semibold mt-1`.
class FieldError extends StatelessWidget {
  const FieldError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: kText(11, weight: FontWeight.w600, color: const Color(0xFFEF4444)),
    ),
  );
}

/// A formatter that runs [format] on every change (the website's
/// sanitize…Input helpers), keeping the cursor at the end when it changes text.
TextInputFormatter formatWith(String Function(String) format) => TextInputFormatter.withFunction((_, next) {
  final text = format(next.text);
  return text == next.text
      ? next
      : TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
});

/// The website's form input: `w-full text-sm p-3 rounded-xl border`, with an
/// optional stone-400 icon at the top-left (`pl-9`) and a red border on error.
class MarketInput extends StatelessWidget {
  const MarketInput({
    super.key,
    required this.controller,
    this.hint,
    this.icon,
    this.error = false,
    this.keyboard,
    this.maxLength,
    this.maxLines = 1,
    this.formatters = const [],
    this.onChanged,
    this.focusNode,
    this.readOnly = false,
    this.suffix,
    this.autofill,
    this.capitalization = TextCapitalization.none,
    this.onTap,
    this.focusColor = K.brown700,
  });

  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool error;
  final TextInputType? keyboard;
  final int? maxLength;
  final int maxLines;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool readOnly;
  final Widget? suffix;
  final Iterable<String>? autofill;
  final TextCapitalization capitalization;
  final VoidCallback? onTap;

  /// Border colour while typing (the website's `focus:border-…`).
  final Color focusColor;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : null,
      readOnly: readOnly,
      onTap: onTap,
      autofillHints: autofill,
      textCapitalization: capitalization,
      inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength), ...formatters],
      onChanged: onChanged,
      style: kText(14, color: readOnly ? K.stone600 : K.gray900, height: 1.43),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: kText(14, color: K.stone400, height: 1.43),
        isDense: true,
        filled: true,
        fillColor: readOnly ? K.stone50 : Colors.white,
        contentPadding: EdgeInsets.fromLTRB(icon == null ? 12 : 36, 12, 12, 12),
        enabledBorder: border(error ? const Color(0xFFFCA5A5) : K.stone200),
        focusedBorder: border(error ? const Color(0xFFF87171) : focusColor, 1.5),
        suffixIcon: suffix == null ? null : Padding(padding: const EdgeInsets.all(12), child: suffix),
        suffixIconConstraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      ),
    );
    if (icon == null) return field;
    return Stack(
      children: [
        field,
        Positioned(
          left: 12,
          top: 14,
          child: IgnorePointer(child: Icon(icon, size: 16, color: K.stone400)),
        ),
      ],
    );
  }
}
