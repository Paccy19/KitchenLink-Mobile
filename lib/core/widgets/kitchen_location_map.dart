import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// The kitchen's spot on a map, like the website's KitchenCoordinatesPicker:
/// tap the map or drag the pin to set the latitude / longitude boxes, and
/// the pin follows whatever is typed or found by the place search. Never
/// reads the phone's GPS, since the vendor may be somewhere other than the
/// kitchen.
///
/// It works on the form's own [latitude] and [longitude] controllers, so the
/// form keeps validating and saving them as before. Pasting
/// "latitude, longitude" (e.g. from Google Maps) into either box fills both.
class KitchenLocationMap extends StatefulWidget {
  const KitchenLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.enabled = true,
    this.place = 'your kitchen',
    this.height = 240,
  });

  final TextEditingController latitude;
  final TextEditingController longitude;

  /// False shows the map and pin without letting them be changed.
  final bool enabled;

  /// Names the spot in the help text ("Tap the map where your kitchen is").
  final String place;
  final double height;

  @override
  State<KitchenLocationMap> createState() => _KitchenLocationMapState();
}

/// Kigali city centre: where the map starts when there is no spot yet.
const _kigali = LatLng(-1.9441, 30.0619);

/// The website's pin colour (`#8a5332`).
const _pinColor = Color(0xFF8A5332);

// "-1.9441, 30.0619" pasted into one box.
final _pair = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[,\s]\s*(-?\d+(?:\.\d+)?)\s*$');

class _KitchenLocationMapState extends State<KitchenLocationMap> {
  final _map = MapController();
  final _mapKey = GlobalKey();
  bool _ready = false;
  bool _dragging = false;

  /// The spot in the boxes; null unless both are valid coordinates.
  LatLng? get _point {
    final lat = double.tryParse(widget.latitude.text.trim());
    final lng = double.tryParse(widget.longitude.text.trim());
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  @override
  void initState() {
    super.initState();
    widget.latitude.addListener(_onText);
    widget.longitude.addListener(_onText);
  }

  @override
  void didUpdateWidget(KitchenLocationMap old) {
    super.didUpdateWidget(old);
    if (old.latitude != widget.latitude || old.longitude != widget.longitude) {
      old.latitude.removeListener(_onText);
      old.longitude.removeListener(_onText);
      widget.latitude.addListener(_onText);
      widget.longitude.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.latitude.removeListener(_onText);
    widget.longitude.removeListener(_onText);
    _map.dispose();
    super.dispose();
  }

  /// Typed, pasted or searched coordinates: split a pasted pair, then bring
  /// the pin into view.
  void _onText() {
    for (final box in [widget.latitude, widget.longitude]) {
      final match = _pair.firstMatch(box.text);
      if (match != null) {
        // Fills both boxes; their listeners run again with plain numbers.
        widget.latitude.text = match.group(1)!;
        widget.longitude.text = match.group(2)!;
        return;
      }
    }
    if (!mounted) return;
    setState(() {});
    final point = _point;
    if (point == null || !_ready || _dragging) return;
    final camera = _map.camera;
    if (!camera.visibleBounds.contains(point) || camera.zoom < 14) {
      _map.move(point, math.max(camera.zoom, 16));
    }
  }

  void _set(LatLng point) {
    widget.latitude.text = point.latitude.toStringAsFixed(6);
    widget.longitude.text = point.longitude.toStringAsFixed(6);
  }

  /// Where a finger is on the map, as a map position.
  LatLng? _at(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _map.camera.offsetToCrs(box.globalToLocal(globalPosition));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = _point;
    final start = point ?? _kigali;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            key: _mapKey,
            height: widget.height,
            child: Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: start,
                  initialZoom: point == null ? 12 : 16,
                  // While the pin is dragged the map stays still.
                  interactionOptions: InteractionOptions(
                    flags: _dragging ? InteractiveFlag.none : InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onMapReady: () => _ready = true,
                  onTap: widget.enabled ? (_, latLng) => _set(latLng) : null,
                ),
                children: [
                  TileLayer(urlTemplate: AppConfig.cartoTileUrl, userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile', retinaMode: true),
                  if (point != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        // The pin's tip sits on the spot.
                        alignment: Alignment.topCenter,
                        child: Semantics(
                          label: 'Kitchen location pin${widget.enabled ? '. Drag to move it' : ''}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: widget.enabled ? (_) => setState(() => _dragging = true) : null,
                            onPanUpdate: widget.enabled
                                ? (details) {
                                    final next = _at(details.globalPosition);
                                    if (next != null) _set(next);
                                  }
                                : null,
                            onPanEnd: widget.enabled ? (_) => setState(() => _dragging = false) : null,
                            onPanCancel: widget.enabled ? () => setState(() => _dragging = false) : null,
                            child: Icon(Icons.location_on, size: 48, color: _pinColor, shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))]),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
              // Zoom buttons (the website's NavigationControl).
              Positioned(
                right: 8,
                top: 8,
                child: Column(children: [
                  _zoomButton(Icons.add, 'Zoom in', 1),
                  const SizedBox(height: 6),
                  _zoomButton(Icons.remove, 'Zoom out', -1),
                ]),
              ),
              const Positioned(
                right: 6,
                bottom: 4,
                child: Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 9, color: Colors.black54)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.enabled
            ? 'Tap the map where ${widget.place} is, or drag the pin. You can also paste "latitude, longitude" from Google Maps into either box.'
            : 'This is where customers find ${widget.place}.',
        style: theme.textTheme.bodySmall,
      ),
      if (point != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps?q=${point.latitude},${point.longitude}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Check on Google Maps'),
          ),
        ),
    ]);
  }

  Widget _zoomButton(IconData icon, String tooltip, double step) => Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18, color: Colors.black87),
          onPressed: () {
            if (!_ready) return;
            final camera = _map.camera;
            _map.move(camera.center, (camera.zoom + step).clamp(3, 19).toDouble());
          },
        ),
      );
}
