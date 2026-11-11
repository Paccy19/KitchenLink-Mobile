import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/home_bars.dart';
import '../widgets/market_ui.dart';

enum KitchensMode { all, specials, events }

/// The website's `/vendors`: every kitchen (nearest first, by category and
/// kitchen type, sorted, page by page), `?filter=preorder` (Tomorrow's
/// Specials and Offer Days) and `?events=1` (kitchens for a Big Event, priced
/// for the customer's number of guests).
class KitchensScreen extends StatefulWidget {
  const KitchensScreen({super.key, this.mode = KitchensMode.all, this.categoryId, this.categoryName, this.vendorTypes = const []});

  final KitchensMode mode;
  final String? categoryId;
  final String? categoryName;
  final List<String> vendorTypes;

  @override
  State<KitchensScreen> createState() => _KitchensScreenState();
}

class _KitchensScreenState extends State<KitchensScreen> {
  late final CustomerApi _api = context.read<CustomerApi>();
  late final ClientLocation _location = context.read<ClientLocation>();

  late String? _categoryId = widget.categoryId;
  late String? _categoryName = widget.categoryName;
  late List<String> _types = [...widget.vendorTypes];
  String _sort = 'distance';
  int? _guests;
  bool _pickup = false;

  final List<Vendor> _vendors = [];
  final List<Json> _rawVendors = [];
  int _page = 0;
  int _total = 0;
  num _nearKm = 5;
  bool _locationUsed = false;
  bool _loading = false;
  Object? _error;
  int _request = 0;

  List<Category> _categories = [];
  List<SpecialEntry>? _specials;
  List<OfferDay>? _offers;

