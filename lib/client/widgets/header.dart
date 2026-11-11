import 'package:flutter/material.dart';

import '../client_theme.dart';

/// Tailwind breakpoints the website's layout switches at.
const smWidth = 640.0;
const lgWidth = 1024.0;

/// `px-4 sm:px-6 lg:px-8`.
double pagePadding(double width) => width >= lgWidth ? 32 : (width >= smWidth ? 24 : 16);

/// The website's Navbar: the "New" banner, then the logo row (logo, name,
/// "MARKET" badge and tagline) with Tomorrow's Specials, Nearby Map, basket,
/// dark mode, saved dishes and Sign In. Below 1024 px the shortcuts move to
/// their own row under the logo, as on the website.
class MarketHeader extends StatelessWidget {
  const MarketHeader({super.key, required this.cartCount, required this.onCart, required this.onSignIn, required this.onLink, required this.onTheme, this.signedInName, this.unreadNotifications, this.onNotifications});

  final int cartCount;
  final VoidCallback onCart;
  final VoidCallback onSignIn;
  final String? signedInName;
  final VoidCallback onTheme;

  /// Unread notifications (null while signed out: no bell).
  final int? unreadNotifications;
  final VoidCallback? onNotifications;

  /// A shortcut the app doesn't have yet ("Tomorrow's Specials", "Nearby Map", "Saved").
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final sm = width >= smWidth;
    final lg = width >= lgWidth;
    final gap = lg ? 12.0 : (sm ? 8.0 : 6.0);
    return Container(
      decoration: BoxDecoration(
        color: K.header,
        border: Border(bottom: BorderSide(color: K.stone200.withValues(alpha: 0.8))),
        boxShadow: K.shadowSm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _banner(top),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pagePadding(width)),
                child: Column(
                  children: [
                    SizedBox(
                      height: sm ? 80 : 64,
                      child: Row(
                        children: [
                          _logo(width),
                          const Spacer(),
                          if (lg) ...[
                            _pill(Icons.calendar_month_outlined, "Tomorrow's Specials", () => onLink("Tomorrow's Specials")),
                            SizedBox(width: gap),
                            _pill(Icons.map_outlined, 'Nearby Map', () => onLink('Nearby Map')),
                            SizedBox(width: gap),
                          ],
                          _cartButton(),
                          SizedBox(width: gap),
                          if (unreadNotifications != null) ...[_bell(), SizedBox(width: gap)],
                          _squareButton(K.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, K.dark ? 'Switch to light mode' : 'Switch to dark mode', onTheme,color: K.stone600, border: K.stone200),
                          if (lg) ...[
                            SizedBox(width: gap),
                            _squareButton(Icons.favorite_border, 'Saved dishes', () => onLink('Saved dishes'), color: K.rose600, border: K.gray200),
                          ],
                          SizedBox(width: gap),
                          _signIn(),
                        ],
                      ),
                    ),
                    if (!lg)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _pill(Icons.calendar_month_outlined, "Tomorrow's Specials", () => onLink("Tomorrow's Specials")),
                              const SizedBox(width: 8),
                              _pill(Icons.map_outlined, 'Nearby Map', () => onLink('Nearby Map')),
                              const SizedBox(width: 8),
                              _pill(Icons.favorite_border, 'Saved', () => onLink('Saved dishes'), saved: true),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(double top) => K.light(() => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(16, 6 + top, 16, 6),
    decoration: BoxDecoration(
      gradient: K.bannerGradient,
      border: Border(bottom: BorderSide(color: K.brown750.withValues(alpha: 0.5))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: K.fillBrown700,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0xFF7A3A19).withValues(alpha: 0.5)),
          ),
          child: Text(
            'NEW',
            style: kText(10, weight: FontWeight.w700, color: K.brown200, spacing: 0.6),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            "Empowering Kigali's Home Cooks & Kitchens! Order immediate meals or pre-order tomorrow's home specials.",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kText(12, color: K.brown100),
          ),
        ),
      ],
    ),
  ));

  /// Logo tile; the name from 420 px, the tagline from 640 px, "MARKET" from 1024 px.
  Widget _logo(double width) {
    final sm = width >= smWidth;
    final size = sm ? 44.0 : 40.0;
    final nameSize = sm ? 20.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: K.logoGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x402B1206), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1)],
          ),
          child: Icon(Icons.local_dining, size: sm ? 24 : 20, color: K.light(() => K.brown100)),
        ),
        if (width >= 420) ...[
          SizedBox(width: sm ? 12 : 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Kitchen', style: kText(nameSize, weight: w900, spacing: -0.3)),
                  const SizedBox(width: 6),
                  Text(
                    'Link',
                    style: kText(nameSize, weight: w900, color: K.brown500, spacing: -0.3),
                  ),
                  if (width >= lgWidth) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: K.brown100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: K.brown200),
                      ),
                      child: Text(
                        'MARKET',
                        style: kText(10, weight: FontWeight.w600, color: K.brown850),
                      ),
                    ),
                  ],
                ],
              ),
              if (sm) Text('Any Cook · Any Food · Anywhere', style: kText(11, color: K.stone500)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cartButton() => Semantics(
    button: true,
    label: cartCount > 0 ? 'View cart, $cartCount ${cartCount == 1 ? 'item' : 'items'}' : 'View cart',
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        _squareButton(Icons.shopping_bag_outlined, null, onCart, color: K.brown600, border: K.brown200, background: K.brown50),
        if (cartCount > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [K.brown900, K.fillBrown700]),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$cartCount',
                style: kText(10, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
      ],
    ),
  );

  /// The notifications bell with its unread count.
  Widget _bell() => Stack(
    clipBehavior: Clip.none,
    children: [
      _squareButton(Icons.notifications_none, 'Notifications', onNotifications ?? () {}, color: K.stone600, border: K.stone200),
      if ((unreadNotifications ?? 0) > 0)
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: K.red500, borderRadius: BorderRadius.circular(99)),
            child: Text(unreadNotifications! > 9 ? '9+' : '$unreadNotifications', style: kText(10, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
    ],
  );

  /// A `rounded-xl border` icon button (basket, dark mode, saved dishes).
  Widget _squareButton(IconData icon, String? label, VoidCallback onTap, {required Color color, required Color border, Color? background}) {
    final button = Material(
      color: background ?? K.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 16, color: color)),
      ),
    );
    return label == null
        ? button
        : Tooltip(
            message: label,
            child: Semantics(button: true, label: label, child: button),
          );
  }

  Widget _signIn() => Container(
    height: 34,
    decoration: BoxDecoration(gradient: K.buttonGradient, borderRadius: BorderRadius.circular(12), boxShadow: K.brownShadow),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSignIn,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 14, color: K.light(() => K.brown300)),
              const SizedBox(width: 6),
              Text(
                signedInName ?? 'Sign In',
                style: kText(12, weight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// `px-3 py-2 rounded-xl text-xs font-bold` shortcut pill.
  Widget _pill(IconData icon, String label, VoidCallback onTap, {bool saved = false}) {
    final fg = saved ? K.rose600 : K.brown850;
    return Material(
      color: saved ? K.surface : K.brown50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: saved ? K.gray200 : K.brown200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: saved ? K.rose600 : K.brown600),
              const SizedBox(width: 6),
              Text(
                label,
                style: kText(12, weight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
