import 'package:flutter/material.dart';

/// KitchenLink's design system: one warm palette (ivory and espresso by day,
/// roasted brown by night), one type scale, one set of radii and spacing.
/// Every role (marketplace, kitchen, delivery worker, admin) builds its theme
/// from these, so the four halves of the app look like one product.
///
/// Pure constants: no Provider or Riverpod, so any half may import it.
class KLColors {
  const KLColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.grouped,
    required this.fill,
    required this.line,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.espresso,
    required this.onEspresso,
    required this.star,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  final Brightness brightness;

  /// The page behind everything (warm ivory / roasted brown).
  final Color canvas;

  /// Cards, sheets and bars that sit on the canvas.
  final Color surface;

  /// A second, quieter surface: grouped rows, secondary panels.
  final Color grouped;

  /// Inputs, chips, icon wells and skeletons.
  final Color fill;

  /// Hairlines and borders, used sparingly.
  final Color line;

  /// Text: primary, secondary (descriptions) and tertiary (captions, hints).
  final Color ink;
  final Color inkSecondary;
  final Color inkTertiary;

  /// Buttons, links, selected states.
  final Color primary;
  final Color onPrimary;

  /// Caramel highlight (prices on dark, small emphasis) and its pale wash.
  final Color accent;
  final Color accentSoft;

  /// A deep espresso surface that stays dark in both modes (the hero card,
  /// the basket button), with the cream text on it.
  final Color espresso;
  final Color onEspresso;

  /// Rating stars.
  final Color star;

  // Status colours: text/icon colour and a pale background.
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  bool get isDark => brightness == Brightness.dark;

  static const light = KLColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF8F4EE),
    surface: Color(0xFFFFFFFF),
    grouped: Color(0xFFF2EBE2),
    fill: Color(0xFFEFE7DD),
    line: Color(0xFFE7DDD1),
    ink: Color(0xFF24170F),
    inkSecondary: Color(0xFF6B5A4E),
    inkTertiary: Color(0xFF9A897C),
    primary: Color(0xFF542813),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFB07A48),
    accentSoft: Color(0xFFF3E6D7),
    espresso: Color(0xFF2B1609),
    onEspresso: Color(0xFFFBF3EA),
    star: Color(0xFFE0A236),
    success: Color(0xFF2E7A4B),
    successSoft: Color(0xFFE4F2E8),
    warning: Color(0xFF9A5B0E),
    warningSoft: Color(0xFFFBEED8),
    danger: Color(0xFFB4342A),
    dangerSoft: Color(0xFFFBE8E5),
    info: Color(0xFF2D6290),
    infoSoft: Color(0xFFE5EFF8),
  );

  static const dark = KLColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF130E0B),
    surface: Color(0xFF1E1713),
    grouped: Color(0xFF251C17),
    fill: Color(0xFF2E241E),
    line: Color(0xFF3A2E26),
    ink: Color(0xFFF6EEE5),
    inkSecondary: Color(0xFFC9B7A7),
    inkTertiary: Color(0xFF8E7C6F),
    primary: Color(0xFFDDAE7E),
    onPrimary: Color(0xFF2B1206),
    accent: Color(0xFFDDAE7E),
    accentSoft: Color(0xFF3A2A1F),
    espresso: Color(0xFF2A1A11),
    onEspresso: Color(0xFFFBF3EA),
    star: Color(0xFFF0B54A),
    success: Color(0xFF7FD1A0),
    successSoft: Color(0xFF15291C),
    warning: Color(0xFFF2C46B),
    warningSoft: Color(0xFF33250D),
    danger: Color(0xFFFF9C90),
    dangerSoft: Color(0xFF3A1714),
    info: Color(0xFF8CC4F0),
    infoSoft: Color(0xFF12283A),
  );

  static KLColors of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// Font families. Plus Jakarta Sans (the website's) for everything people
/// read and tap; DM Serif Display only for large display titles.
class KLFont {
  static const sans = 'PlusJakartaSans';
  static const display = 'DMSerifDisplay';
}

/// The type scale. Tracking tightens as size grows and opens slightly on
/// small text; line height loosens as size shrinks.
class KLType {
  /// Hero and screen titles in the serif ("Good evening", "Your basket").
  static TextStyle display(double size, Color color) =>
      TextStyle(fontFamily: KLFont.display, fontSize: size, height: 1.08, letterSpacing: size >= 28 ? -0.6 : -0.3, color: color, fontWeight: FontWeight.w400);

  /// Large sans title (34): page headers in lists.
  static TextStyle largeTitle(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 30, height: 1.1, letterSpacing: -0.8, fontWeight: FontWeight.w800, color: color);

  /// Section headings ("Popular picks").
  static TextStyle title(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 20, height: 1.2, letterSpacing: -0.45, fontWeight: FontWeight.w800, color: color);

  /// Card and product names.
  static TextStyle headline(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 15, height: 1.25, letterSpacing: -0.2, fontWeight: FontWeight.w700, color: color);

  /// Descriptions and body copy.
  static TextStyle body(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 14, height: 1.45, letterSpacing: -0.05, fontWeight: FontWeight.w500, color: color);

  /// Supporting lines, captions.
  static TextStyle caption(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 12, height: 1.35, letterSpacing: 0, fontWeight: FontWeight.w500, color: color);

  /// Prices: tabular figures so columns of amounts line up.
  static TextStyle price(double size, Color color) => TextStyle(
        fontFamily: KLFont.sans,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small uppercase eyebrow over a title ("TOMORROW'S SPECIALS").
  static TextStyle eyebrow(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 11, height: 1.2, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: color);

  /// Button labels.
  static TextStyle button(Color color) => TextStyle(fontFamily: KLFont.sans, fontSize: 15, letterSpacing: -0.1, fontWeight: FontWeight.w700, color: color);
}

/// Spacing on a 4-point grid.
class KLSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const section = 32.0;

  /// Side margin of a phone screen.
  static const gutter = 20.0;
}

/// Corner radii. Nested shapes step down so their curves stay concentric.
class KLRadius {
  static const sm = 10.0; // small controls, image thumbnails
  static const md = 14.0; // buttons, inputs
  static const lg = 20.0; // cards
  static const xl = 28.0; // hero card, sheets
}

/// Soft, warm shadows: depth without outlines.
class KLShadow {
  static List<BoxShadow> card(KLColors c) => c.isDark
      ? const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))]
      : const [
          BoxShadow(color: Color(0x0A2B1206), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F2B1206), blurRadius: 20, offset: Offset(0, 8)),
        ];

  static List<BoxShadow> lifted(KLColors c) => c.isDark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))]
      : const [BoxShadow(color: Color(0x1F2B1206), blurRadius: 30, offset: Offset(0, 12))];
}