  bool get _events => widget.mode == KitchensMode.events;
  bool get _hasMore => _vendors.length < _total;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocation);
    if (widget.mode == KitchensMode.specials) {
      _loadSpecials();
    } else {
      _api.categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
      if (!_events) _reload();
    }
  }

  @override
  void dispose() {
    _location.removeListener(_onLocation);
    super.dispose();
  }

  String _locKey = '';
  void _onLocation() {
    final key = '${_location.lat}|${_location.lng}';
    if (key == _locKey) return;
    _locKey = key;
    if (widget.mode == KitchensMode.specials) {
      _loadSpecials();
    } else if (!_events || _guests != null) {
      _reload();
    }
  }

  Future<void> _loadSpecials() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([_api.specials(_location), _api.offers(_location)]);
      if (!mounted) return;
      setState(() {
        _specials = results[0] as List<SpecialEntry>;
        _offers = results[1] as List<OfferDay>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _reload() async {
    _vendors.clear();
    _rawVendors.clear();
    _page = 0;
    _total = 0;
    await _more();
  }

  Future<void> _more() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.vendorsPage(
        _location,
        vendorTypes: _types,
        categoryId: _categoryId,
        sort: _sort,
        page: _page + 1,
        events: _events,
        guests: _guests,
      );
      if (!mounted || request != _request) return;
      final raw = pickList(data, ['vendors']);
      final meta = data['meta'] is Map ? (data['meta'] as Map) : const {};
      setState(() {
        _page += 1;
        _rawVendors.addAll(raw);
        _vendors.addAll(raw.map(Vendor.fromJson));
        _total = (meta['total'] as num?)?.toInt() ?? _vendors.length;
        _nearKm = (meta['near_radius_km'] as num?) ?? 5;
        _locationUsed = meta['location_used'] == true;
      });
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ClientLocation>();
    return switch (widget.mode) {
      KitchensMode.specials => _specialsPage(),
      KitchensMode.events when _guests == null => _guestStep(),
      _ => _listPage(),
    };
  }

  // ---- Tomorrow's Specials -------------------------------------------------

  Widget _specialsPage() {
    final specials = _specials;
    final offers = _offers;
    final media = _api.media;
    return MarketPage(
      title: "Tomorrow's Specials",
      subtitle: "Pre-order home cooks' specials before their cutoff, and see upcoming offers",
      body: RefreshIndicator(
        onRefresh: _loadSpecials,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (specials == null || offers == null)
            _error != null
                ? ErrorCard(title: 'Specials could not load', message: _error.toString(), onRetry: _loadSpecials)
                : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (specials.isEmpty && offers.isEmpty)
            EmptyCard(
              icon: Icons.soup_kitchen_outlined,
              title: 'No specials today',
              message: 'No kitchen has announced a special or an upcoming offer yet. Check back soon.',
              actionLabel: 'Browse all kitchens',
              onAction: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const KitchensScreen())),
            )
          else ...[
            if (specials.isNotEmpty) ...[
              _groupHeading(Icons.soup_kitchen_outlined, 'Pre-order specials', 'order before the cutoff'),
              for (final s in specials)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SpecialCard(entry: s, media: media, onTap: () => MarketNav.kitchen(context, s.vendor.id), onPreorder: () => preorderSpecial(context, s)),
                ),
            ],
            if (offers.isNotEmpty) ...[
              _groupHeading(Icons.card_giftcard, 'Upcoming offer days', 'kitchens with a deal on a coming day'),
              for (final o in offers)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: OfferDayCard(offer: o, media: media, onTap: () => MarketNav.kitchen(context, o.vendor.id))),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _groupHeading(IconData icon, String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(children: [
          Icon(icon, size: 18, color: K.brown500),
          const SizedBox(width: 8),
          Text(title, style: kText(17, weight: w900)),
          const SizedBox(width: 8),
          Expanded(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(11.5, color: K.stone400))),
        ]),
      );

  // ---- Big Event: how many guests ------------------------------------------

  Widget _guestStep() => _GuestStep(
        initialPickup: _pickup,
        onSubmit: (count, pickup) {
          setState(() {
            _guests = count;
            _pickup = pickup;
          });
          _reload();
        },
      );

  // ---- The list -------------------------------------------------------------

  Widget _listPage() {
    final media = _api.media;
    final grouped = !_events && _sort == 'distance' && _locationUsed;
    final nearby = grouped ? _vendors.where((v) => v.isNearby).toList() : <Vendor>[];
    final others = grouped ? _vendors.where((v) => !v.isNearby).toList() : _vendors;
    final title = _categoryName ?? (_events ? 'Kitchens for Big Events' : _types.length == 1 ? '${vendorTypeOf(_types.first).label} kitchens' : 'All Kitchens');

    Widget card(Vendor v) {
      if (_events) {
        final raw = _rawVendors.where((r) => '${r['id']}' == v.id).firstOrNull ?? const <String, dynamic>{};
        return _EventVendorCard(vendor: v, event: raw['event'] is Map ? (raw['event'] as Map).cast<String, dynamic>() : const {}, pickup: _pickup, guests: _guests!, media: media);
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: VendorCard(vendor: v, media: media, showDistance: _location.isGps, onTap: () => MarketNav.kitchen(context, v.id)),
      );
    }

    return MarketPage(
      title: title,
      subtitle: _location.isLocated ? 'Nearest to ${_location.label} first' : 'Every kitchen on KitchenLink',
      actions: [IconButton(tooltip: 'Map view', onPressed: () => MarketNav.map(context), icon: const Icon(Icons.map_outlined))],
      body: RefreshIndicator(
        onRefresh: _reload,
        child: NotificationListener<ScrollNotification>(
          // Infinite scroll: the next page loads near the bottom.
          onNotification: (n) {
            if (n.metrics.extentAfter < 400 && _hasMore && !_loading && _error == null) _more();
            return false;
          },
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_events) ...[
              Row(children: [
                const Text('🎉', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(child: Text('Prices for $_guests guests', style: kText(14, weight: w900))),
                TextButton(onPressed: () => setState(() => _guests = null), child: const Text('Change')),
              ]),
              _FulfilmentChoice(pickup: _pickup, onChanged: (p) => setState(() => _pickup = p)),
              const SizedBox(height: 12),
            ] else ...[
              Row(children: [
                const Icon(Icons.tune, size: 16, color: K.stone500),
                const SizedBox(width: 6),
                Text('Sort', style: kText(12, weight: FontWeight.w700, color: K.stone600)),
                const SizedBox(width: 8),
                for (final (id, label) in const [('distance', 'Distance'), ('rating', 'Rating')]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _sort == id,
                    showCheckmark: false,
                    labelStyle: kText(12, weight: FontWeight.w700, color: _sort == id ? Colors.white : K.stone600),
                    selectedColor: K.brown800,
                    backgroundColor: Colors.white,
                    onSelected: (_) => _set(() => _sort = id),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                if (_total > 0) Text('$_total kitchens', style: kText(12, weight: FontWeight.w700, color: K.stone500)),
              ]),
              const SizedBox(height: 10),
            ],
            if (!_location.isLocated)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlineAction(
                  label: _location.status == LocationStatus.requesting ? 'Locating…' : 'Use my location to see kitchens near you first',
                  icon: Icons.navigation_outlined,
                  color: K.brown700,
                  onTap: _location.status == LocationStatus.requesting
                      ? null
                      : () async {
                          if (!await _location.requestGps() && mounted) showMarketSnack(context, 'Could not get your location. Allow location access, or pick a neighbourhood on the home page.');
                        },
                ),
              ),
            KitchenTypeFilter(value: _types, onChanged: (types) => _set(() => _types = types)),
            const SizedBox(height: 12),
            if (_categories.isNotEmpty) ...[
              CategoryBar(
                categories: _categories,
                media: media,
                onSelect: (c) => _set(() {
                  _categoryId = c?.id;
                  _categoryName = c?.name;
                }),
              ),
              if (_categoryId != null)
                Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _set(() => _categoryId = _categoryName = null), child: const Text('Clear category filter'))),
              const SizedBox(height: 12),
            ],
            if (_vendors.isEmpty && _loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_vendors.isEmpty && _error != null)
              ErrorCard(title: 'Kitchens failed to load', message: _error.toString(), onRetry: _reload)
            else if (_vendors.isEmpty)
              EmptyCard(
                icon: Icons.soup_kitchen_outlined,
                title: 'No kitchens found',
                message: _categoryName != null
                    ? 'No kitchen serves ${_categoryName!.toLowerCase()} yet. Try another category.'
                    : _events
                        ? 'No kitchen hosts events for $_guests guests yet. Try a different number of guests.'
                        : _types.isNotEmpty
                            ? 'No kitchen of the selected type has joined yet. Try another type.'
                            : 'No kitchens have joined yet. Check back soon.',
                actionLabel: _types.isNotEmpty ? 'Show every kitchen type' : null,
                onAction: () => _set(() => _types = []),
              )
            else ...[
              if (nearby.isNotEmpty) ...[_groupHeading(Icons.navigation_outlined, 'Near you', 'within ${numTextOf(_nearKm)} km'), for (final v in nearby) card(v)],
              if (others.isNotEmpty) ...[
                if (grouped)
                  _groupHeading(
                    Icons.soup_kitchen_outlined,
                    nearby.isNotEmpty ? 'More kitchens' : 'All kitchens',
                    nearby.isNotEmpty ? 'further than ${numTextOf(_nearKm)} km' : 'none within ${numTextOf(_nearKm)} km — nearest first',
                  ),
                for (final v in others) card(v),
              ],
              const SizedBox(height: 8),
              if (_hasMore)
                Center(child: OutlineAction(label: _loading ? 'Loading…' : 'Load more kitchens', onTap: _loading ? null : _more))
              else
                Center(child: Text('You have seen all $_total kitchens', style: kText(12, color: K.stone400))),
              if (_error != null && _vendors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(_error.toString())),
            ],
          ]),
        ),
      ),
    );
  }
}

