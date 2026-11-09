import 'package:flutter/material.dart';

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

/// The delivery worker app's moss green, the same palette as the website's
/// delivery worker pages (`app-theme-driver`).
class DriverColors {
  const DriverColors._();

  static const moss950 = Color(0xFF12200B);
  static const moss900 = Color(0xFF1C2B12);
  static const brand = Color(0xFF3B5327);
  static const accent = Color(0xFF4A6A34);
  static const leaf = Color(0xFFB8D49A);
  static const sage = Color(0xFFD9E5D0);
  static const mist = Color(0xFFF5F8F2);
  static const mistDeep = Color(0xFFE8F0E0);
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

class AppTheme {
  const AppTheme._();

  static const double radius = 16;

  static ThemeData light() => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.brand,
          onPrimary: Colors.white,
          primaryContainer: AppColors.creamDeep,
          onPrimaryContainer: AppColors.brown900,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          secondaryContainer: AppColors.sand,
          onSecondaryContainer: AppColors.brown900,
          tertiary: Color(0xFF1E6B3F),
          onTertiary: Colors.white,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF23160F),
          onSurfaceVariant: Color(0xFF6D5E55),
          outline: Color(0xFFB9A89B),
          outlineVariant: AppColors.sand,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: AppColors.cream,
          surfaceContainer: Color(0xFFF7F1EC),
          surfaceContainerHigh: AppColors.creamDeep,
          surfaceContainerHighest: Color(0xFFEFE3D8),
          inverseSurface: AppColors.brown900,
          onInverseSurface: Colors.white,
        ),
        scaffold: AppColors.cream,
      );

  static ThemeData dark() => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.caramel,
          onPrimary: AppColors.brown900,
          primaryContainer: Color(0xFF3A2416),
          onPrimaryContainer: Color(0xFFF5EBE1),
          secondary: Color(0xFFD9A57F),
          onSecondary: AppColors.brown900,
          secondaryContainer: Color(0xFF4A2E1D),
          onSecondaryContainer: Color(0xFFF5EBE1),
          tertiary: Color(0xFF7FD4A0),
          onTertiary: Color(0xFF0B2A17),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          surface: Color(0xFF1F1510),
          onSurface: Color(0xFFF1E7DF),
          onSurfaceVariant: Color(0xFFC9B8AB),
          outline: Color(0xFF8C7769),
          outlineVariant: Color(0xFF4A3629),
          surfaceContainerLowest: Color(0xFF140C08),
          surfaceContainerLow: Color(0xFF191009),
          surfaceContainer: Color(0xFF241812),
          surfaceContainerHigh: Color(0xFF2E2019),
          surfaceContainerHighest: Color(0xFF3A2A21),
          inverseSurface: Color(0xFFF1E7DF),
          onInverseSurface: AppColors.brown900,
        ),
        scaffold: const Color(0xFF150D08),
      );

  /// The delivery worker app (lib/main_driver.dart).
  static ThemeData driverLight() => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: DriverColors.brand,
          onPrimary: Colors.white,
          primaryContainer: DriverColors.mistDeep,
          onPrimaryContainer: DriverColors.moss900,
          secondary: DriverColors.accent,
          onSecondary: Colors.white,
          secondaryContainer: DriverColors.sage,
          onSecondaryContainer: DriverColors.moss900,
          tertiary: Color(0xFF1E6B3F),
          onTertiary: Colors.white,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF151C10),
          onSurfaceVariant: Color(0xFF5B6653),
          outline: Color(0xFFA3AE99),
          outlineVariant: Color(0xFFE1E8DA),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: DriverColors.mist,
          surfaceContainer: Color(0xFFF0F4EC),
          surfaceContainerHigh: DriverColors.mistDeep,
          surfaceContainerHighest: Color(0xFFDDE7D3),
          inverseSurface: DriverColors.moss900,
          onInverseSurface: Colors.white,
        ),
        scaffold: const Color(0xFFF6F7F3),
      );

  static ThemeData driverDark() => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: DriverColors.leaf,
          onPrimary: DriverColors.moss950,
          primaryContainer: Color(0xFF26361A),
          onPrimaryContainer: Color(0xFFE3EED8),
          secondary: Color(0xFF9DBF7E),
          onSecondary: DriverColors.moss950,
          secondaryContainer: Color(0xFF2F4321),
          onSecondaryContainer: Color(0xFFE3EED8),
          tertiary: Color(0xFF7FD4A0),
          onTertiary: Color(0xFF0B2A17),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          surface: Color(0xFF151B11),
          onSurface: Color(0xFFE6ECE0),
          onSurfaceVariant: Color(0xFFB4C0AA),
          outline: Color(0xFF7D8a73),
          outlineVariant: Color(0xFF2E3A26),
          surfaceContainerLowest: Color(0xFF0B1008),
          surfaceContainerLow: Color(0xFF11170D),
          surfaceContainer: Color(0xFF1A2214),
          surfaceContainerHigh: Color(0xFF222C1B),
          surfaceContainerHighest: Color(0xFF2C3824),
          inverseSurface: Color(0xFFE6ECE0),
          onInverseSurface: DriverColors.moss900,
        ),
        scaffold: const Color(0xFF0D120A),
      );

  static ThemeData _build(ColorScheme scheme, {required Color scaffold}) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scaffold);
    final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(scheme.outlineVariant),
        enabledBorder: border(scheme.outlineVariant),
        focusedBorder: border(scheme.primary, 1.6),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 1.6),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
