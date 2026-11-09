# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

One Flutter app, **KitchenLink**, for every kind of user. Its single entry point is `lib/main.dart`. It talks to the KitchenLink backend (`../KitchenLink-backend`) using the same endpoints as the website (`../KitchenLink-frontend/API_CONTRACT.md` and its `src/api/`).

**The front door (`lib/root/`), modelled on the website:**
- The app opens on the public marketplace.
- **Sign in** opens "How do you want to sign in?", the same four choices as the website's `RoleSelectModal.jsx`: Customer, Vendor, Delivery Worker and Admin.
- Each choice leads to that role's own sign-in. Each role has its own endpoint and token, as on the backend.
- Every role's sign-in screen has an "Other ways to sign in" button (`OtherSignInButton`) back to the marketplace.
- `KitchenLinkRoot` remembers the last role (`ofk_app_role` in secure storage), so a kitchen or delivery worker reopening the app goes straight to their screens.
- Switching role rebuilds that role's screens from scratch (`KeyedSubtree` per role).
- Customer sign-in, cart and orders aren't built in the app yet. Choosing Customer keeps you on the marketplace with a notice.

| Role | Built by | Stack | Code lives in |
| --- | --- | --- | --- |
| Marketplace (customers) | `buildMarketApp()` in `lib/client/market_app.dart` | Provider + `package:http` | `lib/client/` (+ `lib/api/`, `lib/config.dart`) |
| Admin | `buildAdminApp()` in `lib/screens/admin_app.dart` | Provider + `package:http`, imperative navigation | `lib/api/`, `lib/state/`, `lib/screens/`, `lib/nav/`, `lib/ui/`, `lib/demo/`, `lib/config.dart` |
| Kitchen (vendor) | `KitchenLinkApp` in `lib/app/app.dart` | Riverpod 3 + go_router + Dio | `lib/app/`, `lib/core/`, `lib/features/` |
| Delivery worker (driver) | `KitchenLinkDeliveryApp` in `lib/driver/app/driver_app.dart` | Riverpod 3 + go_router + Dio + geolocator | `lib/driver/`, plus the shared `lib/core/` |

