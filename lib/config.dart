/// App-wide settings.
///
/// The backend address works like the website's `VITE_API_BASE_URL`: pass it
/// at build time with `--dart-define=API_BASE_URL=https://api.example.rw/api/v1`,
/// or change it on the sign-in screen (saved on the device).
library;

import 'package:flutter/foundation.dart';

const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Default backend: the KitchenLink reference backend on the development
/// computer — `localhost` in the browser (`flutter run -d chrome`), and
/// 10.0.2.2 (the host machine) from the Android emulator.
String get kDefaultApiBaseUrl => _apiBaseUrlOverride.isNotEmpty
    ? _apiBaseUrlOverride
    : kIsWeb
        ? 'http://localhost:4000/api/v1'
        : 'http://10.0.2.2:4000/api/v1';

/// Where "Back to marketplace" goes: the KitchenLink website
/// (`--dart-define=MARKETPLACE_URL=https://…`).
const String kMarketplaceUrl = String.fromEnvironment('MARKETPLACE_URL', defaultValue: 'http://localhost:3000/');

/// Milliseconds before a request is abandoned (the website's `VITE_API_TIMEOUT`).
const int kApiTimeoutMs = int.fromEnvironment('API_TIMEOUT', defaultValue: 8000);

/// Optional CARTO basemap key (the website's `VITE_CARTO_API_KEY`).
const String kCartoApiKey = String.fromEnvironment('CARTO_API_KEY');

/// CARTO Voyager raster tiles: the same basemap the website draws with MapLibre.
String get cartoTileUrl =>
    'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
    '${kCartoApiKey.isEmpty ? '' : '?api_key=$kCartoApiKey'}';

/// Kigali city centre: where maps start when there is no position yet.
const double kKigaliLat = -1.9441;
const double kKigaliLng = 30.0619;
