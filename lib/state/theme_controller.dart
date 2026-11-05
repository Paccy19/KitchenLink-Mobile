import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Light / dark mode, switched from the header like the website's ThemeToggle
/// and remembered on the device.
class ThemeController extends ChangeNotifier {
  static const _key = 'ofk_theme';
  static const _storage = FlutterSecureStorage();

  ThemeMode mode = ThemeMode.light;

  bool get isDark => mode == ThemeMode.dark;

  Future<void> restore() async {
    try {
      if (await _storage.read(key: _key) == 'dark') {
        mode = ThemeMode.dark;
        notifyListeners();
      }
    } catch (_) {}
  }

  void toggle() {
    mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _storage.write(key: _key, value: isDark ? 'dark' : 'light').catchError((_) {});
  }
}
