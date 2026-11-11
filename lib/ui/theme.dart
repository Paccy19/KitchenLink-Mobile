import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The admin panel's dark slate brand (#111827 → #1f2937) with the
/// marketplace's brown accent (#542813).
class AppColors {
  static const slate = Color(0xFF1F2937);
  static const slateDeep = Color(0xFF111827);
  static const brown = Color(0xFF542813);
  static const brownDeep = Color(0xFF2B1206);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);

  /// Sidebar active item, sign-in button: `bg-gradient-to-r from-[#111827] via-[#1f2937] to-[#0b1220]`.
  static const brandGradient = LinearGradient(colors: [Color(0xFF2B1609), Color(0xFF3A1E0F)]);

  /// Logo tiles: the same colours, top-left to bottom-right.
  static const brandDiagonal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF542813), Color(0xFF2B1609)],
  );

  /// The admin `Button` primary: `from-[#2b1206] via-[#481f0d] to-[#200d05]`.
  static const buttonGradient = LinearGradient(colors: [Color(0xFF2B1206), Color(0xFF481F0D), Color(0xFF200D05)]);

  // ---- The admin console (operations look): warm off-white page, flat white
  // cards, near-black primary buttons, burnt orange for the brand and urgent
  // actions, and a dark side menu.

  /// Primary buttons and the active filter chip ("Export report").
  static const ink = Color(0xFF2B1609);

  /// Brand tile, urgent actions ("Send surge bonus"), active tab on a phone.
  static const orange = Color(0xFF9A5B2E);

  /// The dark side menu and its active item.
  static const sidebar = Color(0xFF1C130E);
  static const sidebarActive = Color(0xFF33251C);
  static const sidebarText = Color(0xFFF3E9DE);
  static const sidebarMuted = Color(0xFF9E8B7D);

  /// Tailwind `shadow-sm`.
  static const shadowSm = [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))];

  /// Tailwind `shadow-md`.
  static const shadowMd = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];
}

/// The website's surfaces and text colours: Tailwind stone/gray in light mode,
/// and the admin dark palette (`.dark .app-theme-admin` in index.css) in dark mode.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.page,
    required this.card,
    required this.header,
    required this.stone50,
    required this.stone100,
    required this.stone200,
    required this.border,
    required this.divider,
    required this.text,
    required this.textSecondary,
    required this.muted,
    required this.faint,
    required this.accent,
  });

  /// `bg-[#f5f6f8]` page background.
  final Color page;

  /// `bg-white` cards.
  final Color card;

  /// Header and side menu.
  final Color header;

  /// `bg-stone-50` (info tiles, metric boxes).
  final Color stone50;

  /// `bg-stone-100` (icon buttons, "signed in" box).
  final Color stone100;

  /// `bg-stone-200` (chips, secondary fills).
  final Color stone200;

  /// `border-stone-200` card and input borders.
  final Color border;

  /// `border-stone-100` dividers.
  final Color divider;

  /// `text-gray-900`.
  final Color text;

  /// `text-stone-600`.
  final Color textSecondary;

  /// `text-stone-500`.
  final Color muted;

  /// `text-stone-400`.
  final Color faint;

  /// `text-[#1f2937]` links ("View all", "Mark all read").
  final Color accent;

  // Every palette is the shared design tokens (lib/design/tokens.dart).
  static const light = Palette(
    page: Color(0xFFF8F4EE),
    card: Colors.white,
    header: Color(0xFFF8F4EE),
    stone50: Color(0xFFFBF8F4),
    stone100: Color(0xFFEFE7DD),
    stone200: Color(0xFFE7DDD1),
    border: Color(0xFFE7DDD1),
    divider: Color(0xFFEFE7DD),
    text: Color(0xFF24170F),
    textSecondary: Color(0xFF6B5A4E),
    muted: Color(0xFF85746A),
    faint: Color(0xFF9A897C),
    accent: Color(0xFF542813),
  );

  static const dark = Palette(
    page: Color(0xFF130E0B),
    card: Color(0xFF1E1713),
    header: Color(0xFF130E0B),
    stone50: Color(0xFF181210),
    stone100: Color(0xFF2E241E),
    stone200: Color(0xFF3A2E26),
    border: Color(0xFF3A2E26),
    divider: Color(0xFF2E241E),
    text: Color(0xFFF6EEE5),
    textSecondary: Color(0xFFC9B7A7),
    muted: Color(0xFF9E8B7D),
    faint: Color(0xFF8E7C6F),
    accent: Color(0xFFDDAE7E),
  );

  /// The admin console uses the same palettes as everyone else.
  static const adminLight = light;
  static const adminDark = dark;

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>() ?? light;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Badge / stat tones, as the website's TONE_CLASS.
enum Tone { slate, green, amber, red, blue, violet, orange }

