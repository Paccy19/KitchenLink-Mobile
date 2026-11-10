// KitchenLink: one app for every kind of user. Run it with `flutter run`.
//
// It opens on the marketplace; "Sign in" asks how you want to sign in
// (customer, vendor, delivery worker or admin), like the website, and each
// role has its own sign-in and session.
import 'package:flutter/material.dart';

import 'core/config/server_address.dart';
import 'root/kitchenlink_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A server address chosen in the app is used from the very first request.
  await ServerAddressStore().applySaved();
  runApp(const KitchenLinkRoot());
}
