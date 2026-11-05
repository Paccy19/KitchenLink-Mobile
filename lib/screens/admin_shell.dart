import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../nav/admin_nav.dart';
import '../state/admin_session.dart';
import '../state/theme_controller.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'notification_bell.dart';
import 'pages/analytics_page.dart';
import 'pages/audit_page.dart';
import 'pages/books_page.dart';
import 'pages/categories_page.dart';
import 'pages/chats_page.dart';
import 'pages/complaints_page.dart';
import 'pages/deliveries_page.dart';
import 'pages/drivers_page.dart';
import 'pages/orders_page.dart';
import 'pages/overview_page.dart';
import 'pages/payments_page.dart';
import 'pages/payouts_page.dart';
import 'pages/platform_wallet_page.dart';
import 'pages/refunds_page.dart';
import 'pages/settings_pages.dart';
import 'pages/team_page.dart';
import 'pages/users_page.dart';
import 'pages/vendors_page.dart';

/// Lets any page open another one (e.g. Overview → Orders, a late pickup → its order).
class ShellNavigator {
  const ShellNavigator(this.go);

  final void Function(AdminRoute route) go;
}

void openMarketplace() => launchUrl(Uri.parse('${kMarketplaceUrl.replaceAll(RegExp(r'/+$'), '')}/vendors'), mode: LaunchMode.externalApplication);