// Tailwind 50 / 200 / 700 for each tone (badges: `bg-X-50 text-X-700 border-X-200`).
const _toneLight = {
  Tone.slate: (Color(0xFFF5F5F4), Color(0xFFE7E5E4), Color(0xFF44403C)),
  Tone.green: (Color(0xFFECFDF5), Color(0xFFA7F3D0), Color(0xFF047857)),
  Tone.amber: (Color(0xFFFFFBEB), Color(0xFFFDE68A), Color(0xFFB45309)),
  Tone.red: (Color(0xFFFEF2F2), Color(0xFFFECACA), Color(0xFFB91C1C)),
  Tone.blue: (Color(0xFFF0F9FF), Color(0xFFBAE6FD), Color(0xFF0369A1)),
  Tone.violet: (Color(0xFFF5F3FF), Color(0xFFDDD6FE), Color(0xFF6D28D9)),
  Tone.orange: (Color(0xFFFFF7ED), Color(0xFFFED7AA), Color(0xFFC2410C)),
};

extension ToneColors on Tone {
  Color get base => switch (this) {
        Tone.slate => const Color(0xFF78716C),
        Tone.green => const Color(0xFF059669),
        Tone.amber => const Color(0xFFD97706),
        Tone.red => const Color(0xFFDC2626),
        Tone.blue => const Color(0xFF0284C7),
        Tone.violet => const Color(0xFF7C3AED),
        Tone.orange => const Color(0xFFEA580C),
      };

  bool _dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  Color background(BuildContext context) => _dark(context) ? base.withValues(alpha: 0.18) : _toneLight[this]!.$1;

  Color foreground(BuildContext context) => _dark(context) ? Color.lerp(base, Colors.white, 0.45)! : _toneLight[this]!.$3;

  Color border(BuildContext context) => _dark(context) ? base.withValues(alpha: 0.35) : _toneLight[this]!.$2;
}

const _statusTones = {
  'pending': Tone.amber,
  'processing': Tone.blue,
  'in_review': Tone.blue,
  'open': Tone.amber,
  'approved': Tone.green,
  'active': Tone.green,
  'successful': Tone.green,
  'completed': Tone.green,
  'delivered': Tone.green,
  'resolved': Tone.green,
  'online': Tone.green,
  'rejected': Tone.red,
  'failed': Tone.red,
  'suspended': Tone.red,
  'cancelled': Tone.red,
  'offline': Tone.slate,
  'refunded': Tone.violet,
};

Tone statusTone(String? status) => _statusTones[status] ?? Tone.slate;

/// The admin console's theme: the shared design system, plus the admin's
/// [Palette] extension and its dark side menu.
ThemeData buildAdminTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.adminDark : Palette.adminLight;
  final base = klTheme(KLColors.of(brightness), extensions: [p]);
  return base.copyWith(
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.sidebar, surfaceTintColor: Colors.transparent, width: 288),
  );
}

/// The shared light/dark theme with the [Palette] extension (also the
/// marketplace's sign-in sheets and the root screens).
ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  return klTheme(KLColors.of(brightness), extensions: [p]);
}
