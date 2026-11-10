/// App-wide settings for the marketplace and admin screens.
///
/// The backend address (the website's `VITE_API_BASE_URL`) is shared by every
/// role and lives in `AppConfig.current` (`lib/core/config/app_config.dart`):
/// `--dart-define=API_BASE_URL=…` at build time, or the address saved on a
/// sign-in screen.
library;

/// Where "Back to marketplace" goes: the KitchenLink website
/// (`--dart-define=MARKETPLACE_URL=https://…`).
const String kMarketplaceUrl = String.fromEnvironment('MARKETPLACE_URL', defaultValue: 'http://localhost:3000/');

/// Milliseconds before a request is abandoned (the website's `VITE_API_TIMEOUT`).
const int kApiTimeoutMs = int.fromEnvironment('API_TIMEOUT', defaultValue: 8000);

/// Kigali city centre: where maps start when there is no position yet.
const double kKigaliLat = -1.9441;
const double kKigaliLng = 30.0619;
