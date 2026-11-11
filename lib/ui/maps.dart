import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../core/config/app_config.dart';
import 'format.dart';

const _kitchenColor = Color(0xFF8A5332);
const _customerColor = Color(0xFF047857);

LatLng? _point(dynamic lat, dynamic lng) {
  if (lat is! num || lng is! num) return null;
  if (!lat.isFinite || !lng.isFinite) return null;
  return LatLng(lat.toDouble(), lng.toDouble());
}

TileLayer _tiles() => TileLayer(urlTemplate: AppConfig.cartoTileUrl, userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile', retinaMode: true);

/// CARTO attribution, required by the basemap's terms.
Widget _attribution() => const Positioned(
      right: 4,
      bottom: 2,
      child: Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 9, color: Colors.black54)),
    );

MapOptions _framing(List<LatLng> points, {double zoom = 13}) {
  if (points.length >= 2) {
    return MapOptions(
      initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15),
    );
  }
  return MapOptions(initialCenter: points.isEmpty ? const LatLng(kKigaliLat, kKigaliLng) : points.first, initialZoom: points.isEmpty ? 12 : zoom);
}

Widget _pin(String emoji, Color background) => Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 13)),
    );

Widget _dot(Color color) => Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), spreadRadius: 3), const BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
    );

/// A rider moving along the road route to the kitchen, then the customer
/// (the website's LiveRouteMap). [geometry] is the route as [lng, lat] pairs.
class LiveRouteMap extends StatelessWidget {
  const LiveRouteMap({super.key, this.rider, this.kitchen, this.destination, this.geometry, this.height = 260});

  final LatLng? rider;
  final LatLng? kitchen;
  final LatLng? destination;
  final List<dynamic>? geometry;
  final double height;

  factory LiveRouteMap.kitchen(double lat, double lng, {double height = 220}) =>
      LiveRouteMap(kitchen: LatLng(lat, lng), height: height);

  @override
  Widget build(BuildContext context) {
    final route = <LatLng>[
      for (final pair in geometry ?? const [])
        if (pair is List && pair.length >= 2 && pair[0] is num && pair[1] is num) LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
    ];
    final points = [?rider, ?kitchen, ?destination, ...route];
    return SizedBox(
      height: height,
      child: Stack(children: [
        FlutterMap(
          // Re-framed when the phase changes the points in view.
          key: ValueKey('${kitchen}_${destination}_${route.length > 1}'),
          options: _framing(points, zoom: 15),
          children: [
            _tiles(),
            if (route.length > 1)
              PolylineLayer(polylines: [Polyline(points: route, color: const Color(0xFF2563EB), strokeWidth: 4.5)]),
            MarkerLayer(markers: [
              if (kitchen != null) Marker(point: kitchen!, width: 28, height: 28, child: _pin('🍳', _kitchenColor)),
              if (destination != null) Marker(point: destination!, width: 28, height: 28, child: _pin('🏠', _customerColor)),
              if (rider != null) Marker(point: rider!, width: 22, height: 22, child: _dot(const Color(0xFF2563EB))),
            ]),
          ],
        ),
        _attribution(),
      ]),
    );
  }
}

/// Admin live operations map: online delivery workers (blue = free, orange =
/// on a delivery, red = location too old to be offered orders), riders'
/// links to where they're heading, open kitchens and customers being served.
class OperationsMap extends StatefulWidget {
  const OperationsMap({super.key, required this.data, this.height = 440});

  final Json? data;
  final double height;

  @override
  State<OperationsMap> createState() => _OperationsMapState();
}

class _OperationsMapState extends State<OperationsMap> {
  final controller = MapController();
  bool framed = false;

  String _ago(dynamic iso) {
    final date = parseDate(iso);
    if (date == null) return 'never';
    final min = DateTime.now().difference(date).inMinutes;
    return min < 1 ? 'just now' : min < 60 ? '$min min ago' : '${(min / 60).round()} h ago';
  }

