import 'package:flutter/material.dart';

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
  static const brandGradient = LinearGradient(colors: [Color(0xFF1C1917), Color(0xFF292524)]);

  /// Logo tiles: the same colours, top-left to bottom-right.
  static const brandDiagonal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2410C), Color(0xFF9A3412)],
  );

  /// The admin `Button` primary: `from-[#2b1206] via-[#481f0d] to-[#200d05]`.
  static const buttonGradient = LinearGradient(colors: [Color(0xFF2B1206), Color(0xFF481F0D), Color(0xFF200D05)]);

  // ---- The admin console (operations look): warm off-white page, flat white
  // cards, near-black primary buttons, burnt orange for the brand and urgent
  // actions, and a dark side menu.

  /// Primary buttons and the active filter chip ("Export report").
  static const ink = Color(0xFF1C1917);

  /// Brand tile, urgent actions ("Send surge bonus"), active tab on a phone.
  static const orange = Color(0xFFC2410C);

  /// The dark side menu and its active item.
  static const sidebar = Color(0xFF1C1B19);
  static const sidebarActive = Color(0xFF2E2C29);
  static const sidebarText = Color(0xFFE7E5E4);
  static const sidebarMuted = Color(0xFF8F8A84);

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

  static const light = Palette(
    page: Color(0xFFF5F6F8),
    card: Colors.white,
    header: Colors.white,
    stone50: Color(0xFFFAFAF9),
    stone100: Color(0xFFF5F5F4),
    stone200: Color(0xFFE7E5E4),
    border: Color(0xFFE7E5E4),
    divider: Color(0xFFF5F5F4),
    text: Color(0xFF111827),
    textSecondary: Color(0xFF57534E),
    muted: Color(0xFF78716C),
    faint: Color(0xFFA8A29E),
    accent: Color(0xFF1F2937),
  );

  static const dark = Palette(
    page: Color(0xFF0F1218),
    card: Color(0xFF1A1F29),
    header: Color(0xFF151A22),
    stone50: Color(0xFF0F1218),
    stone100: Color(0xFF151A22),
    stone200: Color(0xFF2A313D),
    border: Color(0xFF333B49),
    divider: Color(0xFF333B49),
    text: Color(0xFFF5F7FA),
    textSecondary: Color(0xFFC3CAD6),
    muted: Color(0xFF8A93A3),
    faint: Color(0xFF8A93A3),
    accent: Color(0xFFB4C1D6),
  );

  /// The admin console: warm stone page, flat white cards, soft borders.
  static const adminLight = Palette(
    page: Color(0xFFF6F5F2),
    card: Colors.white,
    header: Color(0xFFF6F5F2),
    stone50: Color(0xFFF6F5F2),
    stone100: Color(0xFFEFEDE9),
    stone200: Color(0xFFE7E5E1),
    border: Color(0xFFE7E5E1),
    divider: Color(0xFFEFEDE9),
    text: Color(0xFF1C1917),
    textSecondary: Color(0xFF57534E),
    muted: Color(0xFF78716C),
    faint: Color(0xFFA8A29E),
    accent: Color(0xFFC2410C),
  );

  /// The admin console in dark mode: warm charcoal instead of slate.
  static const adminDark = Palette(
    page: Color(0xFF141312),
    card: Color(0xFF1E1D1B),
    header: Color(0xFF141312),
    stone50: Color(0xFF191817),
    stone100: Color(0xFF262421),
    stone200: Color(0xFF34322E),
    border: Color(0xFF34322E),
    divider: Color(0xFF2B2926),
    text: Color(0xFFF5F5F4),
    textSecondary: Color(0xFFD6D3D1),
    muted: Color(0xFFA8A29E),
    faint: Color(0xFF8A847E),
    accent: Color(0xFFFB923C),
  );

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

/// The admin console's theme: the shared one with the operations palette,
/// near-black primary buttons and orange accents.
ThemeData buildAdminTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? Palette.adminDark : Palette.adminLight;
  final base = buildTheme(brightness);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border));
  const buttonText = TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 13, fontWeight: FontWeight.w700);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final primary = dark ? const Color(0xFFF5F5F4) : AppColors.ink;
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.page,
    canvasColor: p.card,
    colorScheme: base.colorScheme.copyWith(
      primary: primary,
      onPrimary: dark ? AppColors.ink : Colors.white,
      secondary: AppColors.orange,
      surface: p.card,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerHighest: p.stone100,
      outline: p.border,
    ),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.textSecondary),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: p.header,
      foregroundColor: p.text,
      shape: Border(bottom: BorderSide(color: p.border)),
      titleTextStyle: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 17, fontWeight: FontWeight.w800, color: p.text),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(borderSide: BorderSide(color: p.border.withValues(alpha: 0.6))),
      focusedBorder: border.copyWith(borderSide: BorderSide(color: primary, width: 1.5)),
      labelStyle: TextStyle(fontSize: 13, color: p.muted),
      hintStyle: TextStyle(fontSize: 14, color: p.faint),
      helperStyle: TextStyle(fontSize: 11, color: p.faint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: dark ? AppColors.ink : Colors.white,
        shape: buttonShape,
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        minimumSize: const Size(0, 40),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: p.card,
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
        shape: buttonShape,
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 40),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: buttonText, shape: buttonShape),
    ),
    dividerTheme: DividerThemeData(color: p.divider, space: 1, thickness: 1),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.sidebar, surfaceTintColor: Colors.transparent, width: 288),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.card,
      selectedColor: primary,
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.orange.withValues(alpha: dark ? 0.22 : 0.10),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? (dark ? const Color(0xFFFB923C) : AppColors.orange) : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(size: 24, color: states.contains(WidgetState.selected) ? (dark ? const Color(0xFFFB923C) : AppColors.orange) : p.muted),
      ),
    ),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.slate,
    brightness: brightness,
    primary: dark ? Colors.white : AppColors.slate,
    onPrimary: dark ? AppColors.slateDeep : Colors.white,
    surface: p.card,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerHighest: p.stone100,
    outline: p.border,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness, fontFamily: 'PlusJakartaSans');
  // Inputs: `px-3 py-2 text-sm rounded-xl border-stone-200`, brown focus.
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border));
  const buttonText = TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 12, fontWeight: FontWeight.w700);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.page,
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.header,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.8))),
      titleTextStyle: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 16, fontWeight: FontWeight.w800, color: p.text),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border.withValues(alpha: 0.8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(borderSide: BorderSide(color: p.border.withValues(alpha: 0.6))),
      focusedBorder: border.copyWith(borderSide: BorderSide(color: dark ? Colors.white70 : AppColors.brown, width: 1.5)),
      labelStyle: TextStyle(fontSize: 13, color: p.muted),
      hintStyle: TextStyle(fontSize: 14, color: p.faint),
      helperStyle: TextStyle(fontSize: 11, color: p.faint),
    ),
    // `Button` primary (solid stand-in for the brown gradient), secondary, ghost.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Colors.white : const Color(0xFF481F0D),
        foregroundColor: dark ? AppColors.slateDeep : Colors.white,
        shape: buttonShape,
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: const Size(0, 36),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: p.card,
        foregroundColor: p.textSecondary,
        side: BorderSide(color: p.border),
        shape: buttonShape,
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 36),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: buttonText, shape: buttonShape),
    ),
    dividerTheme: DividerThemeData(color: p.divider, space: 1, thickness: 1),
    drawerTheme: DrawerThemeData(backgroundColor: p.header, surfaceTintColor: Colors.transparent, width: 288),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
