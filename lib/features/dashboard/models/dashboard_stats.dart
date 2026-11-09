import '../../../core/network/json.dart';

/// `GET /vendor/dashboard`. Every figure comes from the backend; the app does
/// no money arithmetic of its own.
class DashboardStats {
  const DashboardStats({
    this.todayOrders = 0,
    this.newOrders = 0,
    this.preparingOrders = 0,
    this.readyOrders = 0,
    this.completedOrdersTotal = 0,
    this.completedToday = 0,
    this.cancelledOrders = 0,
    this.todaySalesRwf = 0,
    this.totalSalesRwf = 0,
    this.availableBalanceRwf = 0,
    this.pendingBalanceRwf = 0,
    this.netEarnedRwf = 0,
    this.withdrawnRwf = 0,
    this.commissionPercent = 0,
  });

  factory DashboardStats.fromJson(Json json) => DashboardStats(
        todayOrders: intOf(json['today_orders']),
        newOrders: intOf(json['new_orders']),
        preparingOrders: intOf(json['preparing_orders']),
        readyOrders: intOf(json['ready_orders']),
        completedOrdersTotal: intOf(json['completed_orders_total']),
        completedToday: intOf(json['completed_orders']),
        cancelledOrders: intOf(json['cancelled_orders']),
        todaySalesRwf: intOf(json['today_sales_rwf']),
        totalSalesRwf: intOf(json['total_sales_rwf']),
        availableBalanceRwf: intOf(json['available_balance_rwf']),
        pendingBalanceRwf: intOf(json['pending_balance_rwf']),
        netEarnedRwf: intOf(json['net_earned_rwf']),
        withdrawnRwf: intOf(json['withdrawn_rwf']),
        commissionPercent: doubleOrNull(json['commission_percent']) ?? 0,
      );

  final int todayOrders;
  final int newOrders;
  final int preparingOrders;
  final int readyOrders;
  final int completedOrdersTotal;
  final int completedToday;
  final int cancelledOrders;
  final int todaySalesRwf;
  final int totalSalesRwf;
  final int availableBalanceRwf;
  final int pendingBalanceRwf;
  final int netEarnedRwf;
  final int withdrawnRwf;
  final double commissionPercent;
}
