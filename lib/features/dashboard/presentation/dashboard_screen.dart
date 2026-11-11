import 'package:flutter/material.dart';

import '../../../design/motion.dart';
import '../../../design/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/application/session.dart';
import '../../auth/models/vendor_account.dart';
import '../../auth/presentation/status_screens.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../orders/application/orders_providers.dart';
import '../../orders/models/order.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../orders/presentation/widgets/order_card.dart';
import '../../settings/application/settings_providers.dart';
import '../application/dashboard_providers.dart';
import '../models/dashboard_stats.dart';

/// The kitchen's home: store switch, today's orders and money, recent orders.
/// Every figure comes from the backend.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(vendorProvider);
    final stats = ref.watch(dashboardProvider);

    Future<void> refresh() async {
      await Future.wait([
        ref.read(sessionProvider.notifier).refreshVendor(),
        ref.read(dashboardProvider.notifier).reload(silent: false),
        ref.read(ordersListProvider(null).notifier).reload(),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: const [NotificationBellButton()]),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                Reveal(child: _Header(vendor: vendor)),
                const SizedBox(height: 14),
                Reveal(index: 1, child: _StoreCard(vendor: vendor)),
                const SizedBox(height: 14),
                Reveal(index: 2, child: stats.when(
                  loading: () => const _StatsSkeleton(),
                  error: (error, _) => SizedBox(
                    height: 260,
                    child: ErrorState(error: error, onRetry: () => ref.invalidate(dashboardProvider)),
                  ),
                  data: (data) => _StatsSection(stats: data),
                )),
                SectionHeader('Recent orders', action: 'See all', onAction: () {
                  ref.read(ordersFilterProvider.notifier).set(null);
                  context.go('/orders');
                }),
                const Reveal(index: 3, child: _RecentOrders()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vendor});

  final VendorAccount vendor;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, icon) = switch (vendor.verificationStatus) {
      VerificationStatus.approved => (Tone.success, Icons.verified_rounded),
      VerificationStatus.pending => (Tone.warning, Icons.hourglass_top_rounded),
      _ => (Tone.danger, Icons.block_rounded),
    };
    return Row(children: [
      AppImage(url: vendor.avatarUrl, width: 56, height: 56, radius: 18),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(vendor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KLType.display(26, theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            StatusChip(label: vendor.verificationStatus.label, tone: tone, icon: icon, dense: true),
            if (vendor.vendorTypeLabel.isNotEmpty) StatusChip(label: vendor.vendorTypeLabel, dense: true),
          ]),
        ]),
      ),
    ]);
  }
}

/// The open / closed switch. Uses `PATCH /vendor/availability`; the backend
/// uses the registered kitchen coordinates, so nothing is read from the phone.
class _StoreCard extends ConsumerStatefulWidget {
  const _StoreCard({required this.vendor});

  final VendorAccount vendor;