/// "Pre-order now" on a special: turns pre-ordering on for that kitchen and
/// opens its menu to add dishes.
void preorderSpecial(BuildContext context, SpecialEntry entry) {
  context.read<Cart>().startPreorder(PreorderSpecial(
        vendorId: entry.vendor.id,
        vendorName: entry.vendor.name,
        text: entry.special.text,
        cutoffAt: entry.special.cutoffAt,
        deliveryAt: entry.special.deliveryAt,
      ));
  showMarketSnack(context, 'Pre-order on — add dishes from ${entry.vendor.name} to your basket.');
  MarketNav.kitchen(context, entry.vendor.id);
}

class _FulfilmentChoice extends StatelessWidget {
  const _FulfilmentChoice({required this.pickup, required this.onChanged});

  final bool pickup;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: ChoiceTile(selected: !pickup, onTap: () => onChanged(false), title: 'Delivery', subtitle: 'Kitchen brings it · delivery fee')),
        const SizedBox(width: 8),
        Expanded(child: ChoiceTile(selected: pickup, onTap: () => onChanged(true), title: 'Pick up', subtitle: 'You collect it · no delivery fee')),
      ]);
}

/// Big Event, first step: how many guests and how the food gets there.
class _GuestStep extends StatefulWidget {
  const _GuestStep({required this.initialPickup, required this.onSubmit});

