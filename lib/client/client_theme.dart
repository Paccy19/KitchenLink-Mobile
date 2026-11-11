import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

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

  /// The shared design tokens for the current mode.
  static KLColors get c => dark ? KLColors.dark : KLColors.light;

  /// The frosted top bar (canvas at 86%).
  static Color get header => c.canvas.withValues(alpha: 0.86);

  /// Chips on top of photos (rating, "Sold out"): a frosted surface.
  static Color get photoChip => c.surface.withValues(alpha: dark ? 0.86 : 0.92);

  // The roasted-brown dark palette (from the design tokens).
  static const _bgMain = Color(0xFF130E0B); // page background
  static const _bgSubtle = Color(0xFF2E241E); // chips, icon tiles
  static const _border = Color(0xFF3A2E26);
  static const _textPrimary = Color(0xFFF6EEE5);
  static const _textSecondary = Color(0xFFC9B7A7);
  static const _textMuted = Color(0xFF8E7C6F);
  static const _textAccent = Color(0xFFDDAE7E);

  // Brand browns that are always fills (buttons, the hero card, footer).
  static const brown950 = Color(0xFF1C0A03);
  static const brown900 = Color(0xFF2B1206);
  static const brown800 = Color(0xFF3E1C0C);
  static const footer = Color(0xFF190A03);
  static const fillBrown850 = Color(0xFF3D1B0C);
  static const fillBrown700 = Color(0xFF542813);
  static const fillBrown600 = Color(0xFF6D391D);

  // Brand browns used as text, icons and borders: caramel on dark.
  static Color get brown850 => _pick(fillBrown850, _textAccent);
  static Color get brown750 => _pick(const Color(0xFF4E2410), _textAccent);
  static Color get brown700 => _pick(fillBrown700, _textAccent);
  static Color get brown600 => _pick(fillBrown600, _textAccent);
  static Color get brown500 => _pick(const Color(0xFF9A6A43), _textAccent);
  static Color get brown300 => _pick(const Color(0xFFD3B597), _textSecondary);
  // Pale latte tints (chip backgrounds, selected washes, borders).
  static Color get brown200 => _pick(const Color(0xFFE9D8C4), _border);
  static Color get brown100 => _pick(const Color(0xFFF3E6D7), const Color(0xFF3A2A1F));
  static Color get brown50 => _pick(const Color(0xFFF8EFE5), const Color(0xFF2B2019));

  // Neutrals, warmed: the names stay (every screen uses them), the values
  // are the design tokens.
  static Color get stone50 => _pick(const Color(0xFFFBF8F4), _bgMain);
  static Color get stone100 => _pick(const Color(0xFFEFE7DD), _bgSubtle);
  static Color get stone200 => _pick(const Color(0xFFE7DDD1), _border);
  static Color get stone300 => _pick(const Color(0xFFCFC2B5), _textMuted);
  static Color get stone400 => _pick(const Color(0xFF9A897C), _textMuted);
  static Color get stone500 => _pick(const Color(0xFF85746A), _textMuted);
  static Color get stone600 => _pick(const Color(0xFF6B5A4E), _textSecondary);
  static Color get stone700 => _pick(const Color(0xFF52433A), _textSecondary);
  static Color get stone800 => _pick(const Color(0xFF33251C), _textPrimary);
  static Color get stone900 => _pick(const Color(0xFF24170F), _textPrimary);
  static Color get gray200 => _pick(const Color(0xFFE7DDD1), _border);
  static Color get gray400 => _pick(const Color(0xFF9A897C), _textMuted);
  static Color get gray900 => _pick(const Color(0xFF24170F), _textPrimary);

  /// Pills that stay dark with white text in both modes ("Closed now", "Sold out").
  static const fillStone700 = Color(0xFF4A3B31);
  static const fillStone800 = Color(0xFF2E221A);

  // Accents: solid fills stay, pale tints and dark status text are swapped.
  static const forest600 = Color(0xFF2E7A4B);
  static Color get forest100 => _pick(const Color(0xFFE4F2E8), const Color(0xFF15291C));
  static Color get forest700 => _pick(const Color(0xFF256A3F), const Color(0xFF7FD1A0));
  static const amber400 = Color(0xFFE0A236);
  static Color get amber200 => _pick(const Color(0xFFFBEED8), const Color(0x2EF59E0B));
  static Color get amber800 => _pick(const Color(0xFF9A5B0E), const Color(0xFFF2C46B));
  static const violet700 = Color(0xFF6B4E8F);
  static Color get rose600 => _pick(const Color(0xFFC2413A), const Color(0xFFFF9C90));
  static Color get red50 => _pick(const Color(0xFFFBE8E5), const Color(0xFF3A1714));
  static Color get red100 => _pick(const Color(0xFFF6D3CE), const Color(0x3DEF4444));
  static const red500 = Color(0xFFC8402F);

  /// The page: warm ivory, roasted brown at night.
  static Color get page => c.canvas;

  /// Cards, sheets, inputs and bars.
  static Color get surface => c.surface;

  /// Selected / strong fills (active chip, "All", the map button): espresso
  /// by day, caramel at night so they still stand out, and the text on them.
  static Color get strong => dark ? const Color(0xFFDDAE7E) : const Color(0xFF2B1609);
  static Color get onStrong => dark ? brown950 : const Color(0xFFFBF3EA);

  /// The quieter grouped surface.
  static Color get warm => c.grouped;

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
  static const buttonGradient = LinearGradient(colors: [fillBrown700, Color(0xFF4A2311)]);

  /// `bg-gradient-to-br from-[#2b1206] via-[#481f0d] to-[#1c0a03]` (logo tile, primer header).
  static const logoGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A1B0B), brown900]);

  /// The navbar's top banner: `from-[#1c0a03] via-[#3a1a0c] to-[#1c0a03]`.
  static const bannerGradient = LinearGradient(colors: [brown950, Color(0xFF3A1A0C), brown950]);

  /// Soft warm shadows (the design tokens' card and lifted shadows).
  static const shadowSm = [BoxShadow(color: Color(0x0F2B1206), blurRadius: 14, offset: Offset(0, 4))];
  static const shadowMd = [BoxShadow(color: Color(0x1A2B1206), blurRadius: 22, offset: Offset(0, 8))];

  /// `shadow-md shadow-[#2b1206]/20` under the brown buttons.
  static const brownShadow = [BoxShadow(color: Color(0x332B1206), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -4)];
}

/// Plus Jakarta Sans text, as the website (`font-black` = 900 is drawn with
/// the bundled 800 weight). The colour defaults to the main text colour.
TextStyle kText(double size, {FontWeight weight = FontWeight.w500, Color? color, double? height, double? spacing}) =>
    TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, fontWeight: weight, color: color ?? K.gray900, height: height, letterSpacing: spacing);

const w900 = FontWeight.w800;

/// The serif display face, for large titles only (hero, screen titles).
TextStyle kDisplay(double size, {Color? color, double? height}) => KLType.display(size, color ?? K.gray900).copyWith(height: height);

ThemeData buildClientTheme({bool dark = false}) => klTheme(dark ? KLColors.dark : KLColors.light);

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
