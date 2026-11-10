# kitchenlink_mobile

One app for every role (marketplace, vendor, delivery worker, admin):

| Run | Entry point | What it is |
| --- | --- | --- |
| `flutter run` | `lib/main.dart` | The unified app. Choose **Vendor** at "Sign in" for the kitchen app, real sign-in + real backend |
| `flutter run -t lib/main_vendor_preview.dart` | `lib/main_vendor_preview.dart` | **Vendor preview**: the same vendor app, no sign-in, sample data only |

## Vendor preview mode (development only)

Opens straight into the vendor dashboard so every vendor screen can be seen
without an account:

    flutter run -t lib/main_vendor_preview.dart            # pick a device, e.g. -d linux or -d chrome

- Every response comes from sample data on the device (`lib/preview/`), shaped
  like the real backend's JSON and parsed by the app's real models.
- No request ever reaches a server, and every write (create, edit, status
  change, withdrawal, upload, sign-out) is refused with a "Preview mode" message.
- A banner on every screen says it is preview mode.
- Real sign-in is untouched: `flutter run` (then Sign in → Vendor) uses the real
  backend (`--dart-define=API_BASE_URL=http://<host>:4000/api/v1`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
