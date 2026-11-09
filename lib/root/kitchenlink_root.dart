import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app.dart';
import '../client/market_app.dart';
import '../driver/app/driver_app.dart';
import '../screens/admin_app.dart';
import 'role_switcher.dart';

/// The one KitchenLink app. It shows the marketplace, or the screens of the
/// role the person signed in as (kitchen, delivery worker, admin). Each role
/// keeps its own sign-in and token, exactly as on the website, and switching
/// role rebuilds that role's screens from scratch.
class KitchenLinkRoot extends StatefulWidget {
  const KitchenLinkRoot({super.key, this.store = const RoleStore()});

  final RoleStore store;

  @override
  State<KitchenLinkRoot> createState() => _KitchenLinkRootState();
}

class _KitchenLinkRootState extends State<KitchenLinkRoot> {
  AppRole? _role;

  @override
  void initState() {
    super.initState();
    widget.store.read().then((role) {
      if (mounted) setState(() => _role = role);
    });
  }

  void _open(AppRole role) {
    if (role == _role) return;
    setState(() => _role = role);
    widget.store.write(role);
  }

  Widget _app(AppRole role) {
    switch (role) {
      case AppRole.marketplace:
        return buildMarketApp();
      case AppRole.vendor:
        // A failed load shows "Try again", never retried silently.
        return ProviderScope(retry: (_, _) => null, child: const KitchenLinkApp());
      case AppRole.driver:
        return ProviderScope(retry: (_, _) => null, overrides: driverOverrides, child: const KitchenLinkDeliveryApp());
      case AppRole.admin:
        return buildAdminApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    if (role == null) {
      // Reading the remembered role takes a moment at launch.
      return const ColoredBox(color: Color(0xFFFAF7F4));
    }
    return RoleSwitcher(
      current: role,
      open: _open,
      child: KeyedSubtree(key: ValueKey(role), child: _app(role)),
    );
  }
}