  @override
  ConsumerState<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends ConsumerState<_StoreCard> {
  bool _saving = false;

  Future<void> _toggle(bool open) async {
    final vendor = widget.vendor;
    if (_saving) return;
    if (!vendor.isApproved) {
      if (vendor.isPending) await showPendingExplanation(context, vendor);
      return;
    }
    setState(() => _saving = true);
    final updated = await runAction(
      context,
      () => ref.read(settingsActionsProvider).setStoreOpen(open),
      success: open ? 'Your kitchen is open for orders.' : 'Your kitchen is closed.',
    );
    if (mounted) setState(() => _saving = false);
    if (updated != null) ref.invalidate(dashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendor = widget.vendor;
    final open = vendor.isOpen;
    final colors = toneColors(context, open ? Tone.success : Tone.neutral);
    return AppCard(
      color: colors.background,
      borderColor: Colors.transparent,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: colors.foreground.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(open ? Icons.storefront_rounded : Icons.store_mall_directory_outlined, color: colors.foreground),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(open ? 'Open for orders' : 'Closed', style: theme.textTheme.titleMedium?.copyWith(color: colors.foreground)),
            Text(
              !vendor.isApproved
                  ? 'You can open your kitchen once your account is approved.'
                  : open
                      ? 'Customers can see and order from you.'
                      : 'Customers cannot order. Switch on to start taking orders.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.foreground),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        if (_saving)
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6))
        else
          Switch(value: open, onChanged: _toggle),
      ]),
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.stats});

  final DashboardStats stats;

  void _openOrders(WidgetRef ref, BuildContext context, OrderStatus? status) {
    ref.read(ordersFilterProvider.notifier).set(status);
    context.go('/orders');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView(
        // A fixed tile height (grown with the text size), not an aspect ratio:
        // a ratio made the tiles too short for their content on narrow phones.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 136 * MediaQuery.textScalerOf(context).scale(14).clamp(14, 28) / 14,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          StatCard(
            label: 'New orders',
            value: '${stats.newOrders}',
            icon: Icons.notifications_active_rounded,
            tone: Tone.warning,
            onTap: () => _openOrders(ref, context, OrderStatus.newOrder),
          ),
          StatCard(
            label: 'Preparing',
            value: '${stats.preparingOrders}',
            icon: Icons.soup_kitchen_rounded,
            onTap: () => _openOrders(ref, context, OrderStatus.preparing),
          ),
          StatCard(
            label: 'Ready',
            value: '${stats.readyOrders}',
            icon: Icons.check_circle_outline_rounded,
            tone: Tone.success,
            onTap: () => _openOrders(ref, context, OrderStatus.ready),
          ),
          StatCard(
            label: "Today's orders",
            value: '${stats.todayOrders}',
            icon: Icons.receipt_long_rounded,
            tone: Tone.info,
            caption: '${stats.completedToday} completed',
            onTap: () => _openOrders(ref, context, null),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: StatCard(label: "Today's sales", value: formatRwf(stats.todaySalesRwf), icon: Icons.trending_up_rounded, tone: Tone.success)),
        const SizedBox(width: 12),
        Expanded(child: StatCard(label: 'Total sales', value: formatRwf(stats.totalSalesRwf), icon: Icons.bar_chart_rounded)),
      ]),
      const SizedBox(height: 12),
      AppCard(
        onTap: () => context.go('/wallet'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Earnings', style: theme.textTheme.titleMedium)),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ]),
          const SizedBox(height: 12),
          _MoneyRow('Available balance', formatRwf(stats.availableBalanceRwf), bold: true),
          _MoneyRow('Pending (orders in progress)', formatRwf(stats.pendingBalanceRwf)),
          _MoneyRow('Net earned', formatRwf(stats.netEarnedRwf)),
          _MoneyRow('Withdrawn', formatRwf(stats.withdrawnRwf)),
          _MoneyRow(
            'Platform commission',
            '${stats.commissionPercent.toStringAsFixed(stats.commissionPercent % 1 == 0 ? 0 : 1)}%',
          ),
        ]),
      ),
    ]);
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        Text(value, style: bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Row(children: [
          Expanded(child: SkeletonBox(height: 86, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(height: 86, radius: 16)),
        ]),
        SizedBox(height: 12),
        Row(children: [
          Expanded(child: SkeletonBox(height: 86, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(height: 86, radius: 16)),
        ]),
        SizedBox(height: 12),
        SkeletonBox(height: 150, radius: 16),
      ]);
}

class _RecentOrders extends ConsumerWidget {
  const _RecentOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersListProvider(null));
    return orders.when(
      loading: () => const Column(children: [SkeletonBox(height: 120, radius: 16)]),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(ordersListProvider(null))),
      data: (data) {
        if (data.items.isEmpty) {
          return const AppCard(
            child: EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No orders yet',
              message: 'Orders from customers will show up here.',
            ),
          );
        }
        return Column(children: [
          for (final order in data.items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OrderCard(order: order, onOpen: () => context.push('/orders/${order.id}')),
            ),
        ]);
      },
    );
  }
}
