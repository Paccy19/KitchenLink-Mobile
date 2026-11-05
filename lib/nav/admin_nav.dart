import 'package:flutter/material.dart';

/// One page of the admin app. Each needs one permission; a team member only
/// sees, and can only open, the pages their role allows. `owner` pages are
/// for the owner (super admin) only. Same table as the website's adminNav.js.
class AdminPage {
  const AdminPage(this.id, this.label, this.icon, {this.permission, this.owner = false});

  final String id;
  final String label;
  final IconData icon;
  final String? permission;
  final bool owner;

  bool allowed({required bool Function(String) can, required bool isOwner}) =>
      (!owner || isOwner) && (permission == null || can(permission!));
}

class AdminSection {
  const AdminSection(this.id, this.label, this.pages);

  final String id;
  final String label;
  final List<AdminPage> pages;
}

class Pages {
  static const overview = AdminPage('overview', 'Overview', Icons.dashboard_outlined, permission: 'dashboard:read');
  static const orders = AdminPage('orders', 'Orders', Icons.assignment_outlined, permission: 'orders:read');
  static const deliveries = AdminPage('deliveries', 'Deliveries', Icons.delivery_dining_outlined, permission: 'deliveries:read');
  static const vendors = AdminPage('vendors', 'Vendors', Icons.storefront_outlined, permission: 'vendors:read');
  static const drivers = AdminPage('drivers', 'Delivery Workers', Icons.pedal_bike_outlined, permission: 'drivers:read');
  static const users = AdminPage('users', 'Customers', Icons.people_outline, permission: 'users:read');
  static const categories = AdminPage('categories', 'Categories', Icons.sell_outlined, permission: 'categories:read');
  static const complaints = AdminPage('complaints', 'Support & Complaints', Icons.report_outlined, permission: 'complaints:read');
  static const chats = AdminPage('chats', 'Customer–Kitchen Chats', Icons.forum_outlined, permission: 'chats:read');
  static const payments = AdminPage('payments', 'Payments', Icons.credit_card_outlined, permission: 'payments:read');
  static const payouts = AdminPage('payouts', 'Payouts', Icons.account_balance_wallet_outlined, permission: 'payouts:read');
  static const refunds = AdminPage('refunds', 'Refunds', Icons.replay_outlined, permission: 'refunds:read');
  static const books = AdminPage('books', 'Platform Books', Icons.menu_book_outlined, permission: 'wallet:read');
  static const analytics = AdminPage('analytics', 'Analytics', Icons.bar_chart_outlined, permission: 'analytics:read');
  static const team = AdminPage('team', 'Team', Icons.groups_outlined, permission: 'team:manage', owner: true);
  static const platform = AdminPage('platform', "Owner's Money", Icons.account_balance_outlined, owner: true);
  static const audit = AdminPage('audit', 'Audit Log', Icons.receipt_long_outlined, permission: 'actions:read', owner: true);

  // Settings: each option is its own page.
  static const settingsProfile = AdminPage('settings/profile', 'Profile', Icons.person_outline);
  static const settingsRules = AdminPage('settings/rules', 'Delivery & pickup rules', Icons.radar_outlined, permission: 'dashboard:read');
  static const settingsBanks = AdminPage('settings/bank-accounts', 'Bank account numbers', Icons.account_balance_outlined, permission: 'payouts:read');
  static const settingsFees = AdminPage('settings/delivery-fees', 'Delivery fee by distance', Icons.route_outlined, permission: 'deliveries:read');
  static const settingsTiming = AdminPage('settings/delivery-timing', 'Delivery timing', Icons.timer_outlined, permission: 'deliveries:read');

  static const settings = [settingsProfile, settingsRules, settingsBanks, settingsFees, settingsTiming];

  static const sections = [
    AdminSection('overview', 'Overview', [overview]),
    AdminSection('operations', 'Operations', [orders, deliveries, vendors, drivers, users, categories]),
    AdminSection('support', 'Support', [complaints, chats]),
    AdminSection('finance', 'Finance', [payments, payouts, refunds, books]),
    AdminSection('reports', 'Reports', [analytics]),
    AdminSection('owner', 'Owner', [team, platform, audit]),
    AdminSection('account', 'Account', settings),
  ];

  static AdminPage? byId(String id) {
    for (final section in sections) {
      for (final page in section.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }
}

/// A page plus deep-link parameters (e.g. `order` to open that order).
class AdminRoute {
  const AdminRoute(this.page, [this.params = const {}]);

  final AdminPage page;
  final Map<String, String> params;

  /// Parses a website link such as `/admin-dashboard/orders?order=123`, as
  /// carried by notifications, into the matching page.
  static AdminRoute fromLink(String? link) {
    if (link == null || link.isEmpty) return const AdminRoute(Pages.overview);
    final uri = Uri.tryParse(link);
    if (uri == null) return const AdminRoute(Pages.overview);
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    path = path.replaceFirst(RegExp(r'^/admin-dashboard/?'), '');
    if (path.isEmpty) return AdminRoute(Pages.overview, uri.queryParameters);
    if (path == 'settings') path = Pages.settingsProfile.id;
    return AdminRoute(Pages.byId(path) ?? Pages.overview, uri.queryParameters);
  }
}
