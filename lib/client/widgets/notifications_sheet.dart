import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/format.dart' show formatRelative;
import '../client_theme.dart';
import '../market_nav.dart';
import '../market_state.dart';
import 'cards.dart';

/// Opens what a notification is about (the website's notificationLink): its
/// own `data.link` when it has one, otherwise the order or the support page.
Future<void> openNotification(BuildContext context, Json notification) async {
  final data = notification['data'] is Map ? notification['data'] as Map : const {};
  final link = '${data['link'] ?? ''}';
  final orderId = '${notification['order_id'] ?? ''}';
  final uri = Uri.tryParse(link);
  if (uri != null && link.startsWith('/')) {
    final parts = uri.pathSegments;
    if (parts.length >= 2 && parts.first == 'track') return MarketNav.order(context, parts[1]);
    if (parts.length >= 2 && parts.first == 'vendor') return MarketNav.kitchen(context, parts[1]);
    if (parts.isNotEmpty && parts.first == 'messages') {
      final chat = uri.queryParameters['chat'];
      return chat == null ? MarketNav.messages(context) : MarketNav.chat(context, chat);
    }
    if (parts.isNotEmpty && parts.first == 'support') return MarketNav.support(context);
    if (parts.isNotEmpty && parts.first == 'orders') return MarketNav.orders(context);
    if (parts.isNotEmpty && parts.first == 'wishlist') return MarketNav.wishlist(context);
    if (parts.isNotEmpty && parts.first == 'profile') return MarketNav.profile(context);
  }
  if (notification['type'] == 'support_message') return MarketNav.support(context);
  if (orderId.isNotEmpty) return MarketNav.order(context, orderId);
  return MarketNav.orders(context);
}

/// The bell's list (the website's Navbar notifications dropdown).
Future<void> showNotificationsSheet(BuildContext context) {
  context.read<Notifications>().refresh();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: K.surface,
    builder: (sheet) => FractionallySizedBox(
      heightFactor: 0.8,
      child: Consumer<Notifications>(
        builder: (_, notifications, _) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(children: [
              Expanded(child: Text('Notifications', style: kText(18, weight: w900))),
              if (notifications.unread > 0)
                TextButton(onPressed: notifications.markAllRead, child: Text('Mark all read', style: kText(12, weight: FontWeight.w700, color: K.brown700))),
            ]),
          ),
          Expanded(
            child: notifications.items.isEmpty
                ? ListView(padding: const EdgeInsets.all(20), children: const [
                    EmptyCard(icon: Icons.notifications_none, title: 'No notifications yet', message: 'Order updates, replies from support and kitchen messages show up here.'),
                  ])
                : ListView.separated(
                    itemCount: notifications.items.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: K.stone100),
                    itemBuilder: (_, i) {
                      final n = notifications.items[i];
                      final unread = n['read'] != true;
                      return ListTile(
                        tileColor: unread ? K.brown50 : null,
                        leading: Icon(unread ? Icons.notifications_active_outlined : Icons.notifications_none, color: unread ? K.brown700 : K.stone400),
                        title: Text('${n['title'] ?? ''}', style: kText(13.5, weight: unread ? w900 : FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ('${n['message'] ?? n['body'] ?? ''}'.isNotEmpty) Text('${n['message'] ?? n['body']}', style: kText(12, color: K.stone600)),
                          Text(formatRelative(n['created_at']), style: kText(10.5, color: K.stone400)),
                        ]),
                        onTap: () {
                          notifications.markRead('${n['id']}');
                          Navigator.pop(sheet);
                          openNotification(context, n);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}
