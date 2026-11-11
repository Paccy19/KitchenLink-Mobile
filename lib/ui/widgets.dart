import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'format.dart';
import 'theme.dart';

// Sizes and colours follow the website's admin ui.jsx (Tailwind classes noted).

// ---- Badges -----------------------------------------------------------------

/// `inline-flex px-2 py-0.5 rounded-full text-[11px] font-bold border`.
class ToneBadge extends StatelessWidget {
  const ToneBadge(this.text, {super.key, this.tone = Tone.slate, this.icon});

  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context);
    // A soft tinted pill, no outline ("Out for delivery", "Ready, no courier").
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) => ToneBadge(toTitle(status), tone: statusTone(status));
}

// ---- Layout -----------------------------------------------------------------

/// Tailwind's `sm:` breakpoint (640px and wider).
bool isSm(BuildContext context) => MediaQuery.sizeOf(context).width >= 640;

/// Title `text-xl font-black tracking-tight`, description `text-xs text-stone-500`.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.description, this.action});

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // `sm:text-2xl` / `sm:text-sm` from 640px.
    final sm = isSm(context);
    final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: TextStyle(fontSize: sm ? 30 : 26, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.text)),
      if (description != null) ...[
        const SizedBox(height: 4),
        Text(description!, style: TextStyle(fontSize: sm ? 15 : 13.5, height: 1.4, color: p.muted)),
      ],
    ]);
    if (action == null) return heading;
    // `flex flex-wrap justify-between gap-3`: the button sits on the right, and
    // drops below the title when they don't fit side by side.
    return LayoutBuilder(builder: (context, constraints) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 12,
        runSpacing: 12,
        children: [ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth), child: heading), action!],
      );
    });
  }
}

/// `bg-white rounded-2xl border border-stone-200/80 shadow-sm`; header row
/// `px-4 py-3 border-b border-stone-100` with a `text-sm font-black` title;
/// body `p-4`.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.description, this.action, required this.child, this.padding, this.actionFullWidth = false});

  final String? title;
  final String? description;
  final Widget? action;
  final Widget child;

  /// Body padding; `p-4 sm:p-5` when not given.
  final EdgeInsets? padding;

  /// Stretch the header [action] across the card (filters on a phone).
  final bool actionFullWidth;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sm = isSm(context);
    return _Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The title sits in the card with no rule under it ("Needs your attention").
        if (title != null || action != null)
          Padding(
            padding: EdgeInsets.fromLTRB(sm ? 24 : 18, sm ? 22 : 18, sm ? 24 : 18, 0),
            child: title == null && description == null
                // Only the action (filters): it sits on the right, or spans the card.
                ? Align(alignment: Alignment.centerRight, child: actionFullWidth ? SizedBox(width: double.infinity, child: action) : action)
                : Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        if (title != null) Text(title!, style: TextStyle(fontSize: sm ? 19 : 17, height: 1.3, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: p.text)),
                        if (description != null) ...[
                          const SizedBox(height: 2),
                          Text(description!, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.muted)),
                        ],
                      ]),
                      ?action,
                    ],
                  ),
          ),
        Padding(padding: padding ?? EdgeInsets.all(sm ? 24 : 18), child: child),
      ]),
    );
  }
}

/// The card surface shared by cards, stat tiles and lists.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;
  static const radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // Flat white with a soft border. A Material (not a coloured box) so list
    // tiles inside show their ink.
    return Material(
      color: p.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: p.border),
      ),
      child: child,
    );
  }
}

/// `bg-white rounded-2xl border p-4`: label `text-[11px] font-bold uppercase
/// tracking-wider text-stone-400`, `w-8 h-8 rounded-xl` icon tile, value
/// `mt-2 text-xl font-black`, hint `text-[11px] text-stone-500`.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.hint, this.icon, this.tone = Tone.slate});

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sm = isSm(context);
    // "Orders today / 1,328 / +9% vs last Wednesday": a plain label, a big
    // number and a coloured line under it.
    return _Surface(
      child: Padding(
        padding: EdgeInsets.all(sm ? 22 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              // Some labels are raw statuses ("processing"): start them with a capital.
              child: Text(label.isEmpty ? label : '${label[0].toUpperCase()}${label.substring(1)}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: sm ? 14 : 13, height: 1.35, fontWeight: FontWeight.w600, color: p.muted)),
            ),
            if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 18, color: p.faint)],
          ]),
          SizedBox(height: sm ? 10 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(fontSize: sm ? 32 : 26, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.text)),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: p.muted)),
          ],
        ]),
      ),
    );
  }
}

