// The admin app, KitchenLink Admin (the default entry point).
// The vendor app starts from lib/main_vendor.dart.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/admin_shell.dart';
import 'screens/login_screen.dart';
import 'state/admin_session.dart';
import 'state/theme_controller.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminSession()..restore()),
        ChangeNotifierProvider(create: (_) => ThemeController()..restore()),
      ],
      child: const KitchenLinkAdminApp(),
    ),
  );
}

class KitchenLinkAdminApp extends StatelessWidget {
  const KitchenLinkAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KitchenLink Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: context.watch<ThemeController>().mode,
      home: const _Root(),
    );
  }
}

/// Signed out → sign-in; signed in → the admin panel.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    if (session.restoring) return const _Splash(label: 'Starting…');
    if (!session.hasToken) return const LoginScreen();
    if (!session.isAuthenticated) {
      if (session.loading) return const _Splash(label: 'Loading admin panel…');
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ErrorNote(error: session.error.isEmpty ? 'Could not load your admin profile.' : session.error),
                const SizedBox(height: 16),
                FilledButton(onPressed: session.restore, child: const Text('Try again')),
                TextButton(onPressed: session.logout, child: const Text('Sign out')),
              ]),
            ),
          ),
        ),
      );
    }
    return const AdminShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: LoadingBlock(label: label));
}
