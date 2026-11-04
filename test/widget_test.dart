import 'package:flutter_test/flutter_test.dart';

import 'package:kitchenlink_mobile/nav/admin_nav.dart';
import 'package:kitchenlink_mobile/ui/format.dart';
import 'package:kitchenlink_mobile/ui/validation.dart';
import 'package:kitchenlink_mobile/ui/vendor_types.dart';

void main() {
  group('notification links', () {
    test('open the matching page with its parameters', () {
      final route = AdminRoute.fromLink('/admin-dashboard/orders?order=abc123');
      expect(route.page.id, 'orders');
      expect(route.params['order'], 'abc123');
    });

    test('settings and the dashboard root', () {
      expect(AdminRoute.fromLink('/admin-dashboard/settings').page.id, 'settings/profile');
      expect(AdminRoute.fromLink('/admin-dashboard').page.id, 'overview');
      expect(AdminRoute.fromLink('/admin-dashboard/deliveries?tab=late').params['tab'], 'late');
    });
  });

  group('permissions', () {
    bool can(String p) => p == 'orders:read';

    test('a page needs its permission', () {
      expect(Pages.orders.allowed(can: can, isOwner: false), isTrue);
      expect(Pages.vendors.allowed(can: can, isOwner: false), isFalse);
    });

    test('owner pages are for the owner only', () {
      expect(Pages.platform.allowed(can: can, isOwner: false), isFalse);
      expect(Pages.platform.allowed(can: (_) => true, isOwner: true), isTrue);
    });
  });

  test('money is shown as the website does', () {
    expect(formatRwf(2500), '2,500 RWF');
    expect(formatRwf(null), '0 RWF');
    expect(toTitle('out_for_delivery'), 'Out For Delivery');
  });

  test('Rwandan phones and emails follow the website rules', () {
    expect(isValidRwandaPhone('0788123456'), isTrue);
    expect(isValidRwandaPhone('+250731234567'), isTrue);
    expect(isValidRwandaPhone('0712345678'), isFalse);
    expect(sanitizePhoneInput('07 88-12a3456789'), '0788123456');
    expect(isValidEmail('admin@foodkitchen.rw'), isTrue);
    expect(isValidEmail('admin@@x'), isFalse);
  });

  test('legacy vendor type labels map to codes', () {
    expect(vendorTypeOf('Home Cook').code, 'home_cook');
    expect(vendorTypeOf('Juice/Drinks vendor').code, 'juice_drinks');
    expect(vendorTypeOf('something new').code, 'other');
  });
}