/// `grid grid-cols-2 gap-3` on a phone, more columns on wider screens.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 150, this.spacing = 12, this.maxColumns = 4, this.equalHeights = true});

  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final int maxColumns;

  /// Rows of equal height, like CSS grid. Turn off when a cell holds a grid itself.
  final bool equalHeights;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.maxWidth / minWidth).floor().clamp(1, maxColumns);
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      if (columns == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(children, spacing));
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += columns) {
        final row = children.sublist(i, (i + columns).clamp(0, children.length));
        final cells = Row(crossAxisAlignment: equalHeights ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) SizedBox(width: spacing),
            SizedBox(width: width, child: j < row.length ? row[j] : null),
          ],
        ]);
        rows.add(equalHeights ? IntrinsicHeight(child: cells) : cells);
      }
      return Column(children: spaced(rows, spacing));
    });
  }
}

/// `rounded-xl bg-stone-50 px-3 py-2`: label `text-[10px] font-bold uppercase
/// tracking-wider text-stone-400`, value `text-sm font-bold mt-0.5`.
class InfoTile extends StatelessWidget {
  const InfoTile(this.label, this.value, {super.key, this.child});

  final String label;
  final String value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // "Owner / Claudine M.": a soft stone box, small label, bold value.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: p.stone50, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label.isNotEmpty) ...[
          Text(label, style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: p.muted)),
          const SizedBox(height: 2),
        ],
        child ?? Text(value, style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }
}

/// `text-xs font-black uppercase tracking-wider text-stone-400 mb-2`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Palette.of(context).faint)),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Muted helper text (`text-[11px] text-stone-500`).
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 11.5, height: 1.45, color: color ?? Palette.of(context).muted));
}

// ---- States -----------------------------------------------------------------

/// `flex justify-center gap-2 py-12 text-sm font-bold text-stone-500` with a spinner.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.faint)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
      ]),
    );
  }
}

/// A coloured note box (`rounded-xl bg-X-50 border border-X-200 px-3 py-2 text-xs text-X-700`).
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.tone = Tone.red, this.icon, this.action, this.bold = true});

  final String text;
  final Tone tone;
  final IconData? icon;
  final Widget? action;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.background(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.border(context)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: fg)), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: fg, fontWeight: bold ? FontWeight.w600 : FontWeight.w400))),
        ?action,
      ]),
    );
  }
}

/// The website's ErrorNote: red box with an alert icon.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  static String messageOf(Object? error) {
    if (error == null) return '';
    if (error is ApiException) return error.message;
    if (error is String) return error;
    return 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    final message = messageOf(error);
    if (message.isEmpty) return const SizedBox.shrink();
    return Note(
      message,
      icon: Icons.error_outline,
      bold: false,
      action: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

/// `py-12 text-center`: `w-12 h-12 rounded-2xl bg-stone-100` icon tile,
/// title `text-sm font-bold`, description `text-xs text-stone-500`.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.description, this.action});

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: p.stone100, borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, size: 24, color: p.faint),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        if (description != null) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(description!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// "1–20 of 57" with `secondary sm` previous / next buttons and "1 / 3".
class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.limit, required this.total, required this.onPage});

  final int page;
  final int limit;
  final int total;
  final ValueChanged<int> onPage;

  factory Pager.of(Json data, {required ValueChanged<int> onPage, int defaultLimit = 20}) => Pager(
        page: jint(data['page'], 1),
        limit: jint(data['limit'], defaultLimit),
        total: jint(data['total']),
        onPage: onPage,
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pageCount = (total / (limit == 0 ? 1 : limit)).ceil().clamp(1, 1 << 31);
    final from = total == 0 ? 0 : (page - 1) * limit + 1;
    final to = (page * limit).clamp(0, total);
    Widget arrow(IconData icon, bool enabled, int target) => Opacity(
          opacity: enabled ? 1 : 0.6,
          child: InkWell(
            onTap: enabled ? () => onPage(target) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: p.card, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 14, color: p.textSecondary),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Expanded(child: Text('$from–$to of $total', style: TextStyle(fontSize: 12, color: p.muted))),
        arrow(Icons.chevron_left, page > 1, page - 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$page / $pageCount', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: p.textSecondary)),
        ),
        arrow(Icons.chevron_right, page < pageCount, page + 1),
      ]),
    );
  }
}

