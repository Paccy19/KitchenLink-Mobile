/// The KitchenLink admin panel. Run it with `flutter run -t lib/main_admin.dart`;
/// the marketplace (customer app) is lib/main.dart.
library;

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
  const KitchenLinkAdminApp({super.key, this.navigatorKey, this.onExit});

  final GlobalKey<NavigatorState>? navigatorKey;

  /// Set when the admin panel was opened from the marketplace app: the
  /// sign-in page's "Back to marketplace" then returns there.
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KitchenLink Admin',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: context.watch<ThemeController>().mode,
      home: _Root(onExit: onExit),
    );
  }
}

/// Opens the admin panel (sign-in first) on top of the marketplace app.
/// Back steps through the admin's own pages first, then returns to the marketplace.
Future<void> openAdminPanel(BuildContext context) {
  final adminNavigator = GlobalKey<NavigatorState>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final handled = await adminNavigator.currentState?.maybePop() ?? false;
          if (!handled && routeContext.mounted) Navigator.of(routeContext).pop();
        },
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AdminSession()..restore()),
            ChangeNotifierProvider(create: (_) => ThemeController()..restore()),
          ],
          child: KitchenLinkAdminApp(
            navigatorKey: adminNavigator,
            onExit: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    ),
  );
}

/// Signed out → sign-in; signed in → the admin panel.
class _Root extends StatelessWidget {
  const _Root({this.onExit});

  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    if (session.restoring) return const _Splash(label: 'Starting…');
    if (!session.hasToken) return LoginScreen(onBackToMarketplace: onExit);
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
