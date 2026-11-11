import 'dart:async';

import 'package:flutter/material.dart';
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
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(session.name, style: kText(18, weight: w900, color: K.gray900)),
              if (session.phone.isNotEmpty) Text(session.phone, style: kText(12, color: K.stone500)),
              const SizedBox(height: 12),
              // The website's account menu.
              for (final (icon, label, open) in [
                (Icons.person_outline, 'My profile', MarketNav.profile),
                (Icons.receipt_long_outlined, 'Order history', MarketNav.orders),
                (Icons.delivery_dining_outlined, 'Track order', MarketNav.track),
                (Icons.chat_bubble_outline, 'Messages', MarketNav.messages),
                (Icons.favorite_border, 'Saved dishes', MarketNav.wishlist),
                (Icons.support_agent, 'Help & Support', (BuildContext c) => MarketNav.support(c)),
              ])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: K.brown700),
                  title: Text(label, style: kText(14, weight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right, color: K.stone400),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    open(context);
                  },
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await session.logout();
                },
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: K.brown700,
                  side: BorderSide(color: K.brown200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    return Scaffold(
      backgroundColor: K.page,
      // The list scrolls on under the raised basket button.
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
      body: Column(
        children: [
          HomeTopBar(
            location: _location,
            onLocation: () => showLocationPicker(context, _location, onGpsUnavailable: _gpsUnavailable),
            onTheme: _darkMode,
            onMap: () => MarketNav.map(context),
            unreadNotifications: signedIn ? context.watch<Notifications>().unread : null,
            onNotifications: () => showNotificationsSheet(context),
          ),
          Expanded(
            child: RefreshIndicator(
              color: K.brown700,
              onRefresh: _refresh,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pad, 6, pad, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MarketSearchBar(controller: _search, onChanged: _onQuery, recent: _recent),
                            const SizedBox(height: 12),
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
          ),
        ],
      ),
    );
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
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
  List<PromoSlide> _promos(List<SpecialEntry> specials, List<OfferDay> offers) => [
        if (specials.isNotEmpty)
          PromoSlide(
            tag: "Tomorrow's Specials",
            title: "Pre-order tomorrow's dishes",
            text: '${specials.length} kitchen${specials.length == 1 ? '' : 's'} cooking something special',
            action: 'See specials',
            emoji: '🍲',
            onTap: () => MarketNav.specials(context),
          ),
        PromoSlide(
          tag: 'Big Event',
          title: 'Feeding 50+ guests?',
          text: 'Weddings, parties and meetings, cooked by local kitchens',
          action: 'Plan an event',
          emoji: '🎉',
          onTap: () => MarketNav.bigEvent(context),
        ),
        if (offers.isNotEmpty)
          PromoSlide(
            tag: 'Offer day',
            title: offers.first.title,
            text: offers.first.vendor.name,
            action: 'See offer',
            emoji: '🎁',
            onTap: () => MarketNav.kitchen(context, offers.first.vendor.id),
          ),
        PromoSlide(
          tag: 'Nearby Map',
          title: 'Kitchens around you',
          text: 'See every open kitchen on the map',
          action: 'Open map',
          emoji: '🗺️',
          onTap: () => MarketNav.map(context),
        ),
      ];

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
    const gap = 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PromoCarousel(slides: _promos(specials, offers)),
        const SizedBox(height: 22),

        CategoryBar(
          categories: categories,
          loading: _categories.loading,
          media: _api.media,
          onSelect: (category) => MarketNav.kitchens(context, categoryId: category?.id, categoryName: category?.name, vendorTypes: _vendorTypes),
        ),
        const SizedBox(height: 14),
        KitchenTypeFilter(value: _vendorTypes, onChanged: _setTypes),

        // The latest order, with "Order again".
        if (lastOrder != null) ...[
          const SizedBox(height: gap),
          SectionHeader(title: 'Previous Order', linkLabel: 'Order history', onLink: () => MarketNav.orders(context)),
          PreviousOrderCard(
            order: lastOrder,
            media: _api.media,
            onOpen: () => MarketNav.order(context, lastOrder.id),
            onReorder: () => reorderDishes(context, lastOrder),
          ),
        ],

        // Popular dishes: two to a row, added straight to the basket.
        const SizedBox(height: gap),
        SectionHeader(title: 'Popular Dishes Near You', linkLabel: 'Browse menus', onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes)),
        if (dishes.isEmpty && _feed.loading)
          _columns(width, [for (var i = 0; i < 4; i++) const SkeletonBox(height: 250, radius: 18)])
        else if (dishes.isEmpty)
          EmptyCard(
            icon: Icons.restaurant_menu,
            title: 'No dishes to show yet',
            message: 'Pick another neighbourhood or kitchen type to see what people are ordering.',
            actionLabel: 'Browse kitchens',
            onAction: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
          )
        else
          _columns(width, [for (final d in dishes) DishGridCard(dish: d, media: _api.media, onTap: () => _openDish(d))]),

        // Featured / nearby kitchens.
        const SizedBox(height: gap),
        SectionHeader(title: 'Top Deals Near You', linkLabel: 'See all kitchens', onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes)),
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
          ]),

        // Tomorrow's specials and offer days.
        if (specials.isNotEmpty || offers.isNotEmpty) ...[
          const SizedBox(height: gap),
          SectionHeader(title: "Tomorrow's Specials", linkLabel: 'See all specials', onLink: () => MarketNav.specials(context)),
          _hScroll([
            for (final s in specials) SpecialCard(entry: s, media: _api.media, onTap: () => MarketNav.kitchen(context, s.vendor.id), onPreorder: () => preorderSpecial(context, s)),
            for (final o in offers) OfferDayCard(offer: o, media: _api.media, onTap: () => MarketNav.kitchen(context, o.vendor.id)),
          ]),
        ],

        // All kitchens.
        const SizedBox(height: gap),
        SectionHeader(
          title: 'All Kitchens',
          linkLabel: (_allVendors.data?.total ?? 0) > 0 ? 'See all ${_allVendors.data!.total}' : 'See all',
          onLink: () => MarketNav.kitchens(context, vendorTypes: _vendorTypes),
        ),
        if (_allVendors.pending)
          _hScroll(const [VendorTileSkeleton(), VendorTileSkeleton(), VendorTileSkeleton()])
        else if (_allVendors.error != null)
          ErrorCard(onRetry: () => _allVendors.run(() => _api.allVendors(_location, _vendorTypes), _changed), retrying: _allVendors.loading)
        else
          _grid([
            for (final v in _allVendors.data!.vendors) VendorCard(vendor: v, media: _api.media, showDistance: _location.isGps, onTap: () => MarketNav.kitchen(context, v.id)),
          ]),
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

  /// `flex gap-4 overflow-x-auto pb-3`: a sideways row of cards (unclipped, so
  /// cards slide out to the screen edges like the website's `-mx-4 px-4`).
  Widget _hScroll(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 16), children[i]],
      ],
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _tabButton('Dishes', data.dishes.length, dishesTab, () => setState(() => _tab = 'dishes')),
              const SizedBox(width: 8),
              _tabButton('Kitchens', data.vendors.length, !dishesTab, () => setState(() => _tab = 'kitchens')),
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

  Widget _tabButton(String label, int count, bool active, VoidCallback onTap) {
    final radius = BorderRadius.circular(16);
    return Container(
      decoration: BoxDecoration(
        gradient: active ? K.buttonGradient : null,
        color: active ? null : K.surface,
        borderRadius: radius,
        border: active ? null : Border.all(color: K.stone200),
        boxShadow: active ? K.brownShadow : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: kText(14, weight: FontWeight.w700, color: active ? Colors.white : K.stone600),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: active ? Colors.white.withValues(alpha: 0.2) : K.stone100, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '$count',
                    style: kText(12, weight: w900, color: active ? Colors.white : K.stone500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
