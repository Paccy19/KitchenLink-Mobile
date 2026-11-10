import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../core/config/app_config.dart';
import 'client_theme.dart';
import 'customer_api.dart';
import 'customer_session.dart';
import 'location.dart';
import 'screens/home_screen.dart';
import 'widgets/home_bars.dart';

/// The public marketplace (customers), as one role of the app. Everyone
/// starts here, like on the website.
Widget buildMarketApp() => MultiProvider(
      providers: [
        // The address saved on a sign-in screen (a phone on the computer's
        // Wi-Fi), else the build default: the same one every role uses.
        Provider(create: (_) => CustomerApi(ApiClient(baseUrl: AppConfig.current.apiBaseUrl))),
        ChangeNotifierProvider(create: (_) => CustomerSession(ApiClient(baseUrl: AppConfig.current.apiBaseUrl))..restore()),
        ChangeNotifierProvider(create: (_) => ClientLocation()..restore()),
        ChangeNotifierProvider(create: (_) => RecentSearches()..restore()),
      ],
      child: const KitchenLinkMarketApp(),
    );

class KitchenLinkMarketApp extends StatelessWidget {
  const KitchenLinkMarketApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'KitchenLink', debugShowCheckedModeBanner: false, theme: buildClientTheme(), home: const HomeScreen());
}
