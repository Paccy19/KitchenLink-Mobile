import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../location.dart';
import '../market_nav.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/home_bars.dart';
import '../widgets/market_ui.dart';

/// Nearby Map (the website's `/vendors/map`): every open kitchen on the map,
/// by category and kitchen type, with the customer's position; tap a pin or
/// a row to see the kitchen. Refreshed every minute (stores open and close).
class KitchensMapScreen extends StatefulWidget {
  const KitchensMapScreen({super.key});

  @override
  State<KitchensMapScreen> createState() => _KitchensMapScreenState();
}

class _KitchensMapScreenState extends State<KitchensMapScreen> {
  late final CustomerApi _api = context.read<CustomerApi>();
  late final ClientLocation _location = context.read<ClientLocation>();
  final _map = MapController();
  List<({Vendor vendor, LatLng point})>? _pins;
  List<Category> _categories = [];
  String? _categoryId;
  List<String> _types = [];
  Object? _error;
  String? _selected;
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _api.categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) => null);
    _load(frame: true);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool frame = false}) async {
    try {
      final raw = await _api.mapVendors(_location, categoryId: _categoryId, vendorTypes: _types);
      final pins = <({Vendor vendor, LatLng point})>[];
      for (final r in raw) {
        final loc = r['location'] is Map ? r['location'] as Map : const {};
        final lat = loc['latitude'];
        final lng = loc['longitude'];
        if (lat is num && lng is num) pins.add((vendor: Vendor.fromJson(r), point: LatLng(lat.toDouble(), lng.toDouble())));
      }
      if (!mounted) return;
      setState(() {
        _pins = pins;
        _error = null;
      });
      if (frame) WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Frames the customer and the nearest kitchens (or every kitchen).
  void _fitAll({int? nearest}) {
    final pins = _pins;
    if (!_ready || pins == null) return;
    final here = LatLng(_location.lat, _location.lng);
    final points = [
      if (_location.isLocated) here,
      for (final p in (nearest == null ? pins : pins.take(nearest))) p.point,
    ];
    if (points.length >= 2) {
      _map.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15));
    } else if (points.length == 1) {
      _map.move(points.first, 14);
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _selected = null;
    _load(frame: true);
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<ClientLocation>();
    final pins = _pins ?? const [];
    final media = _api.media;
    final selected = pins.where((p) => p.vendor.id == _selected).firstOrNull;
    return MarketPage(
      title: 'Nearby Map',
      subtitle: _pins == null ? 'Loading kitchens…' : '${pins.length} open kitchens',
      body: Column(children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.45,
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: LatLng(location.lat, location.lng),
                initialZoom: 13,
                onMapReady: () {
                  _ready = true;
                  _fitAll(nearest: location.isLocated ? 8 : null);
                },
                onTap: (_, _) => setState(() => _selected = null),
              ),
              children: [
                TileLayer(urlTemplate: AppConfig.cartoTileUrl, userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile', retinaMode: true),
                MarkerLayer(markers: [
                  if (location.isLocated)
                    Marker(
                      point: LatLng(location.lat, location.lng),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Color(0x592563EB), spreadRadius: 4)],
                        ),
                      ),
                    ),
                  for (final pin in pins)
                    Marker(
                      point: pin.point,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = pin.vendor.id),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: pin.vendor.id == _selected ? K.amber400 : Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                          ),
                          child: VendorAvatar(vendor: pin.vendor, media: media, size: 34),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Column(children: [
                _mapButton(Icons.zoom_out_map, 'Show all kitchens', () => _fitAll()),
                const SizedBox(height: 6),
                _mapButton(Icons.my_location, 'My location', () async {
                  if (!location.isLocated && !await location.requestGps()) {
                    if (context.mounted) showMarketSnack(context, 'Could not get your location. Allow location access and try again.');
                    return;
                  }
                  _map.move(LatLng(location.lat, location.lng), 14);
                  _load();
                }),
              ]),
            ),
            const Positioned(right: 4, bottom: 2, child: Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 9, color: Colors.black54))),
            if (selected != null)
              Positioned(
                left: 12,
                right: 60,
                bottom: 12,
                child: Material(
                  color: Colors.white,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    leading: VendorAvatar(vendor: selected.vendor, media: media, size: 40),
                    title: Text(selected.vendor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kText(14, weight: w900)),
                    subtitle: Text(
                      [vendorTypeOf(selected.vendor.typeCode).label, selected.vendor.neighborhood, if (selected.vendor.hasDistance) '${numText(selected.vendor.distanceKm)} km'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kText(11.5, color: K.stone500),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => MarketNav.kitchen(context, selected.vendor.id),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            KitchenTypeFilter(value: _types, onChanged: (t) => _set(() => _types = t)),
            if (_categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  _chip('All', _categoryId == null, () => _set(() => _categoryId = null)),
                  for (final c in _categories) _chip(c.name, _categoryId == c.id, () => _set(() => _categoryId = c.id)),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            if (_error != null && _pins == null)
              ErrorCard(title: 'The map could not load', message: _error.toString(), onRetry: () => _load(frame: true))
            else if (_pins == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (pins.isEmpty)
              const EmptyCard(icon: Icons.map_outlined, title: 'No open kitchens here', message: 'Try another category or kitchen type.')
            else
              for (final pin in pins)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  selected: pin.vendor.id == _selected,
                  selectedTileColor: K.brown50,
                  leading: VendorAvatar(vendor: pin.vendor, media: media, size: 38),
                  title: Text(pin.vendor.name, style: kText(13.5, weight: w900)),
                  subtitle: Text(
                    [vendorTypeOf(pin.vendor.typeCode).label, pin.vendor.neighborhood, if (pin.vendor.hasDistance) '${numText(pin.vendor.distanceKm)} km'].join(' · '),
                    style: kText(11.5, color: K.stone500),
                  ),
                  trailing: IconButton(tooltip: 'Open kitchen', icon: const Icon(Icons.chevron_right), onPressed: () => MarketNav.kitchen(context, pin.vendor.id)),
                  onTap: () {
                    setState(() => _selected = pin.vendor.id);
                    if (_ready) _map.move(pin.point, 15);
                  },
                ),
          ]),
        ),
      ]),
    );
  }

  Widget _mapButton(IconData icon, String tooltip, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, size: 20, color: K.stone700)),
      );

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: active,
          showCheckmark: false,
          labelStyle: kText(12, weight: FontWeight.w700, color: active ? Colors.white : K.stone600),
          selectedColor: K.brown800,
          backgroundColor: Colors.white,
          onSelected: (_) => onTap(),
        ),
      );
}