  final bool initialPickup;
  final void Function(int guests, bool pickup) onSubmit;

  @override
  State<_GuestStep> createState() => _GuestStepState();
}

class _GuestStepState extends State<_GuestStep> {
  final _count = TextEditingController();
  late bool _pickup = widget.initialPickup;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  int? get _valid {
    final n = int.tryParse(_count.text.trim());
    return n != null && n >= 1 && n <= 100000 ? n : null;
  }

  @override
  Widget build(BuildContext context) => MarketPage(
        title: 'Plan a big event',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('🎉', textAlign: TextAlign.center, style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text('Plan a big event', textAlign: TextAlign.center, style: kText(20, weight: w900)),
              Text("How many people are coming? We'll show the kitchens that can host them and what it will cost.", textAlign: TextAlign.center, style: kText(12.5, color: K.stone500)),
              const SizedBox(height: 16),
              const FieldLabel('Number of guests'),
              TextField(controller: _count, autofocus: true, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: marketInput('e.g. 150')),
              const SizedBox(height: 14),
              const FieldLabel('How will you get the food?'),
              _FulfilmentChoice(pickup: _pickup, onChanged: (p) => setState(() => _pickup = p)),
              const SizedBox(height: 16),
              GradientButton(label: 'Show kitchens and prices', onTap: _valid == null ? null : () => widget.onSubmit(_valid!, _pickup)),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
            ]),
          ),
        ]),
      );
}

/// A kitchen and each of its event packages priced for the guests.
class _EventVendorCard extends StatelessWidget {
  const _EventVendorCard({required this.vendor, required this.event, required this.pickup, required this.guests, required this.media});

  final Vendor vendor;
  final Json event;
  final bool pickup;
  final int guests;
  final MediaResolver media;

