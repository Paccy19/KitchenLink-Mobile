import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../config.dart';
import '../client_theme.dart';
import '../gps.dart';
import 'form_fields.dart';

/// "-1.944100" style coordinates → numbers, or null when not valid yet
/// (the website's parseCoords).
({double lat, double lng})? parseCoords(String lat, String lng) {
  if (lat.trim().isEmpty || lng.trim().isEmpty) return null;
  final a = double.tryParse(lat.trim());
  final b = double.tryParse(lng.trim());
  if (a == null || b == null || !a.isFinite || !b.isFinite) return null;
  if (a < -90 || a > 90 || b < -180 || b > 180) return null;
  return (lat: a, lng: b);
}

// "-1.9441, 30.0619" pasted into one box (e.g. copied from Google Maps).
final _pair = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*$');

// Above this GPS uncertainty the vendor is asked to check the pin.
const _roughFixM = 50;

/// The website's KitchenLocationFields: area + street search with
/// suggestions, "Use my current location", and a map where tapping places the
/// kitchen pin (which fills in latitude / longitude).
class KitchenLocationFields extends StatefulWidget {
  const KitchenLocationFields({
    super.key,
    required this.client,
    required this.area,
    required this.address,
    required this.lat,
    required this.lng,
    this.areaError,
    this.coordsError,
    this.onChanged,
  });

  final ApiClient client;
  final TextEditingController area;
  final TextEditingController address;
  final TextEditingController lat;
  final TextEditingController lng;
  final String? areaError;
  final String? coordsError;

  /// Called after any value changes (to clear errors, redraw…).
  final VoidCallback? onChanged;

  @override
  State<KitchenLocationFields> createState() => _KitchenLocationFieldsState();
}

class _KitchenLocationFieldsState extends State<KitchenLocationFields> {
  final _map = MapController();
  bool _mapReady = false;
  LatLng? _areaCenter;
  String _notice = '';
  String _failed = '';
  bool _locating = false;

  ({double lat, double lng})? get _coords => parseCoords(widget.lat.text, widget.lng.text);

  void _changed() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  void _setCoords(double lat, double lng) {
    widget.lat.text = lat.toStringAsFixed(6);
    widget.lng.text = lng.toStringAsFixed(6);
    _changed();
  }

  void _moveMap(LatLng center, double zoom) {
    if (_mapReady) _map.move(center, zoom);
  }

  Future<Map<String, dynamic>?> _place(Map<String, dynamic> suggestion) async {
    try {
      final data = await widget.client.request('/geo/places/details${ApiClient.qs({'id': suggestion['id']})}');
      final place = data is Map ? data['place'] : null;
      if (place is Map && place['lat'] is num && place['lng'] is num) return Map<String, dynamic>.from(place);
    } catch (_) {
      // The suggestion's own position is still usable.
    }
    return suggestion['lat'] is num && suggestion['lng'] is num ? suggestion : null;
  }

