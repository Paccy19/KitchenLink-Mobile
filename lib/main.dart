/// The KitchenLink marketplace (customer app): the default `flutter run`.
/// The admin app is `flutter run -t lib/main_admin.dart`.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'client/client_theme.dart';
import 'client/customer_api.dart';
import 'client/customer_session.dart';
import 'client/location.dart';
import 'client/screens/home_screen.dart';
import 'client/widgets/home_bars.dart';
import 'config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => CustomerApi(ApiClient(baseUrl: kDefaultApiBaseUrl))),
        ChangeNotifierProvider(create: (_) => ClientLocation()..restore()),
        ChangeNotifierProvider(create: (_) => RecentSearches()..restore()),
        ChangeNotifierProvider(create: (_) => CustomerSession(ApiClient(baseUrl: kDefaultApiBaseUrl))..restore()),
      ],
      child: const KitchenLinkMarketApp(),
    ),
  );
}

class KitchenLinkMarketApp extends StatelessWidget {
  const KitchenLinkMarketApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'KitchenLink', debugShowCheckedModeBanner: false, theme: buildClientTheme(), home: const HomeScreen());
}