// ---- Lists ------------------------------------------------------------------

/// One record in a list (a table row of the website, laid out for a phone).
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.trailing,
    this.lines = const [],
    this.onTap,
    this.actions = const [],
    this.highlight = false,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> badges;
  final String? trailing;
  final List<String> lines;
  final VoidCallback? onTap;
  final List<Widget> actions;
  final bool highlight;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: highlight ? Tone.red.background(context).withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.43, color: p.text)),
                if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: TextStyle(fontSize: 11, height: 1.45, color: p.faint)),
              ]),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Text(trailing!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text)),
            ],
          ]),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: badges),
          ],
          for (final line in lines.where((l) => l.isNotEmpty))
            Padding(padding: const EdgeInsets.only(top: 3), child: Text(line, style: TextStyle(fontSize: 12, color: p.muted))),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: actions),
          ],
        ]),
      ),
    );
  }
}

/// Records separated by dividers inside a card.
class RecordList extends StatelessWidget {
  const RecordList({super.key, required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
        if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: footer),
      ]),
    );
  }
}

// ---- Form controls ----------------------------------------------------------

/// A labelled dropdown whose options are value → label pairs.
class Dropdown<T> extends StatelessWidget {
  const Dropdown({super.key, required this.value, required this.options, required this.onChanged, this.label, this.enabled = true});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DropdownButtonFormField<T>(
      // Keyed on the value so a change from outside (e.g. a filter reset) shows.
      key: ValueKey(value),
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 14, color: p.text),
      dropdownColor: p.card,
      borderRadius: BorderRadius.circular(12),
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: enabled ? (next) => next == null ? null : onChanged(next) : null,
    );
  }
}

/// Search box that applies on submit (like the website's filter forms).
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.hint, required this.onSubmit, this.initial = '', this.live = false});

  final String hint;
  final ValueChanged<String> onSubmit;
  final String initial;

  /// Apply on every keystroke instead of on submit.
  final bool live;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: Icon(Icons.search, size: 16, color: p.faint),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
      ),
      onChanged: widget.live ? (value) => widget.onSubmit(value) : null,
      onSubmitted: (value) => widget.onSubmit(value.trim()),
    );
  }
}

/// Picks a day for date filters; shows "Any" when empty.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final DateTime? first;
  final DateTime? last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(value) ?? now,
          firstDate: first ?? DateTime(2020),
          lastDate: last ?? DateTime(now.year + 2),
        );
        if (picked != null) onChanged(isoDay(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value.isEmpty
              ? const Icon(Icons.calendar_today_outlined, size: 16)
              : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => onChanged('')),
        ),
        child: Text(value.isEmpty ? 'Any' : formatDate(value, withTime: false), style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// A primary button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.busyLabel, this.danger = false, this.icon});

  final String label;
  final String? busyLabel;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // `danger`: `bg-red-600 hover:bg-red-700 text-white`.
    final style = danger ? FilledButton.styleFrom(backgroundColor: AppColors.red600, foregroundColor: Colors.white) : null;
    final child = Text(busy ? (busyLabel ?? 'Saving…') : label);
    if (icon == null && !busy) return FilledButton(style: style, onPressed: onPressed, child: child);
    return FilledButton.icon(
      style: style,
      onPressed: busy ? null : onPressed,
      icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 16),
      label: child,
    );
  }
}

// ---- Website-style table and controls ----------------------------------------

/// One table column (`px-4 py-2.5` header cell).
class WebColumn {
  const WebColumn(this.label, {this.alignEnd = false, this.nowrap = false});

  final String label;
  final bool alignEnd;

