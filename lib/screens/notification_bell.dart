import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../nav/admin_nav.dart';
import '../state/admin_session.dart';
import '../ui/format.dart';
import '../ui/query.dart';
import '../ui/theme.dart';
import 'admin_shell.dart';

const _typeMeta = <String, (IconData, Tone)>{
  'vendor_application': (Icons.storefront_outlined, Tone.amber),
  'vendor_type_request': (Icons.category_outlined, Tone.orange),
  'category_added': (Icons.category_outlined, Tone.amber),
  'driver_application': (Icons.pedal_bike_outlined, Tone.blue),
  'complaint_opened': (Icons.report_outlined, Tone.red),
  'payout_requested': (Icons.account_balance_wallet_outlined, Tone.violet),
  'order_placed': (Icons.shopping_bag_outlined, Tone.green),
  'payment_failed': (Icons.credit_card_off_outlined, Tone.red),
  'owner_finance': (Icons.account_balance_outlined, Tone.violet),
  'payout_update': (Icons.account_balance_wallet_outlined, Tone.violet),
  'refund_update': (Icons.replay_outlined, Tone.blue),
  'late_pickup': (Icons.pedal_bike_outlined, Tone.red),
  'general': (Icons.notifications_none, Tone.slate),
};

// Where a notification opens when it carries no link of its own.
const _fallbackLink = {
  'vendor_application': '/admin-dashboard/vendors',
  'vendor_type_request': '/admin-dashboard/vendors',
  'category_added': '/admin-dashboard/categories',
  'driver_application': '/admin-dashboard/drivers',
  'complaint_opened': '/admin-dashboard/complaints',
  'payout_requested': '/admin-dashboard/payouts',
  'order_placed': '/admin-dashboard/orders',
  'payment_failed': '/admin-dashboard/payments',
  'owner_finance': '/admin-dashboard/platform',
  'refund_update': '/admin-dashboard/refunds',
  'late_pickup': '/admin-dashboard/deliveries?tab=late',
};

String _linkFor(Json item) => jstr(jmap(item['data'])['link'], _fallbackLink[item['type']] ?? '/admin-dashboard');

/// The header bell (`w-10 h-10 rounded-xl bg-stone-100`) with the red unread
/// count; polls every 15 seconds, pops up new ones, and opens the
/// notifications panel under the header like the website.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final AdminSession session = context.read<AdminSession>();
  late final Query<Json> query = Query(
    () async => jmap(await session.api.listNotifications({'limit': 20})),
    client: session.client,
    poll: const Duration(seconds: 15),
  )..addListener(_popNew);
  Set<String>? seen;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  /// A new unread notification shows a pop-up once (the website's NotificationPopups).
  void _popNew() {
    final items = jlist(query.data?['notifications']);
    if (query.data == null) return;
    final ids = items.map((item) => jstr(item['id'])).toSet();
    if (seen == null) {
      seen = ids;
      return;
    }
    final fresh = items.where((item) => item['read'] != true && !seen!.contains(jstr(item['id']))).toList();
    seen!.addAll(ids);
    if (fresh.isEmpty || !mounted) return;
    final item = fresh.first;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Text('${jstr(item['title'])}\n${jstr(item['body'])}', maxLines: 3),
      action: SnackBarAction(label: 'Open', onPressed: () => _open(item)),
    ));
  }

  void _open(Json item) {
    if (item['read'] != true) session.api.markNotificationRead(jstr(item['id'])).catchError((_) => null);
    context.read<ShellNavigator>().go(AdminRoute.fromLink(_linkFor(item)));
  }

  void _showPanel() {
    final top = MediaQuery.of(context).padding.top + 65 + 8;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: top, right: 16, left: 16),
          child: _NotificationPanel(
            query: query,
            onOpen: (item) {
              Navigator.pop(dialogContext);
              _open(item);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final unread = jint(query.data?['unread_count']);
        return Stack(clipBehavior: Clip.none, children: [
          HeaderButton(onTap: _showPanel, tooltip: 'Notifications', child: Icon(Icons.notifications_none, size: 20, color: p.textSecondary)),
          if (unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: AppColors.red500, borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.center,
                  child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// `w-[88vw] max-w-sm bg-white rounded-2xl shadow-2xl border`: header with
/// "Notifications" and "Mark all read", then the list.
class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({required this.query, required this.onOpen});

  final Query<Json> query;
  final ValueChanged<Json> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    final p = Palette.of(context);
    final width = MediaQuery.of(context).size.width;
    return Material(
      color: p.card,
      elevation: 24,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.divider)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (width * 0.88).clamp(0, 384).toDouble(), maxHeight: MediaQuery.of(context).size.height * 0.65 + 50),
        child: ListenableBuilder(
          listenable: query,
          builder: (context, _) {
            final items = jlist(query.data?['notifications']);
            final unread = jint(query.data?['unread_count']);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
                child: Row(children: [
                  Expanded(child: Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text))),
                  if (unread > 0)
                    InkWell(
                      onTap: () => api.markAllNotificationsRead().catchError((_) => null),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.done_all, size: 14, color: p.accent),
                        const SizedBox(width: 4),
                        Text('Mark all read', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.accent)),
                      ]),
                    ),
                ]),
              ),
              Flexible(
                child: query.data == null
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                    : items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.inbox_outlined, size: 28, color: p.faint),
                              const SizedBox(height: 8),
                              Text('You are all caught up', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.faint)),
                            ]),
                          )
                        : ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [for (final item in items) _row(context, item)]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Json item) {
    final p = Palette.of(context);
    final (icon, tone) = _typeMeta[item['type']] ?? _typeMeta['general']!;
    final read = item['read'] == true;
    return InkWell(
      onTap: () => onOpen(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: read ? null : Tone.amber.background(context).withValues(alpha: 0.4),
          border: Border(bottom: BorderSide(color: p.stone50)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tone.background(context), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: tone.base),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(jstr(item['title']), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
                if (!read) ...[const SizedBox(width: 8), const CircleAvatar(radius: 3, backgroundColor: AppColors.red500)],
              ]),
              const SizedBox(height: 2),
              Text(jstr(item['body']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              const SizedBox(height: 4),
              Text(formatRelative(item['created_at']), style: TextStyle(fontSize: 10, color: p.faint)),
            ]),
          ),
        ]),
      ),
    );
  }
}