  void _showInfo(List<String> lines) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(lines[i], style: TextStyle(fontWeight: i == 0 ? FontWeight.w900 : FontWeight.w500, fontSize: i == 0 ? 16 : 13.5)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data ?? const {};
    final markers = <Marker>[];
    final links = <Polyline>[];
    final points = <LatLng>[];

    Marker marker(LatLng point, Widget child, List<String> info, {double size = 26}) {
      points.add(point);
      return Marker(point: point, width: size, height: size, child: GestureDetector(onTap: () => _showInfo(info), child: child));
    }

    for (final kitchen in jlist(data['kitchens'])) {
      final point = _point(kitchen['latitude'], kitchen['longitude']);
      if (point == null) continue;
      markers.add(marker(point, _pin('🍳', _kitchenColor), [jstr(kitchen['name']), 'Open · ${jstr(kitchen['neighborhood'], 'Kitchen')}']));
    }

    final onDelivery = <String, Json>{};
    for (final delivery in jlist(data['deliveries'])) {
      final driver = jmap(delivery['driver']);
      if (driver['id'] != null) onDelivery[driver['id'].toString()] = delivery;
      final destination = jmap(delivery['destination']);
      final point = _point(destination['latitude'], destination['longitude']);
      if (point != null) {
        markers.add(marker(point, _pin('🏠', _customerColor), [
          jstr(delivery['order_number']),
          jstr(destination['address'], 'Customer'),
          driver.isNotEmpty ? 'Rider: ${jstr(driver['name'])}' : 'Waiting for a rider · offered to ${jstr(delivery['offered_to'], '0')}',
        ]));
      }
      final fix = jmap(driver['location']);
      final from = _point(fix['latitude'], fix['longitude']);
      if (from != null) {
        final toKitchen = const ['assigned_to_driver', 'pending', 'ready_for_pickup'].contains(delivery['status']);
        final target = jmap(toKitchen ? delivery['kitchen'] : delivery['destination']);
        final to = _point(target['latitude'], target['longitude']);
        if (to != null) {
          links.add(Polyline(
            points: [from, to],
            color: (delivery['late'] == true ? const Color(0xFFDC2626) : const Color(0xFFF97316)).withValues(alpha: 0.8),
            strokeWidth: 2.5,
            pattern: StrokePattern.dashed(segments: const [8, 6]),
          ));
        }
      }
    }

    for (final driver in jlist(data['drivers'])) {
      final fix = jmap(driver['location']);
      final point = _point(fix['latitude'], fix['longitude']);
      if (point == null) continue;
      final delivery = onDelivery[driver['id']?.toString()];
      final dispatchable = driver['counts_for_dispatch'] == true;
      final color = !dispatchable ? const Color(0xFFDC2626) : delivery != null ? const Color(0xFFF97316) : const Color(0xFF2563EB);
      final vehicle = [jstr(driver['vehicle_type']), jstr(driver['plate_number'])].where((s) => s.isNotEmpty).join(' · ');
      markers.add(marker(point, _dot(color), [
        jstr(driver['name']),
        vehicle.isEmpty ? 'Delivery worker' : vehicle,
        delivery != null
            ? 'On ${jstr(delivery['order_number'])} · ${jstr(delivery['status_label'])}${delivery['late'] == true ? ' · LATE' : ''}'
            : 'Free',
        'Location ${_ago(fix['updated_at'])}${dispatchable ? '' : ' — too old to be offered orders'}',
        if (jstr(driver['phone']).isNotEmpty) jstr(driver['phone']),
      ], size: 20));
    }

    // Frame everything once, when the first data arrives.
    if (!framed && points.isNotEmpty && widget.data != null) {
      framed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (points.length == 1) {
          controller.move(points.first, 14);
        } else {
          controller.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(60), maxZoom: 14));
        }
      });
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(children: [
          FlutterMap(
            mapController: controller,
            options: const MapOptions(initialCenter: LatLng(kKigaliLat, kKigaliLng), initialZoom: 12),
            children: [_tiles(), PolylineLayer(polylines: links), MarkerLayer(markers: markers)],
          ),
          Positioned(left: 8, bottom: 16, child: _legend()),
          _attribution(),
        ]),
      ),
    );
  }

  Widget _legend() {
    Widget row(Widget mark, String text) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 1.5), child: Row(mainAxisSize: MainAxisSize.min, children: [mark, const SizedBox(width: 6), Text(text)]));
    Widget circle(Color color) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF57534E)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          row(circle(const Color(0xFF2563EB)), 'Free delivery worker'),
          row(circle(const Color(0xFFF97316)), 'On a delivery'),
          row(circle(const Color(0xFFDC2626)), 'Location too old'),
          row(const Text('🍳'), 'Open kitchen   🏠 Customer'),
        ]),
      ),
    );
  }
}