  Future<void> _pickArea(Map<String, dynamic> suggestion) async {
    final name = (suggestion['name'] ?? '').toString();
    widget.area.text = name;
    _failed = '';
    _changed();
    final place = await _place(suggestion);
    if (!mounted) return;
    if (place == null) {
      setState(() => _failed = 'We could not show that area. Move the map to it yourself.');
      return;
    }
    final center = LatLng((place['lat'] as num).toDouble(), (place['lng'] as num).toDouble());
    _areaCenter = center;
    final bounds = place['bounds'];
    if (_mapReady && bounds is List && bounds.length == 4 && bounds.every((v) => v is num)) {
      final b = bounds.cast<num>();
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(LatLng(b[1].toDouble(), b[0].toDouble()), LatLng(b[3].toDouble(), b[2].toDouble())),
          padding: const EdgeInsets.all(24),
          maxZoom: 16,
        ),
      );
    } else {
      _moveMap(center, 14);
    }
    setState(() => _notice = 'Showing $name. Now type your street to place your kitchen.');
  }

  Future<void> _pickStreet(Map<String, dynamic> suggestion) async {
    final name = (suggestion['name'] ?? '').toString();
    final where = (suggestion['secondary'] ?? '').toString().split(', ').where((p) => p.isNotEmpty && p != name).firstOrNull;
    widget.address.text = where == null ? name : '$name, $where';
    _failed = '';
    _changed();
    final place = await _place(suggestion);
    if (!mounted) return;
    if (place == null) {
      setState(() => _failed = 'We could not find that street on the map. Tap your kitchen on the map instead.');
      return;
    }
    final lat = (place['lat'] as num).toDouble();
    final lng = (place['lng'] as num).toDouble();
    _setCoords(lat, lng);
    _moveMap(LatLng(lat, lng), 17);
    setState(() => _notice = "Pin placed on $name. Tap the map at your kitchen's exact spot to move it.");
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _failed = '';
      _locating = true;
    });
    try {
      final here = gpsSupported ? await currentPosition() : null;
      if (!mounted) return;
      if (here == null) {
        setState(
          () => _failed = gpsSupported
              ? 'Could not detect your location. Allow location access and try again, or search / tap the map instead.'
              : "This phone app can't detect your location yet. Search your area and street, or tap the map instead.",
        );
        return;
      }
      _setCoords(here.lat, here.lng);
      _areaCenter = LatLng(here.lat, here.lng);
      _moveMap(_areaCenter!, 17);
      final accuracy = here.accuracyM?.round() ?? 0;
      setState(
        () => _notice = accuracy > _roughFixM
            ? "Location detected, accurate to about $accuracy m. Check the pin and tap your kitchen's exact spot if needed."
            : 'Location detected. Check the pin is on your kitchen and tap the map to move it if needed.',
      );
      // Fill in the area and street the map knows here, without replacing what was typed.
      try {
        final found = await widget.client.request('/geo/places/reverse${ApiClient.qs({'lat': here.lat, 'lng': here.lng})}');
        if (found is Map) {
          final area = (found['area'] ?? '').toString();
          final street = (found['street'] ?? '').toString();
          if (widget.area.text.trim().isEmpty && area.isNotEmpty) widget.area.text = area;
          if (widget.address.text.trim().isEmpty && street.isNotEmpty) widget.address.text = area.isEmpty ? street : '$street, $area';
          _changed();
        }
      } catch (_) {
        // The coordinates are set; the vendor can still type the address.
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _typed(TextEditingController field) {
    final pair = _pair.firstMatch(field.text);
    if (pair != null) {
      widget.lat.text = pair.group(1)!;
      widget.lng.text = pair.group(2)!;
    }
    final c = _coords;
    if (c != null) _moveMap(LatLng(c.lat, c.lng), 15);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final coords = _coords;
    final hint = Text(
      'At your kitchen right now? Detect it automatically. Otherwise, search your area and street below or tap the map.',
      style: kText(11, color: K.stone500, height: 1.375),
    );
    final areaField = _labelled(
      'Area / neighbourhood',
      PlaceSearchField(
        client: widget.client,
        controller: widget.area,
        hint: 'e.g. Kimironko',
        maxLength: 120,
        error: widget.areaError,
        onSelect: _pickArea,
        onChanged: _changed,
      ),
      error: widget.areaError,
    );
    final streetField = _labelled(
      'Street address (optional)',
      PlaceSearchField(
        client: widget.client,
        controller: widget.address,
        hint: 'e.g. KG 11 Ave',
        maxLength: 200,
        near: _areaCenter,
        onSelect: _pickStreet,
        onChanged: _changed,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.brown50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: K.brown200),
          ),
          child: Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: K.brown700))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(
                  _locating ? 'Detecting your location…' : 'Use my current location',
                  style: kText(12, weight: FontWeight.w700, color: K.brown700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: K.brown700,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: K.brown300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(width: wide ? 12 : 0, height: wide ? 0 : 8),
              if (wide) Expanded(child: hint) else hint,
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: areaField),
              const SizedBox(width: 16),
              Expanded(child: streetField),
            ],
          )
        else ...[
          areaField,
          const SizedBox(height: 16),
          streetField,
        ],
        if (_notice.isNotEmpty || _failed.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _failed.isNotEmpty ? const Color(0xFFFFFBEB) : K.brown50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _failed.isNotEmpty ? K.amber200 : K.brown200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: _failed.isNotEmpty ? K.amber800 : K.brown700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _failed.isNotEmpty ? _failed : _notice,
                    style: kText(11, weight: FontWeight.w600, color: _failed.isNotEmpty ? K.amber800 : K.brown700),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labelled(
                'Latitude',
                MarketInput(
                  controller: widget.lat,
                  hint: 'e.g. -1.944100',
                  keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  error: widget.coordsError != null,
                  onChanged: (_) => _typed(widget.lat),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labelled(
                'Longitude',
                MarketInput(
                  controller: widget.lng,
                  hint: 'e.g. 30.061900',
                  keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  error: widget.coordsError != null,
                  onChanged: (_) => _typed(widget.lng),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: wide ? 256 : 224,
            decoration: BoxDecoration(
              border: Border.all(color: K.stone200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: coords == null ? const LatLng(kKigaliLat, kKigaliLng) : LatLng(coords.lat, coords.lng),
                initialZoom: coords == null ? 12 : 15,
                onMapReady: () => _mapReady = true,
                onTap: (_, point) => _setCoords(point.latitude, point.longitude),
              ),
              children: [
                TileLayer(urlTemplate: cartoTileUrl, userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile', retinaMode: true),
                if (coords != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(coords.lat, coords.lng),
                        width: 36,
                        height: 36,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, size: 36, color: K.brown700),
                      ),
                    ],
                  ),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 4, bottom: 2),
                    child: Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 9, color: Colors.black54)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Tap the map where your kitchen is. You can also paste "latitude, longitude" from Google Maps into either box.',
              ),
              if (coords != null) ...[
                const TextSpan(text: ' '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.google.com/maps?q=${coords.lat},${coords.lng}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Check on Google Maps',
                          style: kText(11, weight: FontWeight.w700, color: K.brown700),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.open_in_new, size: 12, color: K.brown700),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          style: kText(11, color: K.stone500, height: 1.4),
        ),
        if (widget.coordsError != null) ...[const SizedBox(height: 4), FieldError(widget.coordsError!)],
      ],
    );
  }

  Widget _labelled(String label, Widget field, {String? error}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label), field, if (error != null) FieldError(error)]);
}

