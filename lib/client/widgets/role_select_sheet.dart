import 'package:flutter/material.dart';

import '../client_theme.dart';

/// Who is signing in, picked in [showRoleSelect].
enum SignInRole { customer, vendor, driver, admin }

class _Role {
  const _Role(this.role, this.title, this.description, this.icon, this.colors);

  final SignInRole role;
  final String title;
  final String description;
  final IconData icon;
  final List<Color> colors;
}

/// Same order, wording and tile colours as the website.
const _roles = [
  _Role(SignInRole.customer, 'Customer', 'Order food from home cooks & kitchens around you', Icons.person_outline,
      [Color(0xFF2B1206), Color(0xFF481F0D), Color(0xFF1C0A03)]),
  _Role(SignInRole.vendor, 'Vendor', 'Sell your food, manage your menu, orders & earnings', Icons.storefront_outlined,
      [Color(0xFF3D1B0C), Color(0xFF6D391D), Color(0xFF2B1206)]),
  _Role(SignInRole.driver, 'Delivery Worker', 'Pick up & deliver orders, track your deliveries & earnings', Icons.pedal_bike,
      [Color(0xFF1C2B12), Color(0xFF3B5327), Color(0xFF12200B)]),
  _Role(SignInRole.admin, 'Admin', 'Manage the marketplace, users, orders, payments & analytics', Icons.verified_user_outlined,
      [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF0B1220)]),
];

/// Opens a popup the way the website's modals do: dark see-through backdrop,
/// fade + slight zoom in. Tapping outside closes it.
Future<T?> showMarketDialog<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => builder(context),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(curved), child: child),
        );
      },
    );

/// The website's modal card: `bg-white rounded-3xl max-w-md p-6 sm:p-8`,
/// with the close (X) button in the top-right corner.
class MarketDialogCard extends StatelessWidget {
  const MarketDialogCard({super.key, required this.children, this.onClose, this.crossAxisAlignment = CrossAxisAlignment.stretch});

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  /// Defaults to closing the popup.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Material(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              elevation: 24,
              shadowColor: const Color(0x40000000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: K.stone100),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.all(wide ? 32 : 24),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: crossAxisAlignment, children: children),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20, color: K.stone400),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's "How do you want to sign in?" popup (RoleSelectModal).
/// Returns the chosen role, or null when closed.
Future<SignInRole?> showRoleSelect(BuildContext context) =>
    showMarketDialog<SignInRole>(context, (_) => const _RoleSelectDialog());

class _RoleSelectDialog extends StatelessWidget {
  const _RoleSelectDialog();

  @override
  Widget build(BuildContext context) => MarketDialogCard(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'How do you want to sign in?',
              textAlign: TextAlign.center,
              style: kText(24, weight: w900, color: K.gray900, spacing: -0.6, height: 1.33),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your role and we will take you to the right login page.',
            textAlign: TextAlign.center,
            style: kText(12, color: K.stone500, height: 1.33),
          ),
          const SizedBox(height: 24),
          for (final role in _roles) ...[
            _RoleTile(role: role),
            if (role != _roles.last) const SizedBox(height: 12),
          ],
        ],
      );
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.role});

  final _Role role;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: K.stone200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(role.role),
          hoverColor: K.brown50,
          highlightColor: K.brown50,
          splashColor: K.brown100,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: role.colors),
                    boxShadow: K.shadowMd,
                  ),
                  child: Icon(role.icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.title, style: kText(14, weight: FontWeight.w700, color: K.gray900)),
                      const SizedBox(height: 2),
                      Text(role.description, style: kText(11, color: K.stone500, height: 1.375)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_forward, size: 16, color: K.stone300),
              ],
            ),
          ),
        ),
      );
}
