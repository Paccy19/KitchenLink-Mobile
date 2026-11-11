import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) =>
      MaterialApp(title: 'KitchenLink', debugShowCheckedModeBanner: false, theme: buildClientTheme(), home: const HomeScreen());
}