**Two stacks for now.** The marketplace and admin halves (Provider/http) share no code with the kitchen and delivery halves (Riverpod/Dio). The plan is to move everything to Riverpod step by step. Until then, keep each change inside the half that owns it, and don't bring Provider into a Riverpod half or the reverse. The kitchen and delivery halves share `lib/core/`, so a change there affects both. Each role still has its own `MaterialApp` and theme.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                                   # all tests
flutter test test/features/session_test.dart   # one file
flutter test --plain-name "a stored token restores the session"   # one test by name
flutter test test/driver/driver_test.dart      # delivery worker tests
flutter test test/root_test.dart               # front door (role choice) tests
flutter run --dart-define=DEMO_MODE=false      # the app, against a real backend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:4000/api/v1 --dart-define=DEMO_MODE=false   # web, always served on localhost:5300 (web_dev_config.yaml)
flutter build apk --dart-define=API_BASE_URL=https://api.example.rw/api/v1 --dart-define=DEMO_MODE=false
```

Build-time settings use `--dart-define`:
- **API address.** Use `API_BASE_URL` (or `--dart-define-from-file=<file>.json`, a JSON file of defines you create; none ships in the repo). The default is `10.0.2.2:4000` (the Android emulator's address for the host computer), or `localhost:4000` on web for the admin app. A real phone needs the computer's LAN IP, which can also be typed on the sign-in screen and is saved on the device.
- **Admin role only:** `DEMO_MODE` defaults to **true**. The admin screens answer every call on the device from `lib/demo/demo_server.dart` (any email and password, any code `123456`) unless it's built with `--dart-define=DEMO_MODE=false`. The other roles have no demo mode and always need a backend.
- **Other defines:** `MARKETPLACE_URL`, `API_TIMEOUT` and `CARTO_API_KEY`.

**Toolchain:** this machine has Flutter 3.38.7 / Dart 3.10.7. `pubspec.yaml` is pinned for them (`sdk: ^3.10.0`, `go_router ^17`, `flutter_riverpod ^3.3`, `geolocator ^14`). The Android build files use the Flutter 3.38 template's plugin versions (AGP 8.11.1, Kotlin 2.2.20) with Gradle 9.1.0. Gradle has to be 9.1 or newer because the only JDK here is Android Studio's bundled JDK 25, and Gradle 8.x refuses Java 25. Don't raise either without upgrading Flutter. Linting is `flutter_lints` with no custom rules.

## Kitchen (vendor) architecture (`lib/core`, `lib/features`)

- Each feature folder (auth, dashboard, orders, menu, wallet, promotions, chat, notifications, settings, support) has four layers: `data/` (a repository that calls the API), `models/` (JSON parsing and payload building), `application/` (Riverpod notifiers) and `presentation/` (screens and widgets).
- `lib/core/providers.dart` wires the shared `ApiClient` (Dio), `TokenStore` (flutter_secure_storage) and every repository.
- **Routing:** `lib/app/router.dart` uses go_router with one global `redirect` driven by the session status (`appRedirect`). It has a splash screen, `/offline` (no connection at launch), `/blocked` (suspended or rejected account) and login/register screens. The five main tabs sit in a `StatefulShellRoute`: dashboard, orders, menu, wallet and more. A deep link is remembered across sign-in.
- **Polling:** `lib/core/polled_notifier.dart` is the base for live screens. It loads once and then refreshes in the background. A failed background refresh keeps the last good data and never replaces it with an error. Retries are turned off globally (`ProviderScope(retry: (_, _) => null)`), so a failure shows "Try again".
- **Session rules** (`test/features/session_test.dart`): a 401 on a signed-in call ends the session, but a 401 on a public call and a 500 don't. No network at launch keeps the token. Suspended and pending-review accounts are reported separately.
- The backend decides which order actions are allowed (`allowed_next_statuses`). The app never offers "complete". Validation in models (big-event guest ranges, delivery fee ranges, bank account length) mirrors the backend and has tests in `test/features/models_test.dart`.

## Delivery worker architecture (`lib/driver`)

It covers the website's delivery worker pages (`src/pages/driver/`, `src/context/DriverContext.jsx`): offers, active trip, earnings and wallet, history, profile, notifications and support.
- **Layers:** `models/` (JSON parsing), `data/driver_repository.dart` (every `/driver/*` endpoint, one for one with the website's `src/api/driverApi.js`), `application/` (session, live data, GPS, actions) and `presentation/`.
- **Shared code:**
  - `lib/driver/app/driver_app.dart` (`driverOverrides`) gives the app its own token key, `ofk_driver_token`.
  - It reuses the vendor app's `WithdrawScreen` and support screens by pointing `WalletRepository` and `SupportRepository` at `/driver/wallet` and `/driver/support` (`basePath`).
  - Tests skip the first override (`driverOverrides.skip(1)`) to use a memory token store, so keep the token store first in that list.
- **Trip steps come from the server.** `TripAction.forDelivery` offers pickup or start only when `allowed_next_statuses` contains them. The order is assigned → picked_up → out_for_delivery, and then the customer's 6-digit code (`otp_code`, plus an optional `proof_photo_base64` data URI) completes it. Picking up before `kitchen_ready` is refused by the server, and the UI disables it too.
- **Polling:**
  - Offers, the active trip and stats refresh every 10 s.
  - Notifications refresh every 15 s. New offers and trip updates raise `offerAlertProvider` and `tripAlertProvider`, which the shell turns into haptics and a snackbar.
  - Offers load only while the worker is online.
- **GPS** (`application/location.dart`, `LocationTracker`) runs in the foreground only, with no background location.
  - While online: the position is sent once a minute.
  - During a trip: a live stream, sent at most every 4 s when the rider has moved 8 m or more, and at least every 15 s (`shouldSendLiveFix`, the website's rules).
  - Going online shares the position first, so the very first offers are nearby.
- **One trip at a time.** The backend allows several (`max_active_deliveries`), but `/driver/deliveries/active` returns only the newest, so offers are blocked while a trip is open, which keeps an older trip from disappearing.
- **Motion** (`presentation/widgets/motion.dart`):
  - Springs use damping ratio and response.
  - Press feedback starts on touch-down (`PressScale`).
  - Irreversible trip steps use `SlideToConfirm`: it tracks the finger 1:1, projects momentum, rubber-bands at the ends, and has a tap action for screen readers.
  - With the phone's reduce-motion setting on, it uses cross-fades and no springs.

## Admin architecture (`lib/api`, `lib/state`, `lib/screens`)

- `AdminSession` (a ChangeNotifier) holds the token and restores it at launch. `lib/screens/admin_app.dart` switches between the splash, `LoginScreen` and `AdminShell`.
- `lib/api/admin_api.dart` mirrors the website's `src/api/adminApi.js` one for one: the same paths, bodies and query parameters.
- `lib/nav/admin_nav.dart` maps website notification links (`/admin-dashboard/...`) to the app's pages.
- Pages are in `lib/screens/pages/`, and shared UI (theme, format, validation, vendor types) is in `lib/ui/`.
- **When you add or change an admin endpoint, update `lib/demo/demo_server.dart` too**, because the admin app runs on it by default.

## Shared rules

- Money is whole RWF from `*_rwf` fields, and the server computes every amount.
- Show the backend's `error.message` to the user.
- Relative upload paths are resolved against the API origin.
- Changing an endpoint here means checking the backend route and the website's `src/api/` for the same change.
