import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Who is using the app right now. One app, four kinds of user, like the
/// website: everyone starts on the marketplace, and "Sign in" asks
/// "How do you want to sign in?" (the website's `RoleSelectModal`).
enum AppRole {
  /// The public marketplace (customers browse without signing in).
  marketplace,
  vendor,
  driver,
  admin;

  static AppRole parse(String? value) =>
      AppRole.values.firstWhere((role) => role.name == value, orElse: () => AppRole.marketplace);
}

/// Remembers the last role on this phone, so a kitchen or delivery worker
/// reopening the app lands on their own screens.
class RoleStore {
  const RoleStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'ofk_app_role';
  final FlutterSecureStorage _storage;

  Future<AppRole> read() async {
    try {
      return AppRole.parse(await _storage.read(key: _key));
    } catch (_) {
      return AppRole.marketplace;
    }
  }

  Future<void> write(AppRole role) async {
    try {
      await _storage.write(key: _key, value: role.name);
    } catch (_) {
      // Not remembering the role only means starting on the marketplace.
    }
  }
}

/// Lets any screen, in any of the role apps, move to another role.
class RoleSwitcher extends InheritedWidget {
  const RoleSwitcher({
    super.key,
    required this.current,
    required this.open,
    this.returnTo,
    this.onVisitMarketplace,
    required super.child,
  });

  final AppRole current;
  final void Function(AppRole role) open;

  /// The signed-in role that is visiting the marketplace (a kitchen or a
  /// delivery worker), so the marketplace can offer the way back. Null for
  /// everyone else.
  final AppRole? returnTo;

  final VoidCallback? onVisitMarketplace;

  /// Opens the marketplace while staying signed in: the marketplace then
  /// offers "Back to …", and reopening the app still lands on this role.
  void visitMarketplace() => onVisitMarketplace != null ? onVisitMarketplace!() : open(AppRole.marketplace);

  /// Null when the screen runs outside the combined app (e.g. in a test).
  static RoleSwitcher? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RoleSwitcher>();

  @override
  bool updateShouldNotify(RoleSwitcher oldWidget) => current != oldWidget.current || returnTo != oldWidget.returnTo;
}

/// On the marketplace, for a kitchen or delivery worker who came to look
/// around: one tap back to their own screens, still signed in. Build it only
/// when [RoleSwitcher.returnTo] is set.
class ReturnToRoleButton extends StatelessWidget {
  const ReturnToRoleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final switcher = RoleSwitcher.maybeOf(context);
    final role = switcher?.returnTo;
    if (switcher == null || role == null) return const SizedBox.shrink();
    final (icon, label) = switch (role) {
      AppRole.driver => (Icons.delivery_dining_rounded, 'Back to deliveries'),
      AppRole.vendor => (Icons.storefront_rounded, 'Back to my kitchen'),
      AppRole.admin => (Icons.admin_panel_settings_rounded, 'Back to admin'),
      AppRole.marketplace => (Icons.arrow_back_rounded, 'Back'),
    };
    return FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: const Color(0xFF2B1206),
      foregroundColor: Colors.white,
      onPressed: () => switcher.open(role),
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// "How do you want to sign in?": the same four choices as the website.
Future<void> showSignInChooser(BuildContext context, {required Future<void> Function() onCustomerSignIn}) {
  final switcher = RoleSwitcher.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      Future<void> choose(AppRole role) async {
        Navigator.of(sheetContext).pop();
        if (role == AppRole.marketplace) {
          await onCustomerSignIn();
        } else {
          switcher?.open(role);
        }
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'How do you want to sign in?',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose your role and we will take you to the right sign-in.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            _RoleTile(
              icon: Icons.person_rounded,
              colors: const [Color(0xFF2B1206), Color(0xFF481F0D)],
              title: 'Customer',
              subtitle: 'Order food from home cooks and kitchens around you',
              onTap: () => choose(AppRole.marketplace),
            ),
            _RoleTile(
              icon: Icons.storefront_rounded,
              colors: const [Color(0xFF3D1B0C), Color(0xFF6D391D)],
              title: 'Vendor',
              subtitle: 'Sell your food, manage your menu, orders and earnings',
              onTap: () => choose(AppRole.vendor),
            ),
            _RoleTile(
              icon: Icons.delivery_dining_rounded,
              colors: const [Color(0xFF1C2B12), Color(0xFF3B5327)],
              title: 'Delivery Worker',
              subtitle: 'Pick up and deliver orders, track your trips and earnings',
              onTap: () => choose(AppRole.driver),
            ),
            _RoleTile(
              icon: Icons.admin_panel_settings_rounded,
              colors: const [Color(0xFF111827), Color(0xFF1F2937)],
              title: 'Admin',
              subtitle: 'Manage the marketplace, users, orders, payments and reports',
              onTap: () => choose(AppRole.admin),
            ),
          ]),
        ),
      );
    },
  );
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.icon, required this.colors, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// On each role's sign-in screen: back to the marketplace and the other
/// ways to sign in. Hidden when the screen runs on its own (tests).
class OtherSignInButton extends StatelessWidget {
  const OtherSignInButton({super.key});

  @override
  Widget build(BuildContext context) {
    final switcher = RoleSwitcher.maybeOf(context);
    if (switcher == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => switcher.open(AppRole.marketplace),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: const Text('Other ways to sign in'),
    );
  }
}
