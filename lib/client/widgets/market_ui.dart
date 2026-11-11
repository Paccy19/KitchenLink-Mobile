import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../client_theme.dart';
import '../market_models.dart';
import 'cards.dart';

/// A marketplace page below the homepage: a back bar with the title, then
/// the body on the warm page colour (the website's `max-w-* mx-auto px-4`).
class MarketPage extends StatelessWidget {
  const MarketPage({super.key, required this.title, required this.body, this.actions = const [], this.bottom, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: K.page,
        appBar: AppBar(
          backgroundColor: K.page,
          surfaceTintColor: Colors.transparent,
          foregroundColor: K.gray900,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: Column(
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(17, weight: FontWeight.w800, spacing: -0.3)),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(12, color: K.stone500)),
            ],
          ),
          actions: actions,
          bottom: PreferredSize(preferredSize: const Size.fromHeight(0.6), child: Container(height: 0.6, color: K.stone200)),
        ),
        body: body,
        bottomNavigationBar: bottom,
      );
}

/// `bg-white rounded-3xl border border-stone-200/80 shadow-sm` card.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: color ?? K.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: border ?? K.stone200.withValues(alpha: 0.6))),
        child: child,
      );
}

/// A numbered checkout step ("1  Delivery Destination").
class StepPanel extends StatelessWidget {
  const StepPanel({super.key, required this.step, required this.title, required this.child, this.action});

  final int step;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(gradient: K.buttonGradient, shape: BoxShape.circle),
                child: Text('$step', style: kText(12, weight: w900, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: kText(15, weight: w900))),
              ?action,
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

/// Uppercase grey label over a group (`text-xs font-bold uppercase tracking-wider`).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(), style: kText(11, weight: FontWeight.w700, color: K.stone600, spacing: 0.6)),
      );
}

InputDecoration marketInput(String hint, {Widget? prefix}) => InputDecoration(
      hintText: hint,
      hintStyle: kText(13, color: K.stone400),
      prefixIcon: prefix,
      isDense: true,
      filled: true,
      fillColor: K.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: K.stone200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: K.stone200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: K.brown700, width: 1.5)),
    );

/// A selectable option card (delivery / pickup, payment method, package…).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.selected, required this.onTap, required this.title, this.subtitle, this.icon});

  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? K.brown50 : K.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? K.brown700 : K.stone200, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: selected ? K.brown700 : K.stone500), const SizedBox(width: 10)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: kText(13, weight: w900, color: selected ? K.brown850 : K.gray900)),
                  if (subtitle != null) Text(subtitle!, style: kText(11, color: K.stone500)),
                ]),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: selected ? K.brown700 : K.stone300),
            ]),
          ),
        ),
      );
}

/// "Subtotal ........ 2,500 RWF".
class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.value, {super.key, this.strong = false, this.color});

  final String label;
  final String value;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: kText(strong ? 14 : 13, weight: strong ? w900 : FontWeight.w600, color: strong ? K.gray900 : K.stone600))),
          const SizedBox(width: 12),
          Text(value, style: kText(strong ? 16 : 13, weight: strong ? w900 : FontWeight.w700, color: color ?? (strong ? K.brown750 : K.gray900))),
        ]),
      );
}

/// A coloured notice box (errors, hints, warnings).
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = NoticeTone.error, this.icon});

  final String text;
  final NoticeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      NoticeTone.error => (K.tone(const Color(0xFFFEF2F2)), K.tone(const Color(0xFFB91C1C)), K.tone(const Color(0xFFFECACA))),
      NoticeTone.warning => (K.tone(const Color(0xFFFFFBEB)), K.tone(const Color(0xFF92400E)), K.tone(const Color(0xFFFDE68A))),
      NoticeTone.success => (K.tone(const Color(0xFFECFDF5)), K.tone(const Color(0xFF047857)), K.tone(const Color(0xFFA7F3D0))),
      NoticeTone.info => (K.tone(const Color(0xFFF0F9FF)), K.tone(const Color(0xFF0369A1)), K.tone(const Color(0xFFBAE6FD))),
      NoticeTone.brand => (K.brown50, K.brown850, K.brown200),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 8)],
        Expanded(child: Text(text, style: kText(12, weight: FontWeight.w600, color: fg, height: 1.4))),
      ]),
    );
  }
}

enum NoticeTone { error, warning, success, info, brand }

/// The outlined secondary button (`border border-stone-200 bg-white`).
class OutlineAction extends StatelessWidget {
  const OutlineAction({super.key, required this.label, required this.onTap, this.icon, this.color, this.dense = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15),
        label: Text(label, style: kText(dense ? 11.5 : 12.5, weight: FontWeight.w700, color: onTap == null ? K.stone400 : color ?? K.stone700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color ?? K.stone700,
          backgroundColor: K.surface,
          side: BorderSide(color: K.stone200),
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 8 : 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}

/// − 2 + quantity buttons.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.label = ''});

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final String label;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback? onTap) => Tooltip(
          message: tooltip,
          child: Material(
            color: K.surface,
            shape: CircleBorder(side: BorderSide(color: K.stone200)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 15, color: onTap == null ? K.stone300 : K.stone600)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.remove, 'One less $label', value > min ? () => onChanged(value - 1) : null),
      SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.center, style: kText(14, weight: w900))),
      button(Icons.add, 'One more $label', value < 99 ? () => onChanged(value + 1) : null),
    ]);
  }
}

void showMarketSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "+250788888888" → "0788 888 888".
String phoneDisplay(String phone) {
  final local = localPhone(phone);
  return local.length == 10 ? '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}' : phone;
}

/// "Call kitchen" / "Call delivery worker": the number in local form, a
/// one-tap call and a copy button (the website's CallKitchenButton).
Future<void> showCallSheet(BuildContext context, {required String phone, required String who}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 26, backgroundColor: K.brown50, child: Icon(Icons.phone, color: K.brown700)),
            const SizedBox(height: 10),
            Text('Call $who', textAlign: TextAlign.center, style: kText(15, weight: w900)),
            const SizedBox(height: 4),
            Text(phoneDisplay(phone), style: kText(22, weight: w900, color: K.brown750, spacing: 0.5)),
            const SizedBox(height: 4),
            Text('A normal local call — standard rates from your network apply.', textAlign: TextAlign.center, style: kText(11, color: K.stone500)),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Call now',
              icon: Icons.phone,
              onTap: () async {
                final ok = await launchUrl(Uri(scheme: 'tel', path: localPhone(phone)));
                if (!ok && sheet.mounted) showMarketSnack(sheet, 'Could not start the call. Dial ${phoneDisplay(phone)}.');
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlineAction(
                label: 'Copy number',
                icon: Icons.copy,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: localPhone(phone)));
                  showMarketSnack(sheet, 'Number copied');
                },
              ),
            ),
          ]),
        ),
      ),
    );

/// A pill showing a status in its colour.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: kText(11, weight: w900, color: foreground)),
      );
}

/// Sign-in prompt for pages that need an account (orders, messages, support).
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.icon, required this.title, required this.message, required this.onSignIn});

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        EmptyCard(icon: icon, title: title, message: message, actionLabel: 'Sign in', onAction: onSignIn),
      ]);
}