  /// Keeps the content on one line (`whitespace-nowrap`); other columns
  /// wrap when room runs short.
  final bool nowrap;
}

/// A grouped table heading (`<td colSpan>`): takes no column width, and draws
/// at its natural width across the empty cells to its right.
class _SpanRow extends SingleChildRenderObjectWidget {
  const _SpanRow({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSpanRow();
}

class _RenderSpanRow extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    child!.layout(BoxConstraints(maxHeight: constraints.maxHeight), parentUsesSize: true);
    size = constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : child!.size.width, child!.size.height));
  }
}

/// As wide as [width], but never narrower than the child's minimum width.
class _AtLeastMinWidth extends SingleChildRenderObjectWidget {
  const _AtLeastMinWidth({required this.width, super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAtLeastMinWidth(width);

  @override
  void updateRenderObject(BuildContext context, _RenderAtLeastMinWidth renderObject) => renderObject.width = width;
}

class _RenderAtLeastMinWidth extends RenderProxyBox {
  _RenderAtLeastMinWidth(this._width);

  double _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  double _target() {
    final min = child?.getMinIntrinsicWidth(double.infinity) ?? 0;
    return min > _width ? min : _width;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _target();

  @override
  double computeMaxIntrinsicWidth(double height) => _target();

  @override
  void performLayout() {
    final width = _target();
    child!.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    size = constraints.constrain(child!.size);
  }
}

/// The website's Table: `text-[11px] font-black uppercase tracking-wider
/// text-stone-400` header with a bottom border, rows `px-4 py-3` divided by
/// `divide-stone-50`. Columns size to their content like an HTML table; the
/// table is at least 640px wide and scrolls sideways on a phone.
class WebTable extends StatelessWidget {
  const WebTable({super.key, required this.columns, required this.rows, this.highlightRows = const {}, this.groupRows = const {}});

  final List<WebColumn> columns;
  final List<List<Widget>> rows;

  /// Rows shown with the light red background (`bg-red-50/40`).
  final Set<int> highlightRows;

  /// A `bg-stone-50` heading row shown before the row with that index (grouped lists).
  final Map<int, Widget> groupRows;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget cell(WebColumn column, Widget child, EdgeInsets padding) => Padding(
          padding: padding,
          child: Align(
            alignment: column.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            widthFactor: 1,
            // IntrinsicWidth reports its one-line width as its minimum, so the
            // table never squeezes a nowrap column.
            child: column.nowrap ? IntrinsicWidth(child: child) : child,
          ),
        );
    return LayoutBuilder(builder: (context, constraints) {
      final minWidth = constraints.maxWidth < 640 ? 640.0 : constraints.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _AtLeastMinWidth(
          width: minWidth,
          // Columns start at their content width; extra room is shared out, and
          // when room runs short the wrappable ones shrink, like an HTML table.
          child: Builder(
            builder: (context) => Table(
              columnWidths: {
                for (var c = 0; c < columns.length; c++)
                  c: columns[c].nowrap ? const IntrinsicColumnWidth() : const IntrinsicColumnWidth(flex: 1),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
                  children: [
                    for (final column in columns)
                      cell(
                        column,
                        Text(column.label.toUpperCase(),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(fontSize: 11.5, height: 1.45, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: p.muted)),
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                  ],
                ),
                for (var i = 0; i < rows.length; i++) ...[
                  if (groupRows.containsKey(i))
                    TableRow(
                      decoration: BoxDecoration(color: p.stone50, border: i == 0 ? null : Border(top: BorderSide(color: p.stone50))),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: _SpanRow(child: groupRows[i]!),
                        ),
                        for (var c = 1; c < columns.length; c++) const SizedBox.shrink(),
                      ],
                    ),
                  TableRow(
                    decoration: BoxDecoration(
                      color: highlightRows.contains(i) ? Tone.red.background(context).withValues(alpha: 0.4) : null,
                      border: i == 0 ? null : Border(top: BorderSide(color: p.divider)),
                    ),
                    children: [
                      for (var c = 0; c < columns.length; c++) cell(columns[c], rows[i][c], const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Cell text helpers: `font-bold text-gray-900` main line and `text-[11px] text-stone-400` second line.
class CellText extends StatelessWidget {
  const CellText(this.text, {super.key, this.sub, this.bold = true, this.size = 14, this.color});

  final String text;
  final String? sub;
  final bool bold;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(text, style: TextStyle(fontSize: size, height: 1.43, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color ?? p.text)),
      if (sub != null && sub!.isNotEmpty) Text(sub!, style: TextStyle(fontSize: 11, height: 1.45, color: p.faint)),
    ]);
  }
}

/// The website's Field: a `text-xs font-bold text-stone-500 mb-1.5` label above
/// the control, and an optional `text-[11px] text-stone-400` hint below it.
class WebField extends StatelessWidget {
  const WebField({super.key, required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
        ),
      child,
      if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: DefaultTextStyle.merge(style: TextStyle(fontSize: 11, color: p.faint), child: hint!)),
    ]);
  }
}

/// A plain website Input (`px-3 py-2 text-sm rounded-xl border`), no floating label.
class WebInput extends StatelessWidget {
  const WebInput({
    super.key,
    this.controller,
    this.initialValue,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
    this.errorText,
    this.obscure = false,
    this.autofillHints,
    this.enabled = true,
  });

  /// `disabled`: greyed out and not editable.
  final bool enabled;

  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final String? errorText;
  final bool obscure;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      readOnly: readOnly,
      enabled: enabled,
      obscureText: obscure,
      autofillHints: autofillHints,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: webInputDecoration(context, hint: hint).copyWith(errorText: errorText, errorMaxLines: 2),
    );
  }
}

/// The website's primary `Button`: brown gradient, `px-4 py-2 text-xs font-bold rounded-xl shadow-sm`.
class WebButton extends StatelessWidget {
  const WebButton({super.key, required this.label, required this.onPressed, this.icon, this.small = false, this.large = false, this.danger = false});

  /// `variant="danger"`: `bg-red-600 text-white shadow-sm`.
  final bool danger;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// `size="sm"`: `px-2.5 py-1.5 text-[11px]`.
  final bool small;

  /// `size="lg"`: `px-5 py-2.5 text-sm`.
  final bool large;

  @override
  Widget build(BuildContext context) {
    // Solid near-black ("Export report"); white on dark mode; red when it destroys.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = danger ? AppColors.red600 : (dark ? const Color(0xFFF5F5F4) : AppColors.ink);
    final fg = danger || !dark ? Colors.white : AppColors.ink;
    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: small
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
                : large
                    ? const EdgeInsets.symmetric(horizontal: 22, vertical: 13)
                    : const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: small ? 14 : 16, color: fg), SizedBox(width: small ? 5 : 7)],
              Flexible(
                child: Text(label, style: TextStyle(fontSize: small ? 12 : large ? 15 : 13.5, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The website's `Button variant="secondary" size="sm"`.
class SmallButton extends StatelessWidget {
  const SmallButton(this.label, {super.key, required this.onPressed, this.primary = false, this.ghost = false, this.danger = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// `variant="ghost"`: no border or fill, `text-stone-600`.
  final bool ghost;

  /// Secondary with red text (`!text-red-600`), e.g. "Erase data".
  final bool danger;

  /// A 16px icon before the label (e.g. the eye on "Read").
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // White with a soft border ("Assign", "Open case", "View"); near-black when primary.
    final primaryFill = dark ? const Color(0xFFF5F5F4) : AppColors.ink;
    final color = primary ? (dark ? AppColors.ink : Colors.white) : danger ? AppColors.red600 : p.text;
    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: Material(
        color: primary ? primaryFill : ghost ? Colors.transparent : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: primary || ghost ? BorderSide.none : BorderSide(color: danger ? AppColors.red600.withValues(alpha: 0.35) : p.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 8 : 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) Icon(icon, size: label.isEmpty ? 15 : 16, color: color),
              if (icon != null && label.isNotEmpty) const SizedBox(width: 6),
              if (label.isNotEmpty)
                Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `w-full px-3 py-2 text-sm rounded-xl border border-stone-200 bg-white`
/// with a brown focus ring, no floating label (like the website's Input).
InputDecoration webInputDecoration(BuildContext context, {String? hint, Widget? prefix, Widget? suffix}) {
  final p = Palette.of(context);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: width));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: p.card,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 14, color: p.faint),
    contentPadding: EdgeInsets.fromLTRB(prefix == null ? 12 : 0, 10, 12, 10),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 36),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 36),
    enabledBorder: border(p.border),
    border: border(p.border),
    focusedBorder: border(Theme.of(context).brightness == Brightness.dark ? Colors.white70 : AppColors.ink, 1.5),
  );
}

/// The website's search Input with the magnifier inside; applies on submit.
class WebSearchInput extends StatefulWidget {
  const WebSearchInput({super.key, required this.hint, required this.onSubmit});

  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  State<WebSearchInput> createState() => _WebSearchInputState();
}

class _WebSearchInputState extends State<WebSearchInput> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: webInputDecoration(context, hint: widget.hint, prefix: Icon(Icons.search, size: 16, color: p.faint)),
      onSubmitted: (value) => widget.onSubmit(value.trim()),
    );
  }
}

/// The website's Select: an input-styled box showing the chosen option.
class WebSelect<T> extends StatelessWidget {
  const WebSelect({super.key, required this.value, required this.options, required this.onChanged, this.dense = false});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  /// The compact card-header size (`!py-1.5 text-xs`).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final decoration = webInputDecoration(context);
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down, size: dense ? 16 : 18, color: p.text),
      style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: dense ? 12 : 14, color: p.text),
      dropdownColor: p.card,
      borderRadius: BorderRadius.circular(12),
      decoration: dense ? decoration.copyWith(contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6)) : decoration,
      items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
      onChanged: (next) => next == null ? null : onChanged(next),
    );
  }
}

