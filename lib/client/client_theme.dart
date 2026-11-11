import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// The marketplace's warm brown palette (the website's customer pages):
/// Tailwind stone / gray plus the brand browns used in its class names.
///
/// In dark mode ([K.dark]) every colour is swapped the way the website's
/// `.dark .app-theme` rules in index.css swap them: light surfaces become
/// chocolate, grey and brown text becomes cream and caramel, and pale tints
/// become translucent ones. The `fill*` colours never change (the brown
/// buttons, gradients and the footer stay brown in both modes).
class K {
  /// Set by [MarketTheme]; read while building, so a change rebuilds the app.
  static bool dark = false;

  static Color _pick(Color light, Color darkColor) => dark ? darkColor : light;

  /// Builds with the light palette: for parts that sit on a fill that is dark
  /// in both modes (the footer, the brown code card, the top banner, icons on
  /// brown buttons), whose pale text must stay pale.
  static T light<T>(T Function() build) {
    final was = dark;
    dark = false;
    try {
      return build();
    } finally {
      dark = was;
    }
  }

  /// `bg-white/95` header bar (`bg-header` at 95% on dark).
  static Color get header => _pick(const Color(0xF2FFFFFF), const Color(0xF22B1A12));

  /// `bg-white/95` chips on top of photos (rating), dark on dark.
  static Color get photoChip => _pick(const Color(0xF2FFFFFF), const Color(0xE62B1A12));

  // The website's chocolate dark palette.
  static const _bgMain = Color(0xFF1E1210); // page background
  static const _bgCard = Color(0xFF35201A); // cards, sheets, inputs
  static const _bgHeader = Color(0xFF2B1A12); // header / footer surfaces
  static const _bgSubtle = Color(0xFF4A2F26); // chips, icon tiles
  static const _border = Color(0xFF4A352F);
  static const _textPrimary = Color(0xFFFFFBF5);
  static const _textSecondary = Color(0xFFD7C4B5);
  static const _textMuted = Color(0xFF9C8A7E);
  static const _textAccent = Color(0xFFD9BDA6);

  // Brand browns that are always fills (buttons, gradients, footer).
  static const brown950 = Color(0xFF1C0A03);
  static const brown900 = Color(0xFF2B1206);
  static const brown800 = Color(0xFF481F0D);
  static const footer = Color(0xFF190A03);
  static const fillBrown850 = Color(0xFF3D1B0C);
  static const fillBrown700 = Color(0xFF542813);
  static const fillBrown600 = Color(0xFF6D391D);

  // Brand browns used as text, icons and borders: caramel on dark.
  static Color get brown850 => _pick(fillBrown850, _textAccent);
  static Color get brown750 => _pick(const Color(0xFF4E2410), _textAccent);
  static Color get brown700 => _pick(fillBrown700, _textAccent);
  static Color get brown600 => _pick(fillBrown600, _textAccent);
  static Color get brown500 => _pick(const Color(0xFF8A5332), _textAccent);
  static Color get brown300 => _pick(const Color(0xFFD9BDA6), _textSecondary);
  // Pale brown tints (chip backgrounds, borders).
  static Color get brown200 => _pick(const Color(0xFFEBD7C5), _border);
  static Color get brown100 => _pick(const Color(0xFFF5EBE1), _bgSubtle);
  static Color get brown50 => _pick(const Color(0xFFFAF6F2), _bgSubtle);

  // Tailwind stone / gray.
  static Color get stone50 => _pick(const Color(0xFFFAFAF9), _bgMain);
  static Color get stone100 => _pick(const Color(0xFFF5F5F4), _bgHeader);
  static Color get stone200 => _pick(const Color(0xFFE7E5E4), _border);
  static Color get stone300 => _pick(const Color(0xFFD6D3D1), _textMuted);
  static Color get stone400 => _pick(const Color(0xFFA8A29E), _textMuted);
  static Color get stone500 => _pick(const Color(0xFF78716C), _textMuted);
  static Color get stone600 => _pick(const Color(0xFF57534E), _textSecondary);
  static Color get stone700 => _pick(const Color(0xFF44403C), _textSecondary);
  static Color get stone800 => _pick(const Color(0xFF292524), _textPrimary);
  static Color get stone900 => _pick(const Color(0xFF1C1917), _textPrimary);
  static Color get gray200 => _pick(const Color(0xFFE5E7EB), _border);
  static Color get gray400 => _pick(const Color(0xFF9CA3AF), _textMuted);
  static Color get gray900 => _pick(const Color(0xFF111827), _textPrimary);

