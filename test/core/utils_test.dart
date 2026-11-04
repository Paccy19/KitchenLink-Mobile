import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/router.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/json.dart';
import 'package:kitchenlink_mobile/core/utils/formatters.dart';
import 'package:kitchenlink_mobile/core/utils/media_url.dart';
import 'package:kitchenlink_mobile/core/utils/uploads.dart';
import 'package:kitchenlink_mobile/core/utils/validators.dart';
import 'package:kitchenlink_mobile/features/auth/application/session.dart';

void main() {
  group('Rwanda phone validation', () {
    test('accepts the forms the backend accepts', () {
      for (final ok in ['0788123456', '+250788123456', '250 788 123 456', '0721234567', '0731234567', '0791234567']) {
        expect(Validators.isValidPhone(ok), isTrue, reason: ok);
      }
    });
    test('rejects other numbers', () {
      for (final bad in ['0711234567', '078812345', '12345', '+254788123456', '']) {
        expect(Validators.isValidPhone(bad), isFalse, reason: bad);
      }
    });
    test('normalises to the local form', () {
      expect(Validators.toLocalPhone('+250 788-123-456'), '0788123456');
    });
    test('mobile-money network by prefix', () {
      expect(Validators.networkOfPhone('0788123456'), 'mtn');
      expect(Validators.networkOfPhone('0731234567'), 'airtel');
    });
  });

  test('OTP must be exactly six digits', () {
    expect(Validators.otp('123456'), isNull);
    expect(Validators.otp('12345'), isNotNull);
    expect(Validators.otp('12345a'), isNotNull);
  });

  test('money is whole RWF with separators', () {
    expect(formatRwf(2500), 'RWF 2,500');
    expect(formatRwf(1234567), 'RWF 1,234,567');
    expect(formatRwf(null), 'RWF 0');
  });

  group('image URLs', () {
    const config = AppConfig(apiBaseUrl: 'http://192.168.1.20:4000/api/v1');
    test('relative paths use the API server', () {
      expect(resolveMediaUrl('/uploads/a.jpg', config: config), 'http://192.168.1.20:4000/uploads/a.jpg');
    });
    test('localhost URLs are re-pointed at the API host', () {
      expect(resolveMediaUrl('http://localhost:4000/uploads/a.jpg', config: config), 'http://192.168.1.20:4000/uploads/a.jpg');
    });
    test('real absolute URLs are untouched', () {
      expect(resolveMediaUrl('https://cdn.kitchenlink.rw/a.jpg', config: config), 'https://cdn.kitchenlink.rw/a.jpg');
    });
    test('empty gives null', () => expect(resolveMediaUrl('  ', config: config), isNull));
  });

  group('upload checks', () {
    test('menu images over 5 MB are refused', () {
      const big = PickedUpload(path: '/x/a.jpg', name: 'a.jpg', sizeBytes: 6 * 1024 * 1024);
      expect(big.validate(UploadRules.image), contains('too large'));
    });
    test('PDF is a document but not a menu image', () {
      const pdf = PickedUpload(path: '/x/id.pdf', name: 'id.pdf', sizeBytes: 1000);
      expect(pdf.validate(UploadRules.document), isNull);
      expect(pdf.validate(UploadRules.image), isNotNull);
    });
    test('mime type comes from the extension', () {
      expect(mimeTypeForName('Photo.JPEG'), 'image/jpeg');
      expect(mimeTypeForName('a.webp'), 'image/webp');
      expect(mimeTypeForName('a.exe'), 'application/octet-stream');
    });
  });

  test('lists are read from bare arrays and wrapped objects', () {
    expect(unwrapList([{'a': 1}], ['items']), hasLength(1));
    expect(unwrapList({'orders': [{'a': 1}, {'a': 2}]}, ['items', 'orders']), hasLength(2));
    expect(unwrapList({'nope': 1}, ['items']), isEmpty);
  });

  test('paging continues while page × limit < total', () {
    expect(const PageMeta(page: 1, limit: 20, total: 45).hasMore, isTrue);
    expect(const PageMeta(page: 3, limit: 20, total: 45).hasMore, isFalse);
  });

  group('navigation rules', () {
    Uri u(String s) => Uri.parse(s);
    test('while restoring the session everything shows the splash', () {
      expect(appRedirect(SessionStatus.restoring, u('/orders')), '/splash');
      expect(appRedirect(SessionStatus.restoring, u('/splash')), isNull);
    });
    test('signed-out visitors go to login, remembering a deep link', () {
      expect(appRedirect(SessionStatus.unauthenticated, u('/dashboard')), '/login');
      expect(appRedirect(SessionStatus.unauthenticated, u('/orders/abc')), '/login?from=${Uri.encodeComponent('/orders/abc')}');
      expect(appRedirect(SessionStatus.unauthenticated, u('/register')), isNull);
    });
    test('signed-in vendors land on the dashboard or their deep link', () {
      expect(appRedirect(SessionStatus.authenticated, u('/login')), '/dashboard');
      expect(appRedirect(SessionStatus.authenticated, u('/splash')), '/dashboard');
      expect(appRedirect(SessionStatus.authenticated, u('/login?from=%2Forders%2Fabc')), '/orders/abc');
      expect(appRedirect(SessionStatus.authenticated, u('/orders/abc')), isNull);
    });
    test('blocked and unreachable states have their own screens', () {
      expect(appRedirect(SessionStatus.blocked, u('/dashboard')), '/blocked');
      expect(appRedirect(SessionStatus.unreachable, u('/dashboard')), '/offline');
    });
  });
}
