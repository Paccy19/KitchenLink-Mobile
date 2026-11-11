// Support code for the vendor end-to-end tests (test/e2e/).
//
// These tests drive the REAL screens with the REAL ApiClient, token store and
// repositories against a REAL running KitchenLink backend. Only two things are
// faked, because they are operating-system dialogs a test cannot operate:
//   - the keystore behind flutter_secure_storage (an in-memory map answers the
//     same platform channel, so SecureTokenStore / RoleStore run unchanged);
//   - the file picker (it hands back real files created on disk).
//
// Run them against a SCRATCH backend (never a database that matters):
//   cd KitchenLink-backend && PORT=4101 MONGODB_URI=mongodb://127.0.0.1:27017/kl_scratch node src/server.js
//   flutter test test/e2e \
//     --dart-define=API_BASE_URL=http://127.0.0.1:4101/api/v1 \
//     --dart-define=E2E_ADMIN_PASSWORD=<the scratch admin's changed password>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter/services.dart' show ByteData, FontLoader, rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/core/utils/uploads.dart';

const String kE2eApi = String.fromEnvironment('API_BASE_URL');
const String kE2eAdminPassword = String.fromEnvironment('E2E_ADMIN_PASSWORD');

/// The tests only run when pointed at a backend explicitly.
bool get e2eEnabled => kE2eApi.isNotEmpty && kE2eAdminPassword.isNotEmpty;

/// Starts every test with an empty phone keystore. The plugin's own in-memory
/// mock answers, so SecureTokenStore / RoleStore / ServerAddressStore run
/// unchanged. It survives "app restarts" inside one test (the widget tree is
/// rebuilt, the storage is kept), like the real keystore does.
void freshKeystore([Map<String, String> initial = const {}]) => FlutterSecureStorage.setMockInitialValues({...initial});

/// What is stored on the "phone" right now.
Future<Map<String, String>> keystoreContents() => const FlutterSecureStorage().readAll();

/// Gives back real files from disk, like the system file picker would.
class FakePicker implements MediaPicker {
  FakePicker(this.image, this.documents);
  final PickedUpload? image;
  final List<PickedUpload> documents;

  @override
  Future<PickedUpload?> pickImage({required bool fromCamera}) async => image;

  @override
  Future<List<PickedUpload>> pickDocuments() async => documents;
}

/// A real 1x1 PNG and a tiny PDF in a temp directory.
class E2eFiles {
  E2eFiles._(this.png, this.pdf);

  final PickedUpload png;
  final PickedUpload pdf;

  static E2eFiles create() {
    final dir = Directory.systemTemp.createTempSync('kl_e2e_');
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfHiEY0liH8OITBAtzm7PV1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBAOaBS/AeSBkAAAAASUVORK5CYII=',
    );
    final pngFile = File('${dir.path}/dish.png')..writeAsBytesSync(pngBytes);
    final pdfBytes = utf8.encode('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n');
    final pdfFile = File('${dir.path}/licence.pdf')..writeAsBytesSync(pdfBytes);
    return E2eFiles._(
      PickedUpload(path: pngFile.path, name: 'dish.png', sizeBytes: pngBytes.length),
      PickedUpload(path: pdfFile.path, name: 'licence.pdf', sizeBytes: pdfBytes.length),
    );
  }
}

/// Raw JSON calls to the backend, for building fixtures (an approved kitchen, a
/// customer's order) and for checking what the app really did on the server.
/// Not used to log the app in: the app always signs in through its own screens
/// or restores a token a real backend issued.
class Backend {
  Backend(this.base);
  final String base;

  Future<(int, dynamic)> call(String method, String path, {Object? body, String? token}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$base$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> ok(String method, String path, {Object? body, String? token}) async {
    final (status, json) = await call(method, path, body: body, token: token);
    if (status < 200 || status >= 300) throw StateError('$method $path -> $status $json');
    return (json as Map).cast<String, dynamic>();
  }

  /// A real backend login (the scratch server returns `dev_otp`). Waits out the
  /// server's 60 s resend cooldown if this phone asked for a code recently.
  Future<String> vendorToken(String phone) async {
    final code = await _otp('/vendor/auth/send-otp', {'phone': phone});
    final json = await ok('POST', '/vendor/auth/verify-otp', body: {'phone': phone, 'code': code});
    return json['token'] as String;
  }

  Future<String> customerToken(String phone, String name) async {
    final code = await _otp('/auth/send-otp', {'phone_number': phone, 'name': name});
    final json = await ok('POST', '/auth/verify-otp', body: {'phone_number': phone, 'code': code, 'name': name});
    return json['token'] as String;
  }

  Future<String> _otp(String path, Map<String, Object?> body) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final (status, json) = await call('POST', path, body: body);
      if (status == 200) return (json as Map)['dev_otp'] as String;
      if (status == 429) {
        await Future<void>.delayed(const Duration(seconds: 61));
        continue;
      }
      throw StateError('POST $path -> $status $json');
    }
    throw StateError('Could not get a code for $path');
  }

  Future<String> adminToken() async {
    final json = await ok('POST', '/admin/auth/login', body: {'email': 'admin@foodkitchen.rw', 'password': kE2eAdminPassword});
    return json['token'] as String;
  }

  /// What an admin does for a new kitchen: review its documents, then approve it.
  Future<void> approveVendor(String vendorId) async {
    final admin = await adminToken();
    await ok('POST', '/admin/vendors/$vendorId/documents/review', token: admin);
    await ok('PATCH', '/admin/vendors/$vendorId/status', body: {'status': 'approved'}, token: admin);
  }
}