  /// Pills that stay dark with white text in both modes ("Closed now", "Sold out").
  static const fillStone700 = Color(0xFF44403C);
  static const fillStone800 = Color(0xFF292524);

  // Accents: solid fills stay, pale tints and dark status text are swapped.
  static const forest600 = Color(0xFF16A34A);
  static Color get forest100 => _pick(const Color(0xFFDCFCE7), const Color(0x2910B981));
  static Color get forest700 => _pick(const Color(0xFF15803D), const Color(0xFF6EE7B7));
  static const amber400 = Color(0xFFFBBF24);
  static Color get amber200 => _pick(const Color(0xFFFDE68A), const Color(0x2EF59E0B));
  static Color get amber800 => _pick(const Color(0xFF92400E), const Color(0xFFFCD34D));
  static const violet700 = Color(0xFF6D28D9);
  static Color get rose600 => _pick(const Color(0xFFE11D48), const Color(0xFFFDA4AF));
  static Color get red50 => _pick(const Color(0xFFFEF2F2), const Color(0x29EF4444));
  static Color get red100 => _pick(const Color(0xFFFEE2E2), const Color(0x3DEF4444));
  static const red500 = Color(0xFFEF4444);

  /// `bg-gray-50/50` on white.
  static Color get page => _pick(const Color(0xFFFCFCFD), _bgMain);

  /// `bg-white`: cards, sheets, inputs and bars.
  static Color get surface => _pick(Colors.white, _bgCard);

  /// `bg-[#faf7f4]` and the other near-white brand tints.
  static Color get warm => _pick(const Color(0xFFFAF7F4), _bgSubtle);

  /// A light status colour written out in a screen (chip and notice
  /// backgrounds, borders and their dark text) in the current mode: the
  /// website's translucent tints and light status text on dark.
  static Color tone(Color light) => dark ? (_tones[light.toARGB32()] ?? light) : light;

  static const _tones = <int, Color>{
    // Backgrounds.
    0xFFFAF7F4: _bgMain,
    0xFFF5F6E9: _bgSubtle,
    0xFFEEF0DC: _bgSubtle,
    0xFFD1FAE5: Color(0x3D10B981),
    0xFFECFDF5: Color(0x2910B981),
    0xFFFFF1F2: Color(0x29F43F5E),
    0xFFF0F9FF: Color(0x290EA5E9),
    0xFFFFFBEB: Color(0x2EF59E0B),
    0xFFFEF2F2: Color(0x29EF4444),
    0xFFEDE9FE: Color(0x298B5CF6),
    // Borders.
    0xFFD9DCC0: _border,
    0xFFF3F4F6: _border,
    0xFFFECACA: Color(0x59EF4444),
    0xFFFDE68A: Color(0x59F59E0B),
    0xFFA7F3D0: Color(0x5910B981),
    0xFFBAE6FD: Color(0x590EA5E9),
    // Text.
    0xFF065F46: Color(0xFF6EE7B7),
    0xFF047857: Color(0xFF6EE7B7),
    0xFF059669: Color(0xFF6EE7B7),
    0xFF991B1B: Color(0xFFFCA5A5),
    0xFFB91C1C: Color(0xFFFCA5A5),
    0xFFDC2626: Color(0xFFFCA5A5),
    0xFFBE123C: Color(0xFFFDA4AF),
    0xFF0369A1: Color(0xFF7DD3FC),
    0xFFB45309: Color(0xFFFCD34D),
    0xFF92400E: Color(0xFFFCD34D),
    0xFF1F2937: _textPrimary,
    0xFF6B7280: _textMuted,
    0xFF2B3317: _textPrimary,
  };

  /// `bg-gradient-to-r from-[#2b1206] via-[#481f0d] to-[#200d05]` (buttons, active chips).
  static const buttonGradient = LinearGradient(colors: [brown900, brown800, Color(0xFF200D05)]);

  /// `bg-gradient-to-br from-[#2b1206] via-[#481f0d] to-[#1c0a03]` (logo tile, primer header).
  static const logoGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [brown900, brown800, brown950]);

  /// The navbar's top banner: `from-[#1c0a03] via-[#3a1a0c] to-[#1c0a03]`.
  static const bannerGradient = LinearGradient(colors: [brown950, Color(0xFF3A1A0C), brown950]);

  static const shadowSm = [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))];
  static const shadowMd = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];

  /// `shadow-md shadow-[#2b1206]/20` under the brown buttons.
  static const brownShadow = [BoxShadow(color: Color(0x332B1206), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1)];
}