/// The website's `<Input type="date">`: shows `mm/dd/yyyy` until a day is picked.
class WebDateInput extends StatelessWidget {
  const WebDateInput({super.key, required this.value, required this.onChanged});

  /// `YYYY-MM-DD`, or empty.
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final date = DateTime.tryParse(value);
    final text = date == null
        ? 'mm/dd/yyyy'
        : '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: date ?? now, firstDate: DateTime(2020), lastDate: DateTime(now.year + 2));
        if (picked != null) onChanged(isoDay(picked));
      },
      onLongPress: value.isEmpty ? null : () => onChanged(''),
      child: InputDecorator(
        decoration: webInputDecoration(
          context,
          suffix: value.isEmpty
              ? Icon(Icons.calendar_today_outlined, size: 15, color: p.text)
              : InkWell(onTap: () => onChanged(''), child: Icon(Icons.close, size: 15, color: p.muted)),
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 14, color: date == null ? p.textSecondary : p.text)),
      ),
    );
  }
}

// ---- Sheets & dialogs -------------------------------------------------------

/// Opens a form as a bottom sheet that grows with its content (the website's Modal).
Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    ),
  );
}

/// Title (`text-sm font-black`), scrollable body (`p-5`) and a footer with
/// the buttons on the right (`bg-stone-50/60 border-t`), like the website's Modal.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.children, this.actions = const []});

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
          child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(children, 16)),
          ),
        ),
        if (actions.isNotEmpty)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: BoxDecoration(
                color: p.stone50.withValues(alpha: 0.6),
                border: Border(top: BorderSide(color: p.divider)),
              ),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ),
          ),
      ]),
    );
  }
}

/// Puts a gap between form rows.
List<Widget> spaced(List<Widget> children, [double gap = 12]) => [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ];

Future<bool> confirmDialog(BuildContext context, String message, {String confirm = 'OK', bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red600, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Busy flag + error message for a form's save action.
mixin BusyState<T extends StatefulWidget> on State<T> {
  bool busy = false;
  Object? actionError;

  Future<bool> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      await action();
      return true;
    } catch (err) {
      if (mounted) setState(() => actionError = err);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// The scrolling body every admin page uses (`p-4 pb-16`, blocks `space-y-5`),
/// with pull-to-refresh.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.gap = 20});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // `p-4 sm:p-6 pb-16`.
    final edge = isSm(context) ? 24.0 : 16.0;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(edge, edge, edge, 64),
      children: spaced(children, gap),
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}
