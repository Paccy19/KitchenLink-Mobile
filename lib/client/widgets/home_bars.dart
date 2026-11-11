import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../location.dart';
import '../models.dart';
import 'cards.dart';

/// The website's SEARCH_SUGGESTIONS.
const searchSuggestions = ['Isombe', 'Pizza', 'Burger', 'Chicken', 'Brochettes', 'Juice'];

/// A section title with an optional "See all →" link.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.linkLabel, this.onLink});

  final String title;
  final String? subtitle;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kText(MediaQuery.sizeOf(context).width >= 640 ? 20 : 18, weight: w900, spacing: -0.3)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: kText(12, weight: FontWeight.w400, color: K.stone500),
                ),
              ],
            ],
          ),
        ),
        if (linkLabel != null && onLink != null) ...[
          const SizedBox(width: 12),
          InkWell(
            onTap: onLink,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '$linkLabel  →',
                style: kText(12, weight: w900, color: K.brown700),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Recent searches, saved on the device (the website keeps the last 6).
class RecentSearches extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ofk_recent_searches';
  static const _max = 6;

  List<String> items = [];

  Future<void> restore() async {
    try {
      final raw = await _storage.read(key: _key).timeout(const Duration(seconds: 2));
      if (raw != null) items = (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {}
    notifyListeners();
  }

  void _save() {
    _storage.write(key: _key, value: jsonEncode(items)).catchError((_) {});
    notifyListeners();
  }

  void add(String query) {
    items = [query, ...items.where((q) => q.toLowerCase() != query.toLowerCase())].take(_max).toList();
    _save();
  }

  void remove(String query) {
    items = items.where((q) => q != query).toList();
    _save();
  }

  void clear() {
    items = [];
    _storage.delete(key: _key).catchError((_) {});
    notifyListeners();
  }
}

/// The website's SearchBar: a large rounded input; while focused, a panel
/// with recent searches and "Try searching for" suggestions.
class MarketSearchBar extends StatefulWidget {
  const MarketSearchBar({super.key, required this.controller, required this.onChanged, required this.recent});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final RecentSearches recent;

  @override
  State<MarketSearchBar> createState() => _MarketSearchBarState();
}

class _MarketSearchBarState extends State<MarketSearchBar> {
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _group = Object();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => _focus.hasFocus ? _portal.show() : _portal.hide());
    widget.recent.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.recent.removeListener(_refresh);
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    widget.recent.add(trimmed);
    widget.controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    widget.onChanged(trimmed);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: K.stone200),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return TapRegion(
          groupId: _group,
          onTapOutside: (_) => _focus.unfocus(),
          child: CompositedTransformTarget(
            link: _link,
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomLeft,
                offset: const Offset(0, 8),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TapRegion(
                    groupId: _group,
                    child: SizedBox(width: constraints.maxWidth, child: _panel()),
                  ),
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: K.shadowSm),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  onChanged: widget.onChanged,
                  onSubmitted: _submit,
                  textInputAction: TextInputAction.search,
                  style: kText(16, weight: FontWeight.w400),
                  decoration: InputDecoration(
                    hintText: 'What are you craving? (Isombe, Pizza, Burger…)',
                    hintStyle: kText(16, weight: FontWeight.w400, color: K.stone400),
                    filled: true,
                    fillColor: K.surface,
                    isDense: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 16, right: 10),
                      child: Icon(Icons.search, size: 20, color: K.gray400),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 46),
                    suffixIcon: widget.controller.text.isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Material(
                              color: K.stone100,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  widget.controller.clear();
                                  widget.onChanged('');
                                  _focus.requestFocus();
                                },
                                child: SizedBox(width: 32, height: 32, child: Icon(Icons.close, size: 16, color: K.stone500)),
                              ),
                            ),
                          ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 32),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(borderSide: BorderSide(color: K.brown700, width: 1.5)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panel() {
    final recent = widget.recent.items;
    final label = kText(11, weight: FontWeight.w700, color: K.stone400, spacing: 0.6);
    return Material(
      color: K.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: K.stone100),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 25, offset: Offset(0, 20), spreadRadius: -5)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recent.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: K.stone100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Row(
                        children: [
                          Expanded(child: Text('RECENT SEARCHES', style: label)),
                          InkWell(
                            onTap: widget.recent.clear,
                            child: Text(
                              'Clear',
                              style: kText(11, weight: FontWeight.w700, color: K.brown700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final query in recent)
                          Container(
                            padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
                            decoration: BoxDecoration(
                              color: K.stone50,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: K.stone100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _submit(query),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule, size: 12, color: K.stone400),
                                      const SizedBox(width: 6),
                                      Text(
                                        query,
                                        style: kText(12, weight: FontWeight.w600, color: K.stone700),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => widget.recent.remove(query),
                                  child: Semantics(
                                    label: 'Remove $query from recent searches',
                                    child: SizedBox(width: 20, height: 20, child: Icon(Icons.close, size: 12, color: K.stone400)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: K.brown500),
                        const SizedBox(width: 4),
                        Text('TRY SEARCHING FOR', style: label),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final s in searchSuggestions) SuggestionChip(label: s, onTap: () => _submit(s))],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `px-3.5 py-1.5 rounded-full bg-[#faf6f2] text-[#3d1b0c] border-[#ebd7c5]`.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: K.brown50,
    shape: StadiumBorder(side: BorderSide(color: K.brown200)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          label,
          style: kText(12, weight: FontWeight.w700, color: K.brown850),
        ),
      ),
    ),
  );
}

// ---- Categories ------------------------------------------------------------

const _categoryIcons = <String, IconData>{
  'all': Icons.grid_view_rounded,
  'local': Icons.ramen_dining_outlined,
  'african': Icons.local_fire_department_outlined,
  'fast-food': Icons.lunch_dining_outlined,
  'healthy': Icons.eco_outlined,
  'bakery': Icons.bakery_dining_outlined,
  'breakfast': Icons.coffee_outlined,
  'lunch': Icons.schedule,
  'dinner': Icons.kebab_dining_outlined,
  'drinks': Icons.local_drink_outlined,
  'desserts': Icons.cake_outlined,
};

IconData _categoryIcon(Category category) {
  String key(String v) => v.toLowerCase().replaceAll('_', '-');
  var slug = category.name.toLowerCase().trim().replaceAll(RegExp(r'\s+food$'), '').replaceAll(RegExp(r'\s+'), '-');
  if (slug == 'fast') slug = 'fast-food';
  return _categoryIcons[key(category.iconUrl)] ?? _categoryIcons[key(category.id)] ?? _categoryIcons[slug] ?? Icons.restaurant_menu;
}

bool _isImageUrl(String value) => RegExp(r'^(https?:)?//', caseSensitive: false).hasMatch(value) || value.startsWith('/uploads');

/// "Explore by Category": a sideways row of category tiles ("All" first).
class CategoryBar extends StatefulWidget {
  const CategoryBar({super.key, required this.categories, required this.onSelect, required this.media, this.loading = false});

  final List<Category> categories;
  final ValueChanged<Category?> onSelect;
  final MediaResolver media;
  final bool loading;

  @override
  State<CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<CategoryBar> {
  final _scroller = ScrollController();

  List<Category> get categories => widget.categories;
  bool get loading => widget.loading;
  MediaResolver get media => widget.media;
  ValueChanged<Category?> get onSelect => widget.onSelect;

  @override
  void dispose() {
    _scroller.dispose();
    super.dispose();
  }

  /// The website's ← → buttons: scroll the row by 240 px.
  void _scrollBy(double amount) {
    if (!_scroller.hasClients) return;
    final target = (_scroller.offset + amount).clamp(0.0, _scroller.position.maxScrollExtent);
    _scroller.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _arrow(IconData icon, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: Container(
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: K.shadowSm),
      child: Material(
        color: K.surface,
        shape: CircleBorder(side: BorderSide(color: K.stone200)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: K.stone600)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Explore by Category', style: kText(wide ? 20 : 18, weight: w900, spacing: -0.3)),
                  Text('Curated cuisines crafted by local culinary experts', style: kText(12, color: K.stone500)),
                ],
              ),
            ),
            if (wide) ...[
              _arrow(Icons.chevron_left, 'Scroll categories left', () => _scrollBy(-240)),
              const SizedBox(width: 6),
              _arrow(Icons.chevron_right, 'Scroll categories right', () => _scrollBy(240)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          controller: _scroller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading && categories.isEmpty)
                for (var i = 0; i < 6; i++) ...[if (i > 0) const SizedBox(width: 12), const SkeletonBox(width: 80, height: 92, radius: 16)]
              else ...[
                _tile(
                  label: 'All',
                  active: true,
                  icon: const Icon(Icons.grid_view_rounded, size: 20, color: Colors.white),
                  onTap: () => onSelect(null),
                ),
                for (final category in categories) ...[
                  const SizedBox(width: 12),
                  _tile(label: category.name, active: false, icon: _iconFor(category), onTap: () => onSelect(category)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconFor(Category category) {
    final fallback = Icon(_categoryIcon(category), size: 20, color: K.brown700);
    final url = _isImageUrl(category.iconUrl) ? media(category.iconUrl) : null;
    if (url == null) return fallback;
    return Image.network(url, width: 24, height: 24, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback);
  }

  Widget _tile({required String label, required bool active, required Widget icon, required VoidCallback onTap}) {
    final radius = BorderRadius.circular(16);
    return Container(
      constraints: const BoxConstraints(minWidth: 80),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [K.brown900, K.brown800, Color(0xFF200D05)])
            : null,
        color: active ? null : K.surface,
        borderRadius: radius,
        border: active ? null : Border.all(color: K.stone200.withValues(alpha: 0.8)),
        boxShadow: active ? const [BoxShadow(color: Color(0x4D2B1206), blurRadius: 15, offset: Offset(0, 10), spreadRadius: -3)] : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.15) : K.stone50,
                    borderRadius: radius,
                    border: Border.all(color: active ? Colors.white.withValues(alpha: 0.2) : K.stone100),
                    boxShadow: K.shadowSm,
                  ),
                  child: icon,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: kText(11, weight: FontWeight.w700, color: active ? Colors.white : K.stone700, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's VendorTypeFilter: "All types" and one chip per kitchen type.
class KitchenTypeFilter extends StatelessWidget {
  const KitchenTypeFilter({super.key, required this.value, required this.onChanged});

  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value.toSet();
    void toggle(String code) {
      final next = {...selected};
      if (!next.remove(code)) next.add(code);
      onChanged(vendorTypes.map((t) => t.code).where(next.contains).toList());
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All types', null, selected.isEmpty, () => onChanged(const [])),
          for (final type in vendorTypes) ...[const SizedBox(width: 8), _chip(type.label, type.icon, selected.contains(type.code), () => toggle(type.code))],
        ],
      ),
    );
  }

  Widget _chip(String label, IconData? icon, bool active, VoidCallback onTap) {
    final radius = BorderRadius.circular(16);
    final fg = active ? Colors.white : K.stone700;
    return Container(
      decoration: BoxDecoration(
        gradient: active ? K.buttonGradient : null,
        color: active ? null : K.surface,
        borderRadius: radius,
        border: Border.all(color: active ? Colors.transparent : K.stone200),
        boxShadow: active ? K.shadowMd : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
                Text(
                  label,
                  style: kText(12, weight: FontWeight.w700, color: fg),
                ),
                if (active && icon != null) ...[const SizedBox(width: 6), Icon(Icons.close, size: 12, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Location --------------------------------------------------------------

/// The location pill ("📍 Kimironko, Kigali  MANUAL  ⌄") that opens the picker.
class LocationPill extends StatelessWidget {
  const LocationPill({super.key, required this.location, required this.onGpsUnavailable});

  final ClientLocation location;
  final VoidCallback onGpsUnavailable;

  @override
  Widget build(BuildContext context) {
    final (badge, bg, fg) = switch (location.source) {
      LocationSource.gps => ('GPS', K.forest100, K.forest700),
      LocationSource.manual => ('MANUAL', K.brown100, K.brown850),
      LocationSource.defaultCentre => ('DEFAULT', K.stone100, K.stone500),
    };
    return Semantics(
      button: true,
      label: 'Delivering to ${location.label}. Change location',
      child: Material(
        color: K.surface,
        shape: StadiumBorder(side: BorderSide(color: K.stone200)),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showLocationPicker(context, location, onGpsUnavailable: onGpsUnavailable),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: K.brown500),
                const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      location.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kText(12, weight: FontWeight.w700, color: K.stone700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    badge,
                    style: kText(9, weight: w900, color: fg),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down, size: 15, color: K.stone400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's "Delivery location" sheet: use GPS, or pick a neighbourhood.
Future<void> showLocationPicker(BuildContext context, ClientLocation location, {required VoidCallback onGpsUnavailable}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: K.surface,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => ListenableBuilder(
      listenable: location,
      builder: (sheet, _) {
        final requesting = location.status == LocationStatus.requesting;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Delivery location', style: kText(18, weight: w900)),
                    ),
                    Material(
                      color: K.stone100,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(sheet),
                        child: SizedBox(width: 36, height: 36, child: Icon(Icons.close, size: 16, color: K.stone600)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Material(
                  color: K.brown50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: K.brown200),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: requesting
                        ? null
                        : () async {
                            if (!gpsAvailable) {
                              Navigator.pop(sheet);
                              onGpsUnavailable();
                              return;
                            }
                            final ok = await location.requestGps();
                            if (sheet.mounted) Navigator.pop(sheet);
                            if (!ok) onGpsUnavailable();
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [K.brown900, K.fillBrown700]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: K.shadowSm,
                            ),
                            child: Icon(Icons.near_me_outlined, size: 20, color: K.light(() => K.brown300)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Use my current location', style: kText(14, weight: w900)),
                                Text(
                                  requesting
                                      ? 'Measuring your position…'
                                      : location.isGps
                                      ? 'Located${location.accuracyM != null ? ' · accurate to ~${location.accuracyM} m' : ''} · showing open kitchens near you'
                                      : 'Finds open kitchens closest to you with GPS',
                                  style: kText(12, weight: FontWeight.w400, color: K.stone500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'OR PICK A NEIGHBOURHOOD',
                    style: kText(11, weight: FontWeight.w700, color: K.stone400, spacing: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < kigaliNeighborhoods.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: K.stone100),
                  _areaRow(sheet, location, kigaliNeighborhoods[i]),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _areaRow(BuildContext sheet, ClientLocation location, Neighborhood area) {
  final active = location.source == LocationSource.manual && location.label.contains(area.name);
  return InkWell(
    onTap: () {
      location.selectNeighborhood(area);
      Navigator.pop(sheet);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              area.name,
              style: kText(14, weight: active ? w900 : FontWeight.w600, color: active ? K.brown700 : K.stone700),
            ),
          ),
          Text(
            area.district,
            style: kText(12, weight: FontWeight.w400, color: K.stone400),
          ),
          if (active) ...[const SizedBox(width: 8), Icon(Icons.check, size: 16, color: K.brown700)],
        ],
      ),
    ),
  );
}

/// The website's LocationPrimer: shown once, explains why the location is asked.
Future<void> showLocationPrimer(BuildContext context, ClientLocation location, {required VoidCallback onGpsUnavailable}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (dialog) => ListenableBuilder(
      listenable: location,
      builder: (dialog, _) {
        final requesting = location.status == LocationStatus.requesting;
        return Dialog(
          backgroundColor: K.surface,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 144,
                  decoration: const BoxDecoration(gradient: K.logoGradient),
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(Icons.location_on_outlined, size: 40, color: Colors.white),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.2),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              location.dismissPrimer();
                              Navigator.pop(dialog);
                            },
                            child: Semantics(
                              label: 'Continue with default location',
                              child: const SizedBox(width: 36, height: 36, child: Icon(Icons.close, size: 16, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Find kitchens near you',
                        textAlign: TextAlign.center,
                        style: kText(20, weight: w900),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'KitchenLink uses your location to show nearby home cooks and restaurants, accurate delivery distances '
                        'and realistic prep times. Your location is only used while you browse.',
                        textAlign: TextAlign.center,
                        style: kText(14, weight: FontWeight.w400, color: K.stone500, height: 1.6),
                      ),
                      const SizedBox(height: 14),
                      GradientButton(
                        label: requesting ? 'Locating…' : 'Use my location',
                        icon: Icons.near_me_outlined,
                        height: 50,
                        onTap: requesting
                            ? null
                            : () async {
                                if (!gpsAvailable) {
                                  await location.dismissPrimer();
                                  if (dialog.mounted) Navigator.pop(dialog);
                                  onGpsUnavailable();
                                  return;
                                }
                                final ok = await location.enableFromPrimer();
                                if (dialog.mounted) Navigator.pop(dialog);
                                if (!ok) onGpsUnavailable();
                              },
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () {
                          location.dismissPrimer();
                          Navigator.pop(dialog);
                        },
                        style: TextButton.styleFrom(foregroundColor: K.stone400, minimumSize: const Size.fromHeight(40)),
                        child: Text(
                          'Continue with Kigali city centre',
                          style: kText(12, weight: FontWeight.w700, color: K.stone400),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