/// Lets real network I/O finish while the widget tree keeps pumping.
extension E2eTester on WidgetTester {
  Future<void> settle({int rounds = 6, int realMs = 200}) async {
    for (var i = 0; i < rounds; i++) {
      await runAsync(() => Future<void>.delayed(Duration(milliseconds: realMs)));
      await pump(const Duration(milliseconds: 120));
    }
  }

  /// Ends a test cleanly: removes the app and lets idle HTTP keep-alive timers
  /// (created under the test clock by real requests) expire.
  Future<void> finish() async {
    await pumpWidget(const SizedBox());
    await pump(const Duration(seconds: 6));
  }

  /// Waits (real time) until [finder] matches, up to [seconds].
  Future<bool> until(Finder finder, {int seconds = 20}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (finder.evaluate().isNotEmpty) {
        // Let the page finish sliding in (iOS-style transitions take ~0.5 s)
        // so the next tap lands where the user would tap.
        for (var i = 0; i < 6; i++) {
          await pump(const Duration(milliseconds: 100));
        }
        return true;
      }
      await runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await pump(const Duration(milliseconds: 120));
    }
    return finder.evaluate().isNotEmpty;
  }
}

/// Collects "RenderFlex overflowed" reports instead of failing the test, for
/// screens that belong to other roles (e.g. the marketplace). Every other error
/// still fails the test. Returns the collected messages.
List<String> collectOverflows() {
  final collected = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed by')) {
      collected.add(text.split('\n').first);
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  return collected;
}

/// `flutter test` draws text in the square "Ahem" font unless a font is loaded,
/// which makes text far wider than on a phone and invents layout overflows.
/// The kitchen and delivery themes use the platform default font (Roboto on
/// Android), so load Roboto from the Flutter SDK; the marketplace and admin
/// themes use PlusJakartaSans from the app's own assets.
Future<void> loadAppFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '/home/debugger/snap/flutter/common/flutter';
  final roboto = FontLoader('Roboto');
  for (final file in ['Regular', 'Medium', 'Bold']) {
    final path = '$sdk/bin/cache/artifacts/material_fonts/Roboto-$file.ttf';
    if (File(path).existsSync()) roboto.addFont(Future.value(ByteData.view(File(path).readAsBytesSync().buffer)));
  }
  await roboto.load();
  final jakarta = FontLoader('PlusJakartaSans');
  for (final weight in [400, 500, 600, 700, 800]) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
  }
  await jakarta.load();
}

/// Registers a kitchen straight on the backend (fixture for tests that are not about registration).
Future<(int, dynamic)> registerVendorRaw(Backend backend, E2eFiles files, String phone, {required String name}) async {
  final request = await HttpClient().postUrl(Uri.parse('${backend.base}/vendor/auth/register'));
  final boundary = 'e2eboundary${DateTime.now().microsecondsSinceEpoch}';
  request.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
  final categories = await backend.ok('GET', '/home/categories');
  final categoryId = ((categories['categories'] as List).first as Map)['id'];
  final fields = {
    'name': name,
    'owner_name': 'Fixture Owner',
    'vendor_type': 'restaurant',
    'phone': phone,
    'description': 'A fixture kitchen created by the e2e test.',
    'location': '{"latitude":-1.95,"longitude":30.09,"address":"KG 7 Ave","neighborhood":"Kimihurura"}',
    'food_categories': '["$categoryId"]',
    'operating_hours': '[{"day":"monday","open_time":"08:00","close_time":"20:00","is_closed":false}]',
    'payment_information': '{"payout_method":"mobile_money","account_name":"Fixture Owner","mobile_money_number":"$phone"}',
  };
  final body = BytesBuilder();
  void text(String s) => body.add(s.codeUnits);
  fields.forEach((k, v) => text('--$boundary\r\nContent-Disposition: form-data; name="$k"\r\n\r\n$v\r\n'));
  text('--$boundary\r\nContent-Disposition: form-data; name="documents"; filename="licence.pdf"\r\nContent-Type: application/pdf\r\n\r\n');
  body.add(File(files.pdf.path).readAsBytesSync());
  text('\r\n--$boundary--\r\n');
  request.add(body.toBytes());
  final response = await request.close();
  final textBody = await response.transform(utf8.decoder).join();
  return (response.statusCode, textBody.isEmpty ? null : jsonDecode(textBody));
}


Future<Map<String, dynamic>> registerVendorFixture(Backend backend, E2eFiles files, String phone, {required String name}) async {
  final (status, json) = await registerVendorRaw(backend, files, phone, name: name);
  if (status != 201) throw StateError('fixture registration failed: $status $json');
  return (json as Map).cast<String, dynamic>();
}