  @override
  Widget build(BuildContext context) {
    final packages = (event['packages'] is List ? event['packages'] as List : const []).whereType<Map>().map((p) => p.cast<String, dynamic>()).toList();
    if (packages.isEmpty) return const SizedBox.shrink();
    final anyQuote = packages.map((p) => p['quote']).whereType<Map>().firstOrNull;
    final ranges = (event['delivery_fee_ranges'] is List ? event['delivery_fee_ranges'] as List : const []).whereType<Map>().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            VendorAvatar(vendor: vendor, media: media, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vendor.name, style: kText(15, weight: w900)),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  VendorTypeBadge(vendor.typeCode, small: true),
                  Text('★ ${numText(vendor.rating)} · ${vendor.neighborhood}', style: kText(11.5, color: K.stone500)),
                ]),
              ]),
            ),
          ]),
          if (packages.length > 1) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${packages.length} packages for your event', style: kText(11.5, weight: FontWeight.w700, color: K.brown500))),
          for (final pkg in packages) _package(context, pkg),
          if (!pickup) ...[
            const SizedBox(height: 8),
            Text('The kitchen brings the food${'${event['delivery_details'] ?? ''}'.isNotEmpty ? ' — ${event['delivery_details']}' : ''}', style: kText(12, color: K.stone600)),
            if (anyQuote?['delivery_fee_rwf'] == null)
              for (final r in ranges)
                Text('${r['to_km'] == null ? '${r['from_km']} km and more' : '${r['from_km']} km up to ${r['to_km']} km'}: ${rwf((r['fee_rwf'] as num?) ?? 0)}', style: kText(11.5, color: K.stone500)),
          ],
          const SizedBox(height: 8),
          OutlineAction(label: 'View kitchen', onTap: () => MarketNav.kitchen(context, vendor.id)),
        ]),
      ),
    );
  }

  Widget _package(BuildContext context, Json pkg) {
    final quote = pkg['quote'] is Map ? (pkg['quote'] as Map).cast<String, dynamic>() : null;
    num n(dynamic v) => (v as num?) ?? 0;
    final menu = (pkg['menu'] is List ? pkg['menu'] as List : const []).join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: K.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: K.stone200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${pkg['name'] ?? 'Package'}', style: kText(14, weight: w900)),
              if ('${pkg['description'] ?? ''}'.isNotEmpty) Text('${pkg['description']}', style: kText(11.5, color: K.stone500)),
            ]),
          ),
          Text('${rwf(n(quote?['price_per_plate_rwf'] ?? pkg['from_price_per_plate_rwf']))} /plate', style: kText(13, weight: w900, color: K.brown750)),
        ]),
        const SizedBox(height: 6),
        if (quote != null) ...[
          MoneyRow('${quote['guests']} ${quote['guests'] == 1 ? 'plate' : 'plates'}', rwf(n(quote['food_total_rwf']))),
          pickup
              ? const MoneyRow('You pick it up', 'No delivery fee')
              : MoneyRow(quote['distance_km'] != null ? 'Delivery (about ${quote['distance_km']} km)' : 'Delivery', quote['delivery_fee_rwf'] != null ? rwf(n(quote['delivery_fee_rwf'])) : 'by distance'),
          MoneyRow(!pickup && quote['delivery_fee_rwf'] == null ? 'Total (+ delivery)' : 'Total', rwf(n(pickup ? quote['pickup_total_rwf'] : quote['total_rwf'])), strong: true),
        ] else
          Text('${pkg['min_guests']}–${pkg['max_guests']} guests', style: kText(12, color: K.stone500)),
        if (menu.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(menu, style: kText(11.5, color: K.stone600))),
        if ('${pkg['portion'] ?? ''}'.isNotEmpty) Text('${pkg['portion']}', style: kText(11, color: K.stone500)),
        if (!pickup && '${pkg['service_style_label'] ?? ''}'.isNotEmpty)
          Text('${pkg['service_style_label']}${'${pkg['service_details'] ?? ''}'.isNotEmpty ? ' — ${pkg['service_details']}' : ''}', style: kText(11, color: K.stone500)),
        const SizedBox(height: 8),
        GradientButton(
          label: 'Place order',
          height: 40,
          fontSize: 13,
          onTap: () => MarketNav.eventOrder(context, vendorId: vendor.id, packageId: '${pkg['id']}', guests: (quote?['guests'] as num?)?.toInt() ?? guests, pickup: pickup),
        ),
      ]),
    );
  }
}
