/// Shows a downloaded private file (e.g. a vendor's PDF): a viewer app on a
/// phone, a new browser tab on the web.
library;

export 'open_document_io.dart' if (dart.library.js_interop) 'open_document_web.dart';
