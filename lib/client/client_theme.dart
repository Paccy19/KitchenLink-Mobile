import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// The marketplace's warm brown palette (the website's customer pages):
/// Tailwind stone / gray plus the brand browns used in its class names.
class K {
  // Brand browns.
  static const brown950 = Color(0xFF1C0A03);
  static const brown900 = Color(0xFF2B1206);
  static const brown850 = Color(0xFF3D1B0C);
  static const brown800 = Color(0xFF481F0D);
  static const brown750 = Color(0xFF4E2410);
  static const brown700 = Color(0xFF542813);
  static const brown600 = Color(0xFF6D391D);
  static const brown500 = Color(0xFF8A5332);
  static const brown300 = Color(0xFFD9BDA6);
  static const brown200 = Color(0xFFEBD7C5);
  static const brown100 = Color(0xFFF5EBE1);
  static const brown50 = Color(0xFFFAF6F2);
  static const footer = Color(0xFF190A03);

  // Tailwind stone / gray.
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone300 = Color(0xFFD6D3D1);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone700 = Color(0xFF44403C);
  static const stone800 = Color(0xFF292524);
  static const stone900 = Color(0xFF1C1917);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray900 = Color(0xFF111827);

  // Accents.
  static const forest600 = Color(0xFF16A34A);
  static const forest100 = Color(0xFFDCFCE7);
  static const forest700 = Color(0xFF15803D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber200 = Color(0xFFFDE68A);
  static const amber800 = Color(0xFF92400E);
  static const violet700 = Color(0xFF6D28D9);
  static const rose600 = Color(0xFFE11D48);
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red500 = Color(0xFFEF4444);

  /// `bg-gray-50/50` on white.
  static const page = Color(0xFFFCFCFD);

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
/// the bundled 800 weight).
TextStyle kText(double size, {FontWeight weight = FontWeight.w500, Color color = K.gray900, double? height, double? spacing}) =>
    TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

const w900 = FontWeight.w800;

ThemeData buildClientTheme() {
  final base = buildTheme(Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: K.page,
    colorScheme: base.colorScheme.copyWith(primary: K.brown700, onPrimary: Colors.white),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: K.brown700),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: K.brown700),
  );
}
