import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/json.dart';
import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../wallet/application/wallet_providers.dart';
import '../models/order.dart';

class OrdersListState {
  const OrdersListState({required this.items, required this.meta, this.loadingMore = false});

  final List<VendorOrder> items;
  final PageMeta meta;
  final bool loadingMore;

  bool get hasMore => meta.hasMore;

  OrdersListState copyWith({List<VendorOrder>? items, PageMeta? meta, bool? loadingMore}) =>
      OrdersListState(
        items: items ?? this.items,
        meta: meta ?? this.meta,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Orders of one status (null = all), newest first, loaded page by page.
///
/// While open it refreshes the first page every 10 seconds and merges it into
/// what is already loaded, so new orders appear without losing the scroll
/// position or the older pages.
class OrdersListNotifier extends AsyncNotifier<OrdersListState> {
  OrdersListNotifier(this.status);

  final OrderStatus? status;
  static const int pageSize = 20;

  @override
  Future<OrdersListState> build() {
    keepFresh(ref, const Duration(seconds: 10), refreshFirstPage);
    return _loadFirstPage();
  }

  Future<OrdersListState> _loadFirstPage() async {
    final page = await ref.read(ordersRepositoryProvider).list(status: status, limit: pageSize);
    return OrdersListState(items: page.orders, meta: page.meta);
  }

  /// Pull-to-refresh: start over from the first page.
  Future<void> reload() async {
    final fresh = await _loadFirstPage();
    if (ref.mounted) state = AsyncData(fresh);
  }

  /// Background refresh of the first page, merged into the current list.
  Future<void> refreshFirstPage() async {
    final current = state.value;
    if (current == null) return;
    final fresh = await _loadFirstPage();
    if (!ref.mounted) return;
    state = AsyncData(
      current.copyWith(items: mergeOrders(current.items, fresh.items), meta: PageMeta(
        page: current.meta.page,
        limit: current.meta.limit,
        total: fresh.meta.total,
      )),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(ordersRepositoryProvider)
          .list(status: status, page: current.meta.page + 1, limit: pageSize);
      if (!ref.mounted) return;
      final known = {for (final order in current.items) order.id};
      state = AsyncData(OrdersListState(
        items: [...current.items, ...page.orders.where((order) => !known.contains(order.id))],
        meta: page.meta,
      ));
    } catch (_) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Applies an order the API just returned: updated in place, or removed when
  /// it no longer belongs to this status.
  void apply(VendorOrder order) {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere((item) => item.id == order.id);
    if (index < 0) return;
    final items = [...current.items];
    if (status != null && order.status != status) {
      items.removeAt(index);
    } else {
      items[index] = order;
    }
    state = AsyncData(current.copyWith(items: items));
  }
}

/// Fresh first page [fresh] + the older orders of [previous] that the first
/// page does not cover. Orders newer than the page's oldest one that are no
/// longer in it (they changed status) are dropped.
List<VendorOrder> mergeOrders(List<VendorOrder> previous, List<VendorOrder> fresh) {
  if (fresh.isEmpty) return fresh;
  final freshIds = {for (final order in fresh) order.id};
  final oldest = fresh.last.createdAt;
  final older = previous.where((order) {
    if (freshIds.contains(order.id)) return false;
    final created = order.createdAt;
    return oldest != null && created != null && created.isBefore(oldest);
  });
  return [...fresh, ...older];
}

final ordersListProvider = AsyncNotifierProvider.autoDispose
    .family<OrdersListNotifier, OrdersListState, OrderStatus?>(OrdersListNotifier.new);

/// One order, refreshed every 8 seconds while its screen is open.
class OrderDetailNotifier extends PolledNotifier<VendorOrder> {
  OrderDetailNotifier(this.id);
  final String id;

  @override
  Duration? get pollInterval => const Duration(seconds: 8);

  @override
  Future<VendorOrder> fetch() => ref.read(ordersRepositoryProvider).detail(id);
}

final orderDetailProvider = AsyncNotifierProvider.autoDispose
    .family<OrderDetailNotifier, VendorOrder, String>(OrderDetailNotifier.new);

/// The writes on an order. Every one is a real API call: nothing is shown as
/// done until the backend confirms it.
class OrderActions {
  OrderActions(this._ref);
  final Ref _ref;

  Future<VendorOrder> advance(String id, OrderStatus status, {String? note}) async {
    final order = await _ref.read(ordersRepositoryProvider).updateStatus(id, status, note: note);
    _afterWrite(order);
    return order;
  }

  Future<VendorOrder> collect(String id, String code) async {
    final order = await _ref.read(ordersRepositoryProvider).collect(id, code);
    _afterWrite(order);
    return order;
  }

  void _afterWrite(VendorOrder order) {
    if (_ref.exists(orderDetailProvider(order.id))) {
      _ref.read(orderDetailProvider(order.id).notifier).put(order);
    }
    _ref.invalidate(ordersListProvider);
    _ref.invalidate(dashboardProvider);
    // Completing an order credits the wallet.
    _ref.invalidate(walletProvider);
  }
}

final orderActionsProvider = Provider<OrderActions>(OrderActions.new);

/// A new order that arrived while the app was open.
class NewOrderAlert {
  const NewOrderAlert(this.order);
  final VendorOrder order;
}

/// Watches for new orders: polls the kitchen's `new` orders and reports the
/// ones it has not seen before. The first load is only the baseline.
class NewOrderWatcher extends Notifier<NewOrderAlert?> {
  final Set<String> _seen = {};
  bool _baselined = false;

  @override
  NewOrderAlert? build() {
    keepFresh(ref, const Duration(seconds: 10), check);
    unawaited(check().catchError((_) {}));
    return null;
  }

  Future<void> check() async {
    final page = await ref.read(ordersRepositoryProvider).list(status: OrderStatus.newOrder, limit: 20);
    if (!ref.mounted) return;
    final unseen = page.orders.where((order) => !_seen.contains(order.id)).toList();
    _seen.addAll(page.orders.map((order) => order.id));
    if (!_baselined) {
      _baselined = true;
      return;
    }
    if (unseen.isNotEmpty) {
      ref.invalidate(dashboardProvider);
      state = NewOrderAlert(unseen.first);
    }
  }
}

final newOrderWatcherProvider =
    NotifierProvider.autoDispose<NewOrderWatcher, NewOrderAlert?>(NewOrderWatcher.new);