/// A text box with place suggestions as the vendor types, like a maps search
/// box (the website's PlaceSearchInput). Typing only changes the text; picking
/// a suggestion calls [onSelect].
class PlaceSearchField extends StatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.client,
    required this.controller,
    required this.hint,
    required this.onSelect,
    this.onChanged,
    this.near,
    this.maxLength,
    this.error,
  });

  final ApiClient client;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback? onChanged;
  final LatLng? near;
  final int? maxLength;
  final String? error;

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  static const _kindIcons = {'area': Icons.place_outlined, 'street': Icons.route_outlined, 'place': Icons.apartment_outlined};
  static const _kindLabels = {'area': 'Area', 'street': 'Street', 'place': 'Place'};

  final _focus = FocusNode();
  Timer? _debounce;
  int _request = 0;
  List<Map<String, dynamic>> _suggestions = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Hide the suggestions once the box loses focus (after a tap on one lands).
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () => mounted ? setState(() => _suggestions = const []) : null);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    widget.onChanged?.call();
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    final request = ++_request;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final data = await widget.client.request(
          '/geo/places/autocomplete${ApiClient.qs({'q': q, 'lat': widget.near?.latitude, 'lng': widget.near?.longitude})}',
        );
        if (request != _request || !mounted) return;
        final list = data is Map && data['suggestions'] is List ? data['suggestions'] as List : const [];
        setState(() {
          _suggestions = [
            for (final s in list)
              if (s is Map) Map<String, dynamic>.from(s),
          ];
          _failed = false;
        });
      } catch (_) {
        if (request != _request || !mounted) return;
        setState(() {
          _suggestions = const [];
          _failed = true;
        });
      } finally {
        if (request == _request && mounted) setState(() => _loading = false);
      }
    });
  }

  void _choose(Map<String, dynamic> suggestion) {
    _request++; // drop any in-flight search
    _debounce?.cancel();
    setState(() {
      _suggestions = const [];
      _loading = false;
    });
    _focus.unfocus();
    widget.onSelect(suggestion);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MarketInput(
        controller: widget.controller,
        focusNode: _focus,
        hint: widget.hint,
        maxLength: widget.maxLength,
        error: widget.error != null,
        onChanged: _typed,
        suffix: _loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: K.stone400))
            : null,
      ),
      if (_failed && _focus.hasFocus)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Place search is unavailable right now. Type it and tap the map instead.', style: kText(11, color: K.stone500)),
        ),
      if (_suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: K.stone200),
            boxShadow: K.shadowMd,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final s in _suggestions)
                InkWell(
                  onTap: () => _choose(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(_kindIcons[s['kind']] ?? Icons.place_outlined, size: 16, color: K.brown500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (s['name'] ?? '').toString(),
                                style: kText(14, weight: FontWeight.w600, color: K.gray900),
                              ),
                              if ((s['secondary'] ?? '').toString().isNotEmpty)
                                Text(
                                  (s['secondary']).toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: kText(11, color: K.stone500),
                                ),
                            ],
                          ),
                        ),
                        if (_kindLabels[s['kind']] != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _kindLabels[s['kind']]!,
                            style: kText(10, weight: FontWeight.w700, color: K.stone400),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
