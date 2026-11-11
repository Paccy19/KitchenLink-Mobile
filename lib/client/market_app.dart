import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../api/api_client.dart';
import '../core/config/app_config.dart';
import 'client_theme.dart';
import 'customer_api.dart';
import 'customer_session.dart';
import 'location.dart';
import 'market_state.dart';
import 'screens/home_screen.dart';
import 'widgets/home_bars.dart';

/// The public marketplace (customers), as one role of the app. Everyone
/// starts here, like on the website.
Widget buildMarketApp() {
  // One connection for the session and every customer request, so the
  // sign-in token goes with the basket, orders, chats… (the address saved on
  // a sign-in screen, else the build default: the same one every role uses).
  return MultiProvider(providers: marketProviders(ApiClient(baseUrl: AppConfig.current.apiBaseUrl)), child: const KitchenLinkMarketApp());
}

/// The customer's state, all on one [ApiClient].
List<SingleChildWidget> marketProviders(ApiClient client) => [
      ChangeNotifierProvider(create: (_) => MarketTheme()..restore((key) => const FlutterSecureStorage().read(key: key))),
      ChangeNotifierProvider(create: (_) => CustomerSession(client)..restore()),
      // Requests always go through the session's own connection, so they
      // carry its sign-in token (checkout, basket, orders, chats…).
      Provider(create: (c) => CustomerApi(c.read<CustomerSession>().client)),
      ChangeNotifierProvider(create: (_) => ClientLocation()..restore()),
      ChangeNotifierProvider(create: (_) => RecentSearches()..restore()),
      ChangeNotifierProvider(create: (c) => Cart(c.read<CustomerApi>(), c.read<CustomerSession>(), c.read<ClientLocation>())..restore()),
      ChangeNotifierProvider(create: (c) => Wishlist(c.read<CustomerApi>(), c.read<CustomerSession>())..restore()),
      ChangeNotifierProvider(create: (c) => Orders(c.read<CustomerApi>(), c.read<CustomerSession>())),
      ChangeNotifierProvider(create: (c) => Notifications(c.read<CustomerApi>(), c.read<CustomerSession>())),
    ];

class KitchenLinkMarketApp extends StatelessWidget {
  const KitchenLinkMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.watch<MarketTheme>().isDark;
    return _PaletteScope(
      dark: dark,
      child: MaterialApp(title: 'KitchenLink', debugShowCheckedModeBanner: false, theme: buildClientTheme(dark: dark), home: const HomeScreen()),
    );
  }
}

/// The palette ([K]) is read while building, and many widgets are `const`,
/// so a theme switch marks every screen (and open sheet) to build again,
/// keeping where the customer is.
class _PaletteScope extends StatefulWidget {
  const _PaletteScope({required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  State<_PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<_PaletteScope> {
  @override
  void didUpdateWidget(_PaletteScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dark == widget.dark) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
