import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vendor PREVIEW MODE (temporary, development only).
///
/// When on, the vendor app opens straight into the dashboard without a
/// sign-in and every request is answered on the device from sample data
/// (see `preview_adapter.dart`). Nothing is sent to the KitchenLink server and
/// every write is refused.
///
/// It is off everywhere except the dedicated entry point
/// `lib/main_vendor_preview.dart`. The unified app (`lib/main.dart`) never
/// turns it on, and the real sign-in code is not touched by it.
final previewModeProvider = Provider<bool>((ref) => false);

/// The placeholder "token" preview mode signs in with. It is never sent
/// anywhere: the preview adapter answers on the device.
const kPreviewToken = 'preview-mode-token';

/// Error code of every write refused in preview mode.
const kPreviewErrorCode = 'PREVIEW_MODE';
