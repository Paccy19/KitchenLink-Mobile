import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/navigation.dart';

/// Kigali centre, where the map starts with nothing to show.
const _kigali = LatLng(-1.9441, 30.0619);

LatLng _ll(GeoPoint point) => LatLng(point.latitude, point.longitude);

/// The road route to the kitchen, then the customer, with the rider on it.
/// The camera frames the whole route whenever the destination changes, and
/// otherwise leaves the worker's own pans and zooms alone.
class RouteMap extends StatefulWidget {
  const RouteMap({super.key, required this.navigation, this.rider, this.height = 240});

  final TripNavigation navigation;

  /// The phone's own newest fix (fresher than the server's copy).
  final GeoPoint? rider;
  final double height;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _controller = MapController();
  String? _framedTarget;
  bool _ready = false;

  List<LatLng> get _route => [for (final point in widget.navigation.geometry) _ll(point)];

  LatLng? get _rider {
    final point = widget.rider ?? widget.navigation.driverPosition;
    return point == null ? null : _ll(point);
  }

  List<LatLng> get _framePoints => [
        ?_rider,
        if (widget.navigation.targetPoint != null) _ll(widget.navigation.targetPoint!),
        ..._route,
      ];

  @override
  void didUpdateWidget(RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && _framedTarget != widget.navigation.target) _frame();
  }

  void _frame() {
    final points = _framePoints;
    _framedTarget = widget.navigation.target;
    if (points.length >= 2) {
      _controller.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(44), maxZoom: 16));
    } else if (points.length == 1) {
      _controller.move(points.first, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nav = widget.navigation;
    final rider = _rider;
    final kitchen = nav.kitchen == null ? null : _ll(nav.kitchen!);
    final customer = nav.destination == null ? null : _ll(nav.destination!);
    final points = _framePoints;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: points.isEmpty ? _kigali : points.first,
              initialZoom: points.isEmpty ? 12 : 14,
              initialCameraFit: points.length >= 2
                  ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(44), maxZoom: 16)
                  : null,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                _ready = true;
                _framedTarget = nav.target;
              },
            ),
            children: [
              TileLayer(urlTemplate: AppConfig.cartoTileUrl, userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile', retinaMode: true),
              if (_route.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(points: _route, strokeWidth: 7, color: Colors.white.withValues(alpha: 0.9)),
                  Polyline(points: _route, strokeWidth: 4.5, color: DriverColors.brand),
                ]),
              MarkerLayer(markers: [
                if (kitchen != null)
                  Marker(
                    point: kitchen,
                    width: 34,
                    height: 34,
                    child: _Pin(icon: Icons.storefront_rounded, color: const Color(0xFFB7791F), dim: !nav.headingToKitchen),
                  ),
                if (customer != null)
                  Marker(
                    point: customer,
                    width: 34,
                    height: 34,
                    child: _Pin(icon: Icons.home_rounded, color: const Color(0xFF047857), dim: nav.headingToKitchen),
                  ),
                if (rider != null)
                  Marker(point: rider, width: 26, height: 26, child: _RiderDot(color: scheme.primary, stale: nav.positionStale)),
              ]),
            ],
          ),
          Positioned(
            right: 6,
            bottom: 4,
            child: Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 9, color: Colors.black.withValues(alpha: 0.55))),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'Show the whole route',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.black87, size: 20),
                onPressed: _frame,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color, this.dim = false});

  final IconData icon;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

class _RiderDot extends StatelessWidget {
  const _RiderDot({required this.color, this.stale = false});

  final Color color;
  final bool stale;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: stale ? Colors.grey : color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3.5),
          boxShadow: [
            BoxShadow(color: (stale ? Colors.grey : color).withValues(alpha: 0.3), spreadRadius: 6),
            const BoxShadow(color: Colors.black26, blurRadius: 6),
          ],
        ),
      );
}
