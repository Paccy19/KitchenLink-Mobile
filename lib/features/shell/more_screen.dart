import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../auth/application/session.dart';
import '../chat/application/chat_providers.dart';
import '../notifications/application/notifications_providers.dart';
import '../support/application/support_providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vendor = ref.watch(vendorProvider);
    final chats = ref.watch(chatUnreadProvider).value ?? 0;
    final support = ref.watch(supportUnreadProvider).value ?? 0;
    final alerts = ref.watch(notificationsProvider).value?.unreadCount ?? 0;

    Widget tile(IconData icon, String title, String route, {int badge = 0, String? subtitle}) => ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: badge > 0 ? CountBadge(count: badge) : const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            AppCard(
              onTap: () => context.push('/settings/account'),
              child: Row(children: [
                AppImage(url: vendor.avatarUrl, width: 52, height: 52, radius: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(vendor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    Text(vendor.phone, style: theme.textTheme.bodySmall),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            const SectionHeader('Customers'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                tile(Icons.chat_bubble_outline_rounded, 'Messages', '/messages', badge: chats),
                const Divider(),
                tile(Icons.notifications_none_rounded, 'Notifications', '/notifications', badge: alerts),
              ]),
            ),
            const SectionHeader('Promote your kitchen'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                tile(Icons.wb_twilight_rounded, "Tomorrow's special", '/special'),
                const Divider(),
                tile(Icons.local_offer_outlined, 'Offer days', '/offers'),
              ]),
            ),
            const SectionHeader('Settings'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                tile(Icons.storefront_outlined, 'Account details', '/settings/account'),
                const Divider(),
                tile(Icons.location_on_outlined, 'Kitchen location', '/settings/location', subtitle: vendor.location.summary),
                const Divider(),
                tile(Icons.category_outlined, 'Kitchen type', '/settings/type', subtitle: vendor.vendorTypeLabel),
                const Divider(),
                tile(Icons.rule_rounded, 'How you take orders', '/settings/ordering'),
                const Divider(),
                tile(Icons.public_rounded, 'Nationwide events', '/settings/nationwide'),
                const Divider(),
                tile(Icons.celebration_outlined, 'Big event packages', '/settings/events'),
              ]),
            ),
            const SectionHeader('Help'),
            AppCard(padding: EdgeInsets.zero, child: tile(Icons.support_agent_rounded, 'Help & support', '/support', badge: support)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                final yes = await confirm(context, title: 'Sign out?', message: 'You will need a new SMS code to sign in again.', confirmLabel: 'Sign out');
                if (yes) await ref.read(sessionProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
            TextButton(
              onPressed: () async {
                final yes = await confirm(
                  context,
                  title: 'Sign out of all devices?',
                  message: 'Every phone signed in to this kitchen will be signed out, including this one.',
                  confirmLabel: 'Sign out everywhere',
                  destructive: true,
                );
                if (yes) await ref.read(sessionProvider.notifier).logout(everywhere: true);
              },
              child: const Text('Sign out of all devices'),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'KitchenLink Kitchen · ${AppConfig.current.apiBaseUrl}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