/// The signed-in admin panel, laid out like the website's AdminLayout: a
/// header with the menu button, "Admin Panel", theme toggle, bell and account
/// menu; a side menu with only the pages this admin's role allows.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  AdminRoute? route;
  // Bumped on every navigation so the same page reopens with new parameters.
  int visit = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The phone may have slept past the idle limit.
    if (state == AppLifecycleState.resumed) context.read<AdminSession>().checkIdle();
  }

  List<AdminSection> _sections(AdminSession session) => [
    for (final section in Pages.sections)
      AdminSection(section.id, section.label, [
        for (final page in section.pages)
          if (page.allowed(can: session.can, isOwner: session.isOwner)) page,
      ]),
  ].where((section) => section.pages.isNotEmpty).toList();

  void go(AdminRoute next) {
    setState(() {
      route = next;
      visit++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final p = Palette.of(context);
    final sections = _sections(session);
    final firstPage = sections.isEmpty ? Pages.settingsProfile : sections.first.pages.first;
    var current = route ?? AdminRoute(firstPage);
    // Still on the default (publicly known) password: the server refuses every
    // other admin action, so only the page to change it opens.
    if (session.usesDefaultPassword) current = const AdminRoute(Pages.settingsProfile);
    final blocked = !current.page.allowed(can: session.can, isOwner: session.isOwner);

    final docked = MediaQuery.sizeOf(context).width >= 1024;

    return Provider.value(
      value: ShellNavigator(go),
      child: Listener(
        onPointerDown: (_) => session.touch(),
        behavior: HitTestBehavior.translucent,
        child: Row(
          children: [
            // From 1024px the side menu stays open beside the page (`lg:flex`).
            if (docked) _Drawer(docked: true, sections: sections, current: current.page, onSelect: (page) => go(AdminRoute(page))),
            Expanded(
              child: Scaffold(
                key: scaffoldKey,
                backgroundColor: p.page,
                appBar: _Header(onMenu: docked ? null : () => scaffoldKey.currentState?.openDrawer()),
                drawer: docked
                    ? null
                    : _Drawer(
                        sections: sections,
                        current: current.page,
                        onSelect: (page) {
                          Navigator.pop(context);
                          go(AdminRoute(page));
                        },
                      ),
                body: Column(
                  children: [
                    if (session.usesDefaultPassword)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: InkWell(
                          onTap: () => go(const AdminRoute(Pages.settingsProfile)),
                          child: const Note(
                            'You are using the default admin password. Change it below to unlock the admin panel.',
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                      ),
                    Expanded(
                      child: blocked
                          ? _Blocked(
                              page: current.page,
                              role: session.admin?['role_label']?.toString() ?? session.role ?? '',
                              onHome: () => go(AdminRoute(firstPage)),
                            )
                          : KeyedSubtree(key: ValueKey('${current.page.id}#$visit'), child: _pageFor(current)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageFor(AdminRoute route) {
    final p = route.params;
    return switch (route.page.id) {
      'overview' => const OverviewPage(),
      'orders' => OrdersPage(focusId: p['order']),
      'deliveries' => DeliveriesPage(initialTab: p['tab']),
      'vendors' => VendorsPage(focusId: p['vendor']),
      'drivers' => DriversPage(focusId: p['driver']),
      'users' => const UsersPage(),
      'categories' => const CategoriesPage(),
      'complaints' => ComplaintsPage(focusId: p['complaint']),
      'chats' => ChatsPage(focusId: p['chat']),
      'payments' => const PaymentsPage(),
      'payouts' => PayoutsPage(focusId: p['payout']),
      'refunds' => RefundsPage(focusId: p['refund']),
      'books' => const BooksPage(),
      'analytics' => const AnalyticsPage(),
      'team' => const TeamPage(),
      'platform' => PlatformWalletPage(sweepAmount: int.tryParse(p['sweep'] ?? '') ?? 0),
      'audit' => const AuditPage(),
      'settings/profile' => const ProfileSettingsPage(),
      'settings/rules' => const DeliveryRulesPage(),
      'settings/bank-accounts' => const BankFormatsPage(),
      'settings/delivery-fees' => const DeliveryFeesPage(),
      'settings/delivery-timing' => const DeliveryTimingPage(),
      _ => const OverviewPage(),
    };
  }
}

/// `w-10 h-10 rounded-xl` header button.
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.child, required this.onTap, this.outlined = false, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final bool outlined;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final button = Material(
      color: outlined ? p.card : p.stone100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: outlined ? BorderSide(color: p.border) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// `sticky top-0 bg-white/95 border-b px-4 py-3`.
class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header({required this.onMenu});

  final VoidCallback? onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(65);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = context.watch<ThemeController>();
    return Material(
      color: p.header.withValues(alpha: 0.95),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 65,
          padding: EdgeInsets.symmetric(horizontal: isSm(context) ? 24 : 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.8))),
          ),
          child: Row(
            children: [
              // `lg:hidden` menu button.
              if (onMenu != null) ...[
                HeaderButton(
                  onTap: onMenu!,
                  tooltip: 'Open menu',
                  child: Icon(Icons.menu, size: 20, color: p.textSecondary),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Panel',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: isSm(context) ? 18 : 16, fontWeight: FontWeight.w800, color: p.text),
                    ),
                    // `hidden sm:block`.
                    if (isSm(context))
                      Text(
                        'Marketplace operations & control',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.faint),
                      ),
                  ],
                ),
              ),
              HeaderButton(
                outlined: true,
                tooltip: theme.isDark ? 'Switch to light mode' : 'Switch to dark mode',
                onTap: theme.toggle,
                child: Icon(theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 16, color: p.textSecondary),
              ),
              const SizedBox(width: 8),
              const NotificationBell(),
              const SizedBox(width: 8),
              const _AccountMenu(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatar button (`p-1 rounded-xl bg-stone-50 border`) and its menu, like
/// the website's RoleAccountMenu for admins.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final session = context.watch<AdminSession>();
    final name = (session.admin?['name'] ?? 'Administrator').toString();
    final email = (session.admin?['email'] ?? 'Admin account').toString();
    final initials = name.split(' ').where((s) => s.isNotEmpty).map((s) => s[0]).take(2).join().toUpperCase();
    final go = context.read<ShellNavigator>().go;

    PopupMenuItem<String> item(String value, IconData icon, String label, {bool danger = false}) => PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: danger ? AppColors.red500 : p.faint),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: danger ? AppColors.red600 : p.textSecondary)),
        ],
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'Account menu',
      offset: const Offset(0, 48),
      color: p.card,
      constraints: const BoxConstraints.tightFor(width: 240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.divider),
      ),
      onSelected: (value) => switch (value) {
        'dashboard' => go(const AdminRoute(Pages.overview)),
        'settings' => go(const AdminRoute(Pages.settingsProfile)),
        'marketplace' => openMarketplace(),
        _ => session.logout(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          height: 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
              ),
              Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        item('dashboard', Icons.dashboard_outlined, 'Admin Dashboard'),
        item('settings', Icons.settings_outlined, 'Panel Settings'),
        item('marketplace', Icons.storefront_outlined, 'Visit marketplace'),
        const PopupMenuDivider(height: 1),
        item('logout', Icons.logout, 'Sign Out', danger: true),
      ],
      child: Container(
        // `p-1 sm:pl-1 sm:pr-3` with the chevron from 640px.
        padding: EdgeInsets.fromLTRB(4, 4, isSm(context) ? 12 : 4, 4),
        decoration: BoxDecoration(
          color: p.stone50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF111827), Color(0xFF0B1220)]),
                border: Border.all(color: const Color(0xFFD6D3D1), width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            if (isSm(context)) ...[const SizedBox(width: 8), Icon(Icons.keyboard_arrow_down, size: 14, color: p.faint)],
          ],
        ),
      ),
    );
  }
}

/// The side menu (`w-72 p-5`): brand, "Signed in as", the sections, then
/// "Visit marketplace" and "Sign out".
class _Drawer extends StatefulWidget {
  const _Drawer({required this.sections, required this.current, required this.onSelect, this.docked = false});

  final List<AdminSection> sections;
  final AdminPage current;
  final ValueChanged<AdminPage> onSelect;

  /// Always shown beside the page (`hidden lg:flex` aside) instead of sliding in.
  final bool docked;

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  // Like the website (`openMenus[item.to] ?? inside`): the Settings dropdown
  // is open while a settings page is showing, until the admin toggles it.
  bool? _settingsToggled;

  bool get _insideSettings => widget.current.id.startsWith('settings/');

  bool get settingsOpen => _settingsToggled ?? _insideSettings;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final admin = session.admin ?? const {};
    final p = Palette.of(context);
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.docked)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close menu',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, size: 20, color: p.muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(gradient: AppColors.brandDiagonal, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.shadowMd),
                    child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KitchenLink',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text),
                      ),
                      Text(
                        'Admin Panel',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).brightness == Brightness.dark ? p.accent : const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.stone100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SIGNED IN AS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.55, color: p.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    admin['name']?.toString() ?? 'Admin',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text),
                  ),
                  Text(
                    admin['email']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.muted),
                  ),
                  if (admin['role'] != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.slate, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        (admin['role_label'] ?? admin['role'].toString().replaceAll('_', ' ')).toString().toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final section in widget.sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        section.label.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: p.faint),
                      ),
                    ),
                    if (section.id == 'account')
                      _settingsGroup(section)
                    else
                      for (final page in section.pages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _NavItem(icon: page.icon, label: page.label, active: page.id == widget.current.id, onTap: () => widget.onSelect(page)),
                        ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.divider)),
              ),
              child: Column(
                children: [
                  _NavItem(icon: Icons.open_in_new, iconSize: 16, label: 'Visit marketplace', active: false, onTap: openMarketplace),
                  const SizedBox(height: 4),
                  _NavItem(
                    icon: Icons.logout,
                    iconSize: 16,
                    label: 'Sign out',
                    active: false,
                    danger: true,
                    onTap: () {
                      if (!widget.docked) Navigator.pop(context);
                      session.logout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.docked) {
      // `w-72 border-r border-stone-200/80 bg-white p-5`.
      return Container(
        width: 288,
        decoration: BoxDecoration(
          color: p.header,
          border: Border(right: BorderSide(color: p.border.withValues(alpha: 0.8))),
        ),
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    return Drawer(width: (MediaQuery.of(context).size.width * 0.85).clamp(0, 288).toDouble(), shape: const RoundedRectangleBorder(), child: content);
  }

  /// "Settings" opens a dropdown; each option is its own page.
  Widget _settingsGroup(AdminSection section) {
    final p = Palette.of(context);
    final inside = _insideSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NavItem(
          icon: Icons.settings_outlined,
          label: 'Settings',
          active: inside && !settingsOpen,
          trailing: AnimatedRotation(
            turns: settingsOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: const Icon(Icons.expand_more, size: 16),
          ),
          onTap: () => setState(() => _settingsToggled = !settingsOpen),
        ),
        if (settingsOpen)
          Container(
            margin: const EdgeInsets.only(left: 24, top: 4),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: p.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final page in section.pages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: page.id == widget.current.id ? p.stone100 : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => widget.onSelect(page),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            page.label,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: page.id == widget.current.id ? p.text : p.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// `flex gap-3 px-4 py-2.5 rounded-xl text-sm font-bold`; the active page is
/// the dark gradient pill.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap, this.trailing, this.danger = false, this.iconSize = 18});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = active
        ? Colors.white
        : danger
        ? AppColors.red600
        : p.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: active ? AppColors.brandGradient : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: active ? AppColors.shadowMd : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: IconTheme(
              data: IconThemeData(color: color),
              child: Row(
                children: [
                  Icon(icon, size: iconSize),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Not part of your role": `max-w-lg mt-16 bg-white rounded-3xl border p-8 text-center`.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.page, required this.role, required this.onHome});

  final AdminPage page;
  final String role;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 16),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 512),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              Icon(Icons.lock_outline, size: 36, color: p.faint),
              const SizedBox(height: 12),
              Text(
                'Not part of your role',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text),
              ),
              const SizedBox(height: 4),
              Text(
                'Your role ($role) does not include ${page.label}. Ask the owner if you need it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.muted),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: onHome,
                child: Text(
                  'Go to my pages',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.accent, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
