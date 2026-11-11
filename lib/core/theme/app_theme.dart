import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../design/tokens.dart';

/// KitchenLink's warm food-business look: deep brown, cream and white.
class AppColors {
  const AppColors._();

  static const brown900 = Color(0xFF2B1206);
  static const brown800 = Color(0xFF481F0D);
  static const brand = Color(0xFF542813);
  static const accent = Color(0xFF8A5332);
  static const caramel = Color(0xFFE8B896);
  static const sand = Color(0xFFEBD7C5);
  static const cream = Color(0xFFFAF7F4);
  static const creamDeep = Color(0xFFF5EBE1);
}

/// The delivery worker's brand colours. They used to be the website's moss
/// green; the app now uses one espresso brand for every role, and green only
/// means "online" (the go-online switch).
class DriverColors {
  const DriverColors._();

  static const moss950 = Color(0xFF1C0A03);
  static const moss900 = Color(0xFF2B1609);
  static const brand = Color(0xFF542813);
  static const accent = Color(0xFF8A5332);
  static const leaf = Color(0xFFDDAE7E);
  static const sage = Color(0xFFEBD7C5);
  static const mist = Color(0xFFF8F4EE);
  static const mistDeep = Color(0xFFF3E6D7);

  /// "Online": the go-online switch and its card.
  static const online = Color(0xFF2E7A4B);
  static const onlineDeep = Color(0xFF1F5A35);
}

/// Meaning of a status colour, resolved against the current theme.
enum Tone { neutral, brand, info, success, warning, danger }

class ToneColors {
  const ToneColors(this.foreground, this.background);
  final Color foreground;
  final Color background;
}

ToneColors toneColors(BuildContext context, Tone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (tone) {
    case Tone.success:
      return dark
          ? const ToneColors(Color(0xFF7FD4A0), Color(0xFF16301F))
          : const ToneColors(Color(0xFF1E6B3F), Color(0xFFE3F4EA));
    case Tone.warning:
      return dark
          ? const ToneColors(Color(0xFFF2C46B), Color(0xFF38290B))
          : const ToneColors(Color(0xFF8A5A00), Color(0xFFFFF1D6));
    case Tone.danger:
      return dark
          ? const ToneColors(Color(0xFFFF9C94), Color(0xFF3B1714))
          : const ToneColors(Color(0xFFA32A20), Color(0xFFFDE8E6));
    case Tone.info:
      return dark
          ? const ToneColors(Color(0xFF8CC4F0), Color(0xFF12293A))
          : const ToneColors(Color(0xFF1B5E91), Color(0xFFE4F1FB));
    case Tone.brand:
      // The app's own brand colour (brown for kitchens, moss for delivery workers).
      final scheme = Theme.of(context).colorScheme;
      return ToneColors(scheme.primary, scheme.primaryContainer);
    case Tone.neutral:
      return dark
          ? const ToneColors(Color(0xFFCDBFB5), Color(0xFF2E221B))
          : const ToneColors(Color(0xFF5E524A), Color(0xFFEFE9E4));
  }
}

/// The kitchen and delivery worker themes: both are KitchenLink's shared
/// design system (`lib/design/`), so every role looks like one app. The
/// delivery worker keeps moss green only where it means "online".
class AppTheme {
  const AppTheme._();

  static const double radius = KLRadius.lg;

  static ThemeData light() => klTheme(KLColors.light);

  static ThemeData dark() => klTheme(KLColors.dark);

  /// The delivery worker screens (lib/driver).
  static ThemeData driverLight() => klTheme(KLColors.light);

  static ThemeData driverDark() => klTheme(KLColors.dark);
}
