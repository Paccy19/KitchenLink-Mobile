import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/components.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../application/orders_providers.dart';
import '../models/order.dart';
import 'widgets/order_card.dart';

/// Which status filter the Orders tab shows. The dashboard sets it when a
/// counter is tapped.
class OrdersFilterNotifier extends Notifier<OrderStatus?> {
  @override
  OrderStatus? build() => null;

  void set(OrderStatus? status) => state = status;
}

final ordersFilterProvider = NotifierProvider<OrdersFilterNotifier, OrderStatus?>(OrdersFilterNotifier.new);

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(ordersFilterProvider);
    final stats = ref.watch(dashboardProvider).value;

    int? countFor(OrderStatus? status) => switch (status) {
          OrderStatus.newOrder => stats?.newOrders,
          OrderStatus.preparing => stats?.preparingOrders,
          OrderStatus.ready => stats?.readyOrders,
          OrderStatus.completed => stats?.completedOrdersTotal,
          OrderStatus.cancelled => stats?.cancelledOrders,
          _ => null,
        };

    return Scaffold(
      appBar: AppBar(title: const Text('Orders'), actions: const [NotificationBellButton()]),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final status in <OrderStatus?>[null, ...OrderStatus.values])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    selected: filter == status,
                    onSelected: (_) => ref.read(ordersFilterProvider.notifier).set(status),
                    label: Text([
                      status?.label ?? 'All',
                      if ((countFor(status) ?? 0) > 0) ' ${countFor(status)}',
                    ].join()),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _OrdersList(status: filter)),
      ]),
    );
  }
}

class _OrdersList extends ConsumerStatefulWidget {
  const _OrdersList({required this.status});

  final OrderStatus? status;

  @override
  ConsumerState<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends ConsumerState<_OrdersList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(ordersListProvider(widget.status).notifier).loadMore().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ordersListProvider(widget.status);
    final state = ref.watch(provider);
    final label = widget.status?.label.toLowerCase();

    return state.when(
      loading: () => const SkeletonList(),
      error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(provider)),
      data: (data) {
        Future<void> refresh() => ref.read(provider.notifier).reload();
        if (data.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: label == null ? 'No orders yet' : 'No $label orders',
                    message: 'New orders appear here the moment customers place them. Pull down to refresh.',
                  ),
                ),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView.separated(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: data.items.length + (data.hasMore || data.loadingMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index >= data.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
                    );
                  }
                  final order = data.items[index];
                  return OrderCard(order: order, onOpen: () => context.push('/orders/${order.id}'));
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
