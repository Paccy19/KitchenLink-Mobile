import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../client_theme.dart';
import '../customer_session.dart';
import 'market_ui.dart';

/// Asks first, then signs the customer out: of this device, or of every
/// device ([everywhere], like the kitchen and delivery worker apps). Returns
/// true once signed out.
Future<bool> confirmSignOut(BuildContext context, {bool everywhere = false}) async {
  final session = context.read<CustomerSession>();
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(everywhere ? 'Sign out of all devices?' : 'Sign out?'),
      content: Text(
        everywhere
            ? 'You will be signed out on every phone and computer, including this one. Your basket and saved addresses on this device are cleared.'
            : 'You will need a new code to sign in again. Your basket and saved addresses on this device are cleared.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: K.rose600, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(everywhere ? 'Sign out everywhere' : 'Sign out'),
        ),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    if (everywhere) {
      await session.logoutEverywhere();
    } else {
      await session.logout();
    }
  } catch (error) {
    if (context.mounted) showMarketSnack(context, error.toString());
    return false;
  }
  if (context.mounted) showMarketSnack(context, everywhere ? 'Signed out on all devices.' : "You're signed out.");
  return true;
}

/// "Sign out" and "Sign out of all devices", as a grouped list.
class SignOutPanel extends StatelessWidget {
  const SignOutPanel({super.key, this.onSignedOut});

  /// Runs after a successful sign-out (e.g. to close the screen).
  final VoidCallback? onSignedOut;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, bool everywhere) => ListTile(
          minTileHeight: 50,
          leading: Icon(icon, color: K.rose600, size: 22),
          title: Text(label, style: kText(15, weight: FontWeight.w700, color: K.rose600)),
          onTap: () async {
            if (await confirmSignOut(context, everywhere: everywhere)) onSignedOut?.call();
          },
        );
    return Container(
      decoration: BoxDecoration(color: K.dark ? K.page : K.stone100.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: [
          tile(Icons.logout_rounded, 'Sign out', false),
          Divider(height: 0.6, thickness: 0.6, indent: 52, color: K.stone200),
          tile(Icons.devices_other_rounded, 'Sign out of all devices', true),
        ]),
      ),
    );
  }
}
