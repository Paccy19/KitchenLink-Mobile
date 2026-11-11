import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../location.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/home_style.dart';
import '../widgets/home_bars.dart';
import '../customer_session.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../widgets/customer_auth_sheet.dart';
import '../widgets/notifications_sheet.dart';
import 'kitchen_screen.dart';
import 'kitchens_screen.dart';
import 'order_screen.dart';

import '../../root/role_switcher.dart';

/// One request's state (the website uses React Query for this).
class _Load<T> {
  T? data;
  Object? error;
  bool loading = false;
  int _token = 0;

  bool get pending => data == null && error == null;

  Future<void> run(Future<T> Function() fetch, VoidCallback changed) async {
    final token = ++_token;
    loading = true;
    changed();
    try {
      final value = await fetch();
      if (token != _token) return;
      data = value;
      error = null;
    } catch (e) {
      if (token != _token) return;
      error = e;
    } finally {
      if (token == _token) {
        loading = false;
        changed();
      }
    }
  }

  void reset() {
    _token++;
    data = null;
    error = null;
    loading = false;
  }
}

/// The marketplace homepage (the website's `/`: HomeFeed + LocationPrimer):
/// search → location → categories → kitchen types → "Top Deals Near You" →
/// "All Kitchens" → "Tomorrow's Specials" → "Popular Dishes Near You".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _feed = _Load<HomeFeed>();
  final _categories = _Load<List<Category>>();
  final _allVendors = _Load<VendorPage>();
  final _specials = _Load<List<SpecialEntry>>();
  final _offers = _Load<List<OfferDay>>();
  final _results = _Load<SearchResult>();

  late final ClientLocation _location;
  late final CustomerApi _api;
  late final RecentSearches _recent;

  List<String> _vendorTypes = [];
  String _query = '';
  Timer? _debounce;
  String _tab = 'dishes';
  bool _primerShown = false;
  String _locationKey = '';
  bool _scrolled = false;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _location = context.read<ClientLocation>();
    _api = context.read<CustomerApi>();
    _recent = context.read<RecentSearches>();
    _location.addListener(_onLocation);
    if (_location.restored) _onLocation();
    _scroll.addListener(() {
      final scrolled = _scroll.hasClients && _scroll.offset > 4;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _location.removeListener(_onLocation);
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onLocation() {
    if (!_location.restored) return;
    final key = '${_location.source}|${_location.lat.toStringAsFixed(4)}|${_location.lng.toStringAsFixed(4)}';
    if (key != _locationKey) {
      _locationKey = key;
      _loadAll();
      if (_query.isNotEmpty) _runSearch();
    }
    if (_location.primerOpen && !_primerShown) {
      _primerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showLocationPrimer(context, _location, onGpsUnavailable: _gpsUnavailable);
      });
    }
    _changed();
  }

  Future<void> _loadAll() => Future.wait([
    _loadFeed(),
    _allVendors.run(() => _api.allVendors(_location, _vendorTypes), _changed),
    _specials.run(() => _api.specials(_location), _changed),
    _offers.run(() => _api.offers(_location), _changed),
    if (_categories.data == null) _categories.run(_api.categories, _changed),
  ]);

  Future<void> _loadFeed() => _feed.run(() => _api.feed(_location, _vendorTypes), _changed);

  Future<void> _refresh() async {
    await _loadAll();
    if (mounted && _feed.error != null && _feed.data != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not refresh your feed. Check your connection.')));
    }
  }

  void _setTypes(List<String> types) {
    setState(() => _vendorTypes = types);
    _loadFeed();
    _allVendors.run(() => _api.allVendors(_location, _vendorTypes), _changed);
    if (_query.isNotEmpty) _runSearch();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = value.trim();
      if (trimmed == _query) return;
      setState(() {
        _query = trimmed;
        _tab = 'dishes';
      });
      if (trimmed.isEmpty) {
        _results.reset();
      } else {
        _runSearch();
      }
    });
  }

  void _suggest(String value) {
    _search.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _onQuery(value);
  }

  Future<void> _runSearch() async {
    final query = _query;
    await _results.run(() => _api.search(query, _location, _vendorTypes), _changed);
    final data = _results.data;
    // A newer search (or clearing the box) replaced this one: its results
    // must not pick the tab.
    if (data == null || !mounted || query != _query) return;
    // Searching for a kitchen by name opens the Kitchens tab; otherwise the
    // tab that actually has results.
    final term = query.toLowerCase();
    var tab = _tab;
    if (data.vendors.any((v) => v.name.toLowerCase().contains(term))) tab = 'kitchens';
    if (tab == 'dishes' && data.dishes.isEmpty && data.vendors.isNotEmpty) tab = 'kitchens';
    if (tab == 'kitchens' && data.vendors.isEmpty && data.dishes.isNotEmpty) tab = 'dishes';
    setState(() => _tab = tab);
  }

  /// A dish opens its details here, with a link to its kitchen (the website's DishCard).
  void _openDish(Dish dish) {
    if (dish.vendorId.isEmpty) return;
    showDishSheet(context, MenuDish.fromDish(dish), KitchenRef(id: dish.vendorId, name: dish.vendorName.isEmpty ? 'Kitchen' : dish.vendorName), showKitchenLink: true);
  }

  /// The header's moon / sun button: light or dark, remembered on the device.
  void _darkMode() => context.read<MarketTheme>().toggle((key, value) => const FlutterSecureStorage().write(key: key, value: value));

  Future<void> _signIn() async {
    final session = context.read<CustomerSession>();
    if (session.isSignedIn) {
      await _accountSheet(session);
      return;
    }
    await showSignInChooser(context, onCustomerSignIn: () async {
      final signedIn = await showCustomerSignIn(context);
      if (signedIn && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Welcome, ${context.read<CustomerSession>().firstName}!')));
      }
    });
  }

  Future<void> _accountSheet(CustomerSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: K.brown100, shape: BoxShape.circle),
                    child: Text(session.firstName.isEmpty ? '?' : session.firstName[0].toUpperCase(), style: kDisplay(26, color: K.brown700)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kDisplay(26)),
                        if (session.phone.isNotEmpty) Text(session.phone, style: kText(13, color: K.stone500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // The website's account menu, as one grouped list.
              Container(
                decoration: BoxDecoration(color: K.dark ? K.page : K.stone100.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, (icon, label, open)) in [
                      (Icons.person_outline_rounded, 'My profile', MarketNav.profile),
                      (Icons.receipt_long_outlined, 'Order history', MarketNav.orders),
                      (Icons.delivery_dining_outlined, 'Track order', MarketNav.track),
                      (Icons.chat_bubble_outline_rounded, 'Messages', MarketNav.messages),
                      (Icons.favorite_border_rounded, 'Saved dishes', MarketNav.wishlist),
                      (Icons.support_agent_rounded, 'Help & Support', (BuildContext c) => MarketNav.support(c)),
                    ].indexed) ...[
                      if (i > 0) Divider(height: 0.6, thickness: 0.6, indent: 52, color: K.stone200),
                      ListTile(
                        dense: true,
                        minTileHeight: 50,
                        leading: Icon(icon, color: K.brown600, size: 22),
                        title: Text(label, style: kText(15, weight: FontWeight.w600)),
                        trailing: Icon(Icons.chevron_right_rounded, color: K.stone400),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          open(context);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: K.dark ? K.page : K.stone100.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minTileHeight: 50,
                  leading: Icon(Icons.logout_rounded, color: K.rose600, size: 22),
                  title: Text('Sign out', style: kText(15, weight: FontWeight.w700, color: K.rose600)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await session.logout();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _gpsUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            gpsAvailable
                ? 'Could not get your location. Allow location access, or pick a neighbourhood.'
                : 'GPS location is not available in the phone app yet. Pick a neighbourhood instead.',
          ),
          action: SnackBarAction(
            label: 'Pick',
            onPressed: () => showLocationPicker(context, _location, onGpsUnavailable: _gpsUnavailable),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final customerSession = context.watch<CustomerSession>();
    context.watch<ClientLocation>();
    final width = MediaQuery.sizeOf(context).width;
    final pad = pagePadding(width);
    final visiting = RoleSwitcher.maybeOf(context)?.returnTo != null;
    final signedIn = customerSession.isSignedIn;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: K.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: K.page,
        // The list scrolls on under the frosted bars.
        extendBody: true,
        floatingActionButton: visiting ? const ReturnToRoleButton() : null,
        bottomNavigationBar: MarketBottomBar(
          cartCount: context.watch<Cart>().itemCount,
          onHome: _toTop,
          onKitchens: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
          onCart: () => MarketNav.cart(context),
          onSaved: () => MarketNav.wishlist(context),
          onAccount: _signIn,
          accountLabel: signedIn ? customerSession.firstName : 'Sign In',
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              color: K.brown700,
              backgroundColor: K.surface,
              edgeOffset: top + homeTopBarHeight,
              onRefresh: _refresh,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: EdgeInsets.only(top: top + homeTopBarHeight, bottom: 110 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_query.isEmpty) ...[
                              HomeGreeting(firstName: signedIn ? customerSession.firstName : null),
                              const SizedBox(height: 18),
                            ],
                            Row(
                              children: [
                                Expanded(child: MarketSearchBar(controller: _search, onChanged: _onQuery, recent: _recent)),
                                const SizedBox(width: 10),
                                Tooltip(
                                  message: 'Nearby Map',
                                  child: Material(
                                    color: K.strong,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => MarketNav.map(context),
                                      child: SizedBox(width: 50, height: 50, child: Icon(Icons.map_outlined, size: 22, color: K.onStrong)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_location.isUsingFallback && !_location.primerOpen && _query.isEmpty) _fallbackNotice(),
                            if (_query.isNotEmpty) _searchResults() else _feedBody(width),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: HomeTopBar(
                location: _location,
                scrolled: _scrolled,
                onLocation: () => showLocationPicker(context, _location, onGpsUnavailable: _gpsUnavailable),
                onTheme: _darkMode,
                unreadNotifications: signedIn ? context.watch<Notifications>().unread : null,
                onNotifications: () => showNotificationsSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  Widget _fallbackNotice() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.location_off_outlined, size: 14, color: K.gray400),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Showing kitchens around ${_location.label} — allow location or pick a neighbourhood for exact distances.',
            style: kText(11, weight: FontWeight.w400, color: K.gray400),
          ),
        ),
      ],
    ),
  );

  // ---- Feed ----------------------------------------------------------------

  /// The swipeable banner: Tomorrow's Specials, Big Event, the next offer day
  /// and the map (the reference's "Happy Weekend · 25% OFF" banner).
  List<PromoSlide> _promos(List<SpecialEntry> specials, List<OfferDay> offers) {
    String? photo(Vendor v) => _api.media(v.bannerUrl.isNotEmpty ? v.bannerUrl : v.avatarUrl);
    return [
      if (specials.isNotEmpty)
        PromoSlide(
          tag: "Tomorrow's Specials",
          title: "Pre-order tomorrow's dishes",
          text: '${specials.length} kitchen${specials.length == 1 ? '' : 's'} cooking something special',
          action: 'See specials',
          icon: Icons.soup_kitchen_outlined,
          imageUrl: photo(specials.first.vendor),
          onTap: () => MarketNav.specials(context),
        ),
      PromoSlide(
        tag: 'Big Event',
        title: 'Feeding 50+ guests?',
        text: 'Weddings, parties and meetings, cooked by local kitchens',
        action: 'Plan an event',
        icon: Icons.celebration_outlined,
        onTap: () => MarketNav.bigEvent(context),
      ),
      PromoSlide(
        tag: 'Nearby Map',
        title: 'Kitchens around you',
        text: 'See every open kitchen on the map',
        action: 'Open map',
        icon: Icons.map_outlined,
        onTap: () => MarketNav.map(context),
      ),
    ];
  }

  Widget _feedBody(double width) {
    final feed = _feed.data;
    if (_feed.pending || (_feed.loading && feed == null && _feed.error == null)) return _feedSkeleton();
    if (_feed.error != null && feed == null) {
      return ErrorCard(
        title: 'Your feed could not load',
        message: _feed.error.toString().isEmpty ? 'We could not reach the kitchens near you.' : _feed.error.toString(),
        onRetry: _loadFeed,
        retrying: _feed.loading,
      );
    }
    final categories = (feed?.categories.isNotEmpty ?? false) ? feed!.categories : (_categories.data ?? const <Category>[]);
    final specials = _specials.data ?? const <SpecialEntry>[];
    final offers = _offers.data ?? const <OfferDay>[];
    final featured = feed?.featuredVendors ?? const <Vendor>[];
    final dishes = feed?.popularDishes ?? const <Dish>[];
    final typeLabel = _vendorTypes.isNotEmpty;
    final orders = context.watch<Orders>();
    final lastOrder = context.watch<CustomerSession>().isSignedIn ? orders.orders.firstOrNull : null;
    const gap = 34.0;

    final pad = pagePadding(width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PromoCarousel(slides: _promos(specials, offers)),
        const SizedBox(height: gap),

        CategoryBar(
          categories: categories,
          loading: _categories.loading,
          media: _api.media,
          onSelect: (category) => MarketNav.kitchens(context, categoryId: category?.id, categoryName: category?.name, vendorTypes: _vendorTypes),
        ),
        const SizedBox(height: 16),
        KitchenTypeFilter(value: _vendorTypes, onChanged: _setTypes),

        // The latest order, with "Order again".
        if (lastOrder != null) ...[
          const SizedBox(height: gap),
          SectionHeader(title: 'Your last order', linkLabel: 'Order history', onLink: () => MarketNav.orders(context)),
          PreviousOrderCard(
            order: lastOrder,
            media: _api.media,
            onOpen: () => MarketNav.order(context, lastOrder.id),
            onReorder: () => reorderDishes(context, lastOrder),
          ),
        ],

        // Popular dishes, added straight to the basket.
        const SizedBox(height: gap),
        SectionHeader(title: 'Popular picks near you', linkLabel: 'Browse menus', onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes)),
        if (dishes.isEmpty && _feed.loading)
          _hScroll(const [DishCardSkeleton(), DishCardSkeleton(), DishCardSkeleton()], pad)
        else if (dishes.isEmpty)
          EmptyCard(
            icon: Icons.restaurant_menu,
            title: 'No dishes to show yet',
            message: 'Pick another neighbourhood or kitchen type to see what people are ordering.',
            actionLabel: 'Browse kitchens',
            onAction: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
          )
        else if (width >= smWidth)
          _columns(width, [for (final d in dishes) DishGridCard(dish: d, media: _api.media, onTap: () => _openDish(d))])
        else
          _hScroll([for (final d in dishes) DishGridCard(dish: d, width: 158, media: _api.media, onTap: () => _openDish(d))], pad),

        // The next offer day, as a banner.
        if (offers.isNotEmpty) ...[
          const SizedBox(height: gap),
          OfferBanner(offer: offers.first, media: _api.media, onTap: () => MarketNav.kitchen(context, offers.first.vendor.id)),
        ],

        // Featured / nearby kitchens.
        const SizedBox(height: gap),
        SectionHeader(title: 'Top kitchens near you', linkLabel: 'See all kitchens', onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes)),
        if (_feed.error != null)
          ErrorCard(onRetry: _loadFeed, retrying: _feed.loading)
        else if (featured.isEmpty && !_feed.loading)
          EmptyCard(
            icon: Icons.soup_kitchen_outlined,
            title: typeLabel ? 'No kitchens of this type nearby' : 'No kitchens nearby yet',
            message: typeLabel
                ? 'Try another kitchen type, or clear the filter to see every kitchen.'
                : 'Widen your search radius or switch neighbourhood to discover more kitchens.',
            actionLabel: 'Browse nearby kitchens',
            onAction: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
          )
        else
          _hScroll([
            for (final v in featured) VendorCard(vendor: v, tile: true, media: _api.media, showDistance: _location.isGps, onTap: () => MarketNav.kitchen(context, v.id)),
            if (_feed.loading && featured.isEmpty) ...const [VendorTileSkeleton(), VendorTileSkeleton(), VendorTileSkeleton()],
          ], pad),

        // Tomorrow's specials and the other offer days.
        if (specials.isNotEmpty || offers.length > 1) ...[
          const SizedBox(height: gap),
          SectionHeader(title: "Tomorrow's specials", subtitle: 'Order today, delivered tomorrow', linkLabel: 'See all specials', onLink: () => MarketNav.specials(context)),
          _hScroll([
            for (final s in specials) SpecialCard(entry: s, media: _api.media, onTap: () => MarketNav.kitchen(context, s.vendor.id), onPreorder: () => preorderSpecial(context, s)),
            for (final o in offers.skip(1)) OfferDayCard(offer: o, media: _api.media, onTap: () => MarketNav.kitchen(context, o.vendor.id)),
          ], pad),
        ],

        // All kitchens.
        const SizedBox(height: gap),
        SectionHeader(
          title: 'All kitchens',
          linkLabel: (_allVendors.data?.total ?? 0) > 0 ? 'See all ${_allVendors.data!.total}' : 'See all',
          onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
        ),
        if (_allVendors.pending)
          _hScroll(const [VendorTileSkeleton(), VendorTileSkeleton(), VendorTileSkeleton()], pad)
        else if (_allVendors.error != null)
          ErrorCard(onRetry: () => _allVendors.run(() => _api.allVendors(_location, _vendorTypes), _changed), retrying: _allVendors.loading)
        else
          _grid([
            for (final v in _allVendors.data!.vendors) VendorCard(vendor: v, media: _api.media, showDistance: _location.isGps, onTap: () => MarketNav.kitchen(context, v.id)),
          ], gap: 16),
      ],
    );
  }

  /// Two cards to a row on a phone (three from 640 px, four from 1024 px),
  /// each row as tall as its tallest card.
  Widget _columns(double width, List<Widget> cards) {
    final perRow = width >= 1024 ? 4 : (width >= 640 ? 3 : 2);
    return Column(
      children: [
        for (var start = 0; start < cards.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + perRow; i++) ...[
                  if (i > start) const SizedBox(width: 12),
                  Expanded(child: i < cards.length ? cards[i] : const SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// A sideways row of cards that runs to the screen edges (the page
  /// padding is undone, then put back inside the row).
  Widget _hScroll(List<Widget> children, [double bleed = 0]) => OverflowBox(
    alignment: Alignment.centerLeft,
    minWidth: MediaQuery.sizeOf(context).width,
    maxWidth: MediaQuery.sizeOf(context).width,
    fit: OverflowBoxFit.deferToChild,
    child: Transform.translate(
      offset: Offset(-bleed, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(bleed, 0, bleed, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 14), children[i]],
          ],
        ),
      ),
    ),
  );

  /// `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6`.
  Widget _grid(List<Widget> children, {double gap = 24}) => LayoutBuilder(
    builder: (context, constraints) {
      final w = MediaQuery.sizeOf(context).width;
      final columns = w >= 1024 ? 3 : (w >= 640 ? 2 : 1);
      final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
      );
    },
  );

  Widget _feedSkeleton() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SkeletonBox(height: 48, radius: 16),
      const SizedBox(height: 32),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(width: 12), const SkeletonBox(width: 80, height: 92, radius: 16)],
          ],
        ),
      ),
      const SizedBox(height: 32),
      const SkeletonBox(width: 192, height: 20),
      const SizedBox(height: 12),
      _hScroll(const [VendorTileSkeleton(), VendorTileSkeleton(), VendorTileSkeleton()]),
      const SizedBox(height: 32),
      const SkeletonBox(width: 224, height: 20),
      const SizedBox(height: 12),
      _hScroll(const [DishCardSkeleton(), DishCardSkeleton(), DishCardSkeleton()]),
    ],
  );

  // ---- Search results --------------------------------------------------------

  Widget _searchResults() {
    final heading = Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Results for '),
          TextSpan(
            text: '“$_query”',
            style: kText(18, weight: w900, color: K.brown700),
          ),
        ],
      ),
      style: kText(18, weight: w900),
    );
    final data = _results.data;
    if (data == null && _results.error == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          for (var i = 0; i < 4; i++) ...[const SizedBox(height: 16), const SkeletonBox(height: 108, radius: 24)],
        ],
      );
    }
    if (_results.error != null && data == null) {
      return ErrorCard(
        title: 'Search failed',
        message: _results.error.toString().isEmpty ? 'We could not run your search right now.' : _results.error.toString(),
        onRetry: _runSearch,
        retrying: _results.loading,
      );
    }
    final filter = KitchenTypeFilter(value: _vendorTypes, onChanged: _setTypes);
    if (data!.dishes.isEmpty && data.vendors.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filter,
          const SizedBox(height: 16),
          EmptyCard(
            icon: Icons.search_off,
            title: 'No matches for “$_query”',
            message: 'Double-check the spelling or try one of these popular cravings:',
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final s in searchSuggestions) SuggestionChip(label: 'Try “$s”', onTap: () => _suggest(s))],
                ),
                if (_vendorTypes.isNotEmpty)
                  TextButton(
                    onPressed: () => _setTypes(const []),
                    child: Text(
                      'Search all kitchen types',
                      style: kText(12, weight: FontWeight.w700, color: K.brown700),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    final dishesTab = _tab == 'dishes';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        const SizedBox(height: 20),
        filter,
        if (data.matchedTypes.isNotEmpty && _vendorTypes.isEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Text(
                'Kitchens of type',
                style: kText(12, weight: FontWeight.w400, color: K.stone500),
              ),
              for (final code in data.matchedTypes) VendorTypeBadge(code, small: true),
              Text(
                'are included.',
                style: kText(12, weight: FontWeight.w400, color: K.stone500),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: K.dark ? K.surface : K.stone100, borderRadius: BorderRadius.circular(13)),
          child: Row(
            children: [
              Expanded(child: _tabButton('Dishes', data.dishes.length, dishesTab, () => setState(() => _tab = 'dishes'))),
              Expanded(child: _tabButton('Kitchens', data.vendors.length, !dishesTab, () => setState(() => _tab = 'kitchens'))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (dishesTab)
          data.dishes.isEmpty
              ? EmptyCard(
                  icon: Icons.soup_kitchen_outlined,
                  title: 'No dishes matched',
                  message: 'Kitchens matched your search — check the Kitchens tab.',
                  actionLabel: 'Show kitchens',
                  onAction: () => setState(() => _tab = 'kitchens'),
                )
              : _grid([for (final d in data.dishes) DishRow(dish: d, media: _api.media, onTap: () => _openDish(d))], gap: 12)
        else
          data.vendors.isEmpty
              ? EmptyCard(
                  icon: Icons.soup_kitchen_outlined,
                  title: 'No kitchens matched',
                  message: 'Dishes matched your search — check the Dishes tab.',
                  actionLabel: 'Show dishes',
                  onAction: () => setState(() => _tab = 'dishes'),
                )
              : _grid([
                  for (final v in data.vendors) VendorCard(vendor: v, media: _api.media, showDistance: _location.isGps, onTap: () => MarketNav.kitchen(context, v.id)),
                ], gap: 20),
      ],
    );
  }

  Widget _tabButton(String label, int count, bool active, VoidCallback onTap) => Semantics(
    button: true,
    selected: active,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? K.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: active && !K.dark ? K.shadowSm : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14, weight: FontWeight.w700, color: active ? K.gray900 : K.stone500))),
              const SizedBox(width: 6),
              Text('$count', style: kText(13, weight: w900, color: active ? K.brown600 : K.stone400)),
            ],
          ),
        ),
      ),
    ),
  );
}