/// Plus Jakarta Sans text, as the website (`font-black` = 900 is drawn with
/// the bundled 800 weight). The colour defaults to the main text colour.
TextStyle kText(double size, {FontWeight weight = FontWeight.w500, Color? color, double? height, double? spacing}) =>
    TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, fontWeight: weight, color: color ?? K.gray900, height: height, letterSpacing: spacing);

const w900 = FontWeight.w800;

ThemeData buildClientTheme({bool dark = false}) {
  final base = buildTheme(dark ? Brightness.dark : Brightness.light);
  final theme = dark ? _chocolate(base) : base;
  return theme.copyWith(
    scaffoldBackgroundColor: K.page,
    colorScheme: base.colorScheme.copyWith(
      primary: dark ? K.brown700 : K.fillBrown700,
      onPrimary: dark ? K.brown950 : Colors.white,
      surface: K.surface,
      onSurface: K.gray900,
    ),
    canvasColor: K.surface,
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: K.surface),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: K.surface, modalBackgroundColor: K.surface),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: K.brown700),
    textSelectionTheme: TextSelectionThemeData(cursorColor: K.brown700),
  );
}

/// The shared dark theme is the admin's slate one; the marketplace's dark
/// mode is the website's chocolate one, so every Material default (bars,
/// inputs, buttons, dividers, menus) is re-coloured from [K].
ThemeData _chocolate(ThemeData base) {
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: K.stone200));
  final input = base.inputDecorationTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: K.gray900, displayColor: K.gray900),
    iconTheme: base.iconTheme.copyWith(color: K.stone600),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: K.header,
      foregroundColor: K.gray900,
      shape: Border(bottom: BorderSide(color: K.stone200)),
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(color: K.gray900),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: K.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: K.stone200)),
    ),
    inputDecorationTheme: input.copyWith(
      fillColor: K.surface,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: K.brown700, width: 1.5)),
      labelStyle: input.labelStyle?.copyWith(color: K.stone500),
      hintStyle: input.hintStyle?.copyWith(color: K.stone400),
      helperStyle: input.helperStyle?.copyWith(color: K.stone400),
    ),
    // The website's dark primary button: white with dark text.
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(K.gray900),
        foregroundColor: const WidgetStatePropertyAll(K.brown950),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(K.surface),
        foregroundColor: WidgetStatePropertyAll(K.stone600),
        side: WidgetStatePropertyAll(BorderSide(color: K.stone200)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(foregroundColor: WidgetStatePropertyAll(K.brown700)),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: K.stone200),
    drawerTheme: base.drawerTheme.copyWith(backgroundColor: K.header),
    popupMenuTheme: base.popupMenuTheme.copyWith(color: K.surface),
    listTileTheme: base.listTileTheme.copyWith(iconColor: K.stone600, textColor: K.gray900),
    chipTheme: base.chipTheme.copyWith(backgroundColor: K.surface, side: BorderSide(color: K.stone200)),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: K.gray900,
      contentTextStyle: kText(13, color: K.brown950),
      actionTextColor: K.fillBrown700,
    ),
  );
}

/// Light or dark marketplace, like the website's ThemeContext (same
/// `ofk-theme` key). Until the customer picks one it follows the phone.
class MarketTheme extends ChangeNotifier with WidgetsBindingObserver {
  MarketTheme() {
    WidgetsBinding.instance.addObserver(this);
    _apply(_systemDark);
  }

  static const storageKey = 'ofk-theme';

  /// 'light' / 'dark' once chosen, else null (follow the phone).
  String? choice;

  bool get isDark => K.dark;

  static bool get _systemDark => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  /// Loads the saved choice with [read] (secure storage in the app).
  Future<void> restore(Future<String?> Function(String key) read) async {
    try {
      final saved = await read(storageKey);
      if (saved == 'dark' || saved == 'light') {
        choice = saved;
        _apply(saved == 'dark');
      }
    } catch (_) {}
  }

  /// The header's moon / sun button.
  void toggle(Future<void> Function(String key, String value) write) {
    choice = isDark ? 'light' : 'dark';
    _apply(choice == 'dark');
    write(storageKey, choice!).catchError((_) {});
  }

  @override
  void didChangePlatformBrightness() {
    if (choice == null) _apply(_systemDark);
  }

  void _apply(bool value) {
    if (K.dark == value) return;
    K.dark = value;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leave the shared palette light for whatever is built next.
    K.dark = false;
    super.dispose();
  }
}
