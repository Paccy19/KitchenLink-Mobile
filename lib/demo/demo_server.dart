import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../api/api_client.dart';

/// Every SMS / action code in demo mode.
const demoCode = '123456';
const _token = 'demo-token-admin';
const _commissionPercent = 10;

/// Answers the admin API on the phone itself with demo data around Kigali,
/// like the website's `npm run demo`. Nothing is sent to a server; changes
/// last until the app is closed or "Reset demo data" is pressed.
class DemoServer {
  DemoServer() {
    reset();
  }

  final _rand = math.Random();
  late Map<String, dynamic> s;
  int _seq = 1000;

  String _id(String prefix) => '$prefix-${_seq++}';
  String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();
  String _in(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();
  String get _now => DateTime.now().toUtc().toIso8601String();

  Never _fail(int status, String message, [String code = '']) => throw ApiException(message, status: status, code: code);

  void _code(dynamic value) {
    if (value?.toString() != demoCode) _fail(400, 'Wrong code. In demo mode every code is $demoCode.', 'INVALID_CODE');
  }

  // ---- Seed data --------------------------------------------------------

  void reset() {
    _seq = 1000;
    final vendors = <Json>[
      _vendor('v1', 'Inzu Heritage Kitchen', 'restaurant', 'Kimironko', -1.9496, 30.1268, 'approved', true, 4.8, 1840000),
      _vendor('v2', "Mama Keza's Home Meals", 'home_cook', 'Remera', -1.9578, 30.1060, 'approved', true, 4.6, 920000),
      _vendor('v3', 'Kigali Bean Café', 'cafe', 'Kacyiru', -1.9390, 30.0830, 'approved', true, 4.5, 610000),
      _vendor('v4', 'Golden Crust Bakery', 'bakery', 'Nyamirambo', -1.9800, 30.0420, 'approved', false, 4.7, 455000),
      _vendor('v5', 'Umuganura Caterers', 'caterer', 'Kicukiro', -1.9850, 30.1040, 'approved', true, 4.9, 2760000),
      _vendor('v6', 'Fresh Juice Corner', 'juice_drinks', 'Gikondo', -1.9720, 30.0750, 'pending', false, 0, 0),
      _vendor('v7', 'Chef Eric Signature', 'chef', 'Kiyovu', -1.9530, 30.0600, 'pending', false, 0, 0),
      _vendor('v8', 'Street Brochette Truck', 'food_truck', 'Nyabugogo', -1.9380, 30.0450, 'suspended', false, 4.1, 230000),
    ];
    vendors[1]['vendor_type_request'] = {
      'vendor_type': 'caterer',
      'vendor_type_label': 'Caterer',
      'reason': 'We now cook for weddings and office events too.',
      'requested_at': _ago(const Duration(hours: 20)),
    };
    vendors[7]['suspension_reason'] = 'Repeated hygiene complaints from customers.';

    final drivers = <Json>[
      _driver('d1', 'Jean Bosco Habimana', 'motorcycle', 'RD 412 B', '0788100201', -1.9520, 30.1150, true, 'approved', 214, 642000),
      _driver('d2', 'Aline Uwase', 'bicycle', '', '0788100202', -1.9440, 30.0900, true, 'approved', 98, 236000),
      _driver('d3', 'Eric Nshimiyimana', 'motorcycle', 'RD 977 C', '0733100203', -1.9650, 30.0700, true, 'approved', 167, 498000),
      _driver('d4', 'Claudine Mukamana', 'motorcycle', 'RD 205 A', '0788100204', -1.9900, 30.1100, false, 'approved', 75, 201000),
      _driver('d5', 'Patrick Niyonzima', 'car', 'RAD 330 K', '0788100205', null, null, false, 'pending', 0, 0),
      _driver('d6', 'Samuel Iradukunda', 'motorcycle', 'RD 118 F', '0733100206', -1.9300, 30.0600, false, 'suspended', 40, 96000),
    ];

    final customerNames = ['Grace Ingabire', 'David Mugisha', 'Diane Uwimana', 'Olivier Nkurunziza', 'Sandrine Umutoni', 'Kevin Habineza', 'Ange Mutesi', 'Yves Ndayisaba', 'Josiane Akimana', 'Thierry Gasana'];
    final customers = <Json>[
      for (var i = 0; i < customerNames.length; i++)
        {
          'id': 'c${i + 1}',
          'name': customerNames[i],
          'phone': '07881${(23450 + i * 7).toString().padLeft(5, '0')}',
          'status': i == 8 ? 'suspended' : 'active',
          'created_at': _ago(Duration(days: 120 - i * 9)),
          // No demo customer has shared a location, so every row shows "—" (as on the website).
          'location': null,
        },
    ];

    s = {
      'admin': {
        'id': 'a1',
        'name': 'Demo Owner',
        'email': 'admin@foodkitchen.rw',
        'role': 'super_admin',
        'role_label': 'Owner',
        'is_owner': true,
        'is_active': true,
        'phone': '',
        'two_factor_enabled': false,
        'uses_default_password': false,
        'permissions': <String>[],
        'last_login_at': _ago(const Duration(days: 1)),
      },
      'vendors': vendors,
      'drivers': drivers,
      'customers': customers,
      'orders': <Json>[],
      'categories': [
        // The website demo's categories: all active, each with a description.
        for (final (i, (name, description)) in const [
          ('Rwandan', 'Isombe, ibihaza, brochettes and more.'),
          ('Grills', 'Brochettes, grilled chicken and fish.'),
          ('Pizza', 'Wood-fired and pan pizzas.'),
          ('Burgers', 'Burgers, wraps and fries.'),
          ('Breakfast', 'Morning plates and coffee.'),
          ('Bakery', 'Bread, cakes and pastries.'),
          ('Drinks', 'Fresh juices and smoothies.'),
          ('Healthy', 'Salads and balanced bowls.'),
        ].indexed)
          {'id': 'cat${i + 1}', 'name': name, 'description': description, 'icon_url': '', 'sort_order': i, 'is_active': true, 'created_by_vendor': null},
      ],
      'complaints': <Json>[],
      'chats': <Json>[],
      'commissions': <Json>[
        {'id': 'com1', 'name': 'Standard commission', 'scope': 'global', 'percentage': _commissionPercent, 'fixed_fee_rwf': 0, 'is_active': true},
        {'id': 'com2', 'name': 'Caterers', 'scope': 'vendor_type', 'vendor_type': 'caterer', 'vendor_type_label': 'Caterer', 'percentage': 8, 'fixed_fee_rwf': 0, 'is_active': true},
      ],
      'withdrawals': <Json>[],
      'refunds': <Json>[],
      'notifications': <Json>[],
      'actions': <Json>[],
      'team': <Json>[],
      'rules': {
        'radius_km': 5, 'max_drivers_per_broadcast': 10, 'driver_location_max_age_minutes': 10, 'rebroadcast_every_seconds': 60,
        'max_active_deliveries_per_driver': 2, 'platform_delivery_max_km': 15, 'max_wrong_codes': 5, 'updated_at': _ago(const Duration(days: 3)),
      },
      'fees': {'ranges': <Json>[], 'updated_at': null},
      'timing': {'warning_minutes': 10, 'charge_after_minutes': 20, 'reassign_after_minutes': 30, 'updated_at': _ago(const Duration(days: 5))},
      'banks': {
        'banks': [
          {'name': 'Bank of Kigali', 'digits_min': 14, 'digits_max': 14},
          {'name': 'I&M Bank Rwanda', 'digits_min': 16, 'digits_max': 16},
          {'name': 'Equity Bank Rwanda', 'digits_min': null, 'digits_max': null},
          {'name': 'Ecobank Rwanda', 'digits_min': null, 'digits_max': null},
        ],
        'updated_at': _ago(const Duration(days: 12)),
      },
      'owner': {
        'destinations': [
          {'id': 'dest1', 'type': 'bank', 'label': 'Company BK account', 'provider': 'Bank of Kigali', 'account_name': 'KitchenLink Ltd', 'account_number': '00040•••••1234', 'ready': true, 'activates_at': _ago(const Duration(days: 30))},
        ],
        'withdrawals': [
          {'id': 'pw1', 'amount_rwf': 350000, 'status': 'completed', 'source': 'manual', 'reference': 'BK-TRF-88213', 'created_at': _ago(const Duration(days: 9)), 'destination': {'label': 'Company BK account', 'provider': 'Bank of Kigali', 'account_name': 'KitchenLink Ltd', 'account_number': '00040•••••1234'}},
        ],
        'withdrawn_rwf': 350000,
        'adjustments_rwf': 0,
        'payout_settings': {
          'method': 'bank',
          'account': {'provider': 'Bank of Kigali', 'account_name': 'KitchenLink Ltd', 'account_number': '00040•••••1234', 'ready': true, 'activates_at': _ago(const Duration(days: 30))},
          'schedule': {'mode': 'reminder', 'frequency': 'weekly', 'weekday': 5, 'day_of_month': 1, 'hour': 9, 'amount_mode': 'all_available', 'fixed_amount_rwf': 0},
          'provider': {'automatic': false, 'label': 'Manual transfer'},
        },
        'reconciliations': <Json>[],
      },
    };

    _seedOrders();
    _seedSupport();
    _seedMoney();
    _seedTeam();
  }

  Json _vendor(String id, String name, String type, String area, double lat, double lng, String status, bool open, num rating, int sales) => {
        'id': id,
        'name': name,
        'vendor_type': type,
        'vendor_type_request': null,
        'phone': '0788${id.codeUnitAt(1)}00${id.codeUnitAt(1)}',
        'neighborhood': area,
        'address': 'KG ${10 + id.codeUnitAt(1) % 40} Ave, $area',
        'location': {'latitude': lat, 'longitude': lng, 'updated_at': _ago(const Duration(days: 40))},
        'status': status,
        'is_open': open,
        'rating': rating,
        'total_sales_rwf': sales,
        'available_balance_rwf': (sales * 0.18).round(),
        'nationwide_override': null,
        'verification_documents': [
          {'label': 'National ID', 'download_path': '/admin/vendors/$id/documents/0', 'uploaded_at': _ago(const Duration(days: 45))},
          {'label': 'RDB business certificate', 'download_path': '/admin/vendors/$id/documents/1', 'uploaded_at': _ago(const Duration(days: 45))},
        ],
        'documents_reviewed_at': status == 'pending' ? null : _ago(const Duration(days: 40)),
        'rejection_reason': null,
        'suspension_reason': null,
        'created_at': _ago(Duration(days: 60 - id.codeUnitAt(1) % 20)),
      };

  Json _driver(String id, String name, String vehicle, String plate, String phone, double? lat, double? lng, bool online, String status, int deliveries, int earnings) => {
        'id': id,
        'name': name,
        'vehicle_type': vehicle,
        'plate_number': plate,
        'phone': phone,
        'latitude': lat,
        'longitude': lng,
        'is_online': online,
        'verification_status': status,
        'completed_deliveries': deliveries,
        'total_earnings_rwf': earnings,
        'available_balance_rwf': (earnings * 0.12).round(),
        'created_at': _ago(Duration(days: 90 - deliveries % 50)),
      };

  static const _menu = [
    ('Isombe with Beef', 6500),
    ('Brochettes (4)', 5000),
    ('Matoke & Peas', 3500),
    ('Chapati Roll', 2000),
    ('Fresh Passion Juice', 1500),
    ('Sambaza Plate', 4500),
    ('Akabenzi Platter', 7000),
    ('African Tea', 1000),
  ];

  static const _labels = {
    'placed': 'Placed',
    'confirmed': 'Confirmed',
    'preparing': 'Preparing',
    'ready': 'Ready',
    'assigned': 'Delivery worker assigned',
    'picked_up': 'Picked up',
    'out_for_delivery': 'Out for delivery',
    'delivered': 'Delivered',
    'cancelled': 'Cancelled',
  };

  void _seedOrders() {
    final plan = <(String, String, int, String?)>[
      // status, fulfillment, minutes ago, driver
      ('placed', 'delivery', 3, null),
      ('placed', 'pickup', 6, null),
      ('confirmed', 'delivery', 12, null),
      ('preparing', 'delivery', 18, null),
      ('ready', 'delivery', 25, null),
      ('ready', 'pickup', 30, null),
      ('assigned', 'delivery', 34, 'd1'),
      ('picked_up', 'delivery', 41, 'd2'),
      ('out_for_delivery', 'delivery', 47, 'd3'),
      ('delivered', 'delivery', 90, 'd1'),
      ('delivered', 'delivery', 150, 'd2'),
      ('delivered', 'pickup', 200, null),
      ('cancelled', 'delivery', 260, null),
      ('delivered', 'delivery', 60 * 26, 'd3'),
      ('delivered', 'delivery', 60 * 30, 'd4'),
      ('delivered', 'pickup', 60 * 50, null),
      ('cancelled', 'delivery', 60 * 52, null),
      ('delivered', 'delivery', 60 * 75, 'd1'),
      ('delivered', 'delivery', 60 * 100, 'd2'),
      ('delivered', 'delivery', 60 * 140, 'd3'),
      ('delivered', 'delivery', 60 * 190, 'd1'),
      ('delivered', 'pickup', 60 * 240, null),
    ];
    final open = (s['vendors'] as List<Json>).where((v) => v['status'] == 'approved').toList();
    final orders = s['orders'] as List<Json>;
    for (var i = 0; i < plan.length; i++) {
      final (status, fulfillment, minutes, driver) = plan[i];
      final vendor = open[i % open.length];
      final customer = (s['customers'] as List<Json>)[i % 10];
      final items = [
        for (var k = 0; k < 1 + i % 3; k++)
          {'menu_item_id': 'm${(i + k) % _menu.length}', 'name': _menu[(i + k) % _menu.length].$1, 'quantity': 1 + (i + k) % 2, 'price_rwf': _menu[(i + k) % _menu.length].$2},
      ];
      for (final item in items) {
        item['subtotal_rwf'] = (item['price_rwf'] as int) * (item['quantity'] as int);
      }
      final subtotal = items.fold<int>(0, (sum, item) => sum + (item['subtotal_rwf'] as int));
      final fee = fulfillment == 'pickup' ? 0 : 800 + (i % 4) * 300;
      final created = DateTime.now().toUtc().subtract(Duration(minutes: minutes));
      orders.add({
        'id': 'o${i + 1}',
        'order_number': 'OFK-${(240518 + i * 37).toRadixString(16).toUpperCase()}',
        'vendor_id': vendor['id'],
        'customer_id': customer['id'],
        'driver_id': driver,
        'fulfillment': fulfillment,
        'payment_method': ['mobile_money', 'card', 'ekash', 'mobile_money'][i % 4],
        'payment_status': status == 'cancelled' ? (i == 12 ? 'refunded' : 'paid') : 'paid',
        'status': status,
        'items': items,
        'subtotal_rwf': subtotal,
        'delivery_fee_rwf': fee,
        'total_amount_rwf': subtotal + fee,
        'order_type': i == 3 ? 'scheduled' : 'immediate',
        'scheduled_for': i == 3 ? _in(const Duration(hours: 2)) : null,
        'created_at': created.toIso8601String(),
        'ready_at': ['ready', 'assigned', 'picked_up', 'out_for_delivery', 'delivered'].contains(status) ? created.add(const Duration(minutes: 15)).toIso8601String() : null,
        'status_history': [
          {'status': 'placed', 'label': 'Order placed', 'at': created.toIso8601String(), 'note': ''},
          if (status != 'placed') {'status': status, 'label': _labels[status], 'at': created.add(const Duration(minutes: 5)).toIso8601String(), 'note': ''},
        ],
        'cancel_reason': status == 'cancelled' ? 'Kitchen ran out of ingredients' : null,
      });
    }
    // The order assigned 34 minutes ago is late to be collected.
    orders[6]['late'] = true;
  }

  void _seedSupport() {
    final complaints = s['complaints'] as List<Json>;
    final seeds = [
      ('Food arrived cold', 'delivery', 'high', 'open', 'customer', 'c2', true),
      ('Charged twice for one order', 'payment', 'urgent', 'open', 'customer', 'c4', true),
      ('Customer gave a wrong pickup code', 'order', 'medium', 'in_review', 'vendor', 'v3', false),
      ('App shows wrong delivery address', 'app', 'low', 'resolved', 'driver', 'd2', false),
      ('Refund still not received', 'refund', 'high', 'in_review', 'customer', 'c7', false),
    ];
    for (final (i, (subject, category, priority, status, role, user, unread)) in seeds.indexed) {
      final name = role == 'customer'
          ? _find('customers', user)!['name']
          : role == 'vendor'
              ? _find('vendors', user)!['name']
              : _find('drivers', user)!['name'];
      final at = _ago(Duration(hours: 3 + i * 9));
      complaints.add({
        'id': 'cmp${i + 1}',
        'reference': 'SUP-${1042 + i}',
        'subject': subject,
        'description': '$subject. Please help.',
        'category': category,
        'priority': priority,
        'status': status,
        'unread': unread,
        'raised_by': {'role': role, 'user_id': user, 'name': name, 'phone': '0788${(500000 + i * 111).toString()}'},
        'messages': [
          {'id': 'msg${i}a', 'author_role': role, 'author_name': name, 'body': '$subject. Please help.', 'at': at},
          if (status != 'open') {'id': 'msg${i}b', 'author_role': 'admin', 'author_name': 'Demo Owner', 'body': 'Thanks, we are looking into it.', 'at': _ago(Duration(hours: 2 + i * 9))},
        ],
        'notes': [if (status == 'resolved') {'body': 'Fixed the pin on the map for this customer.', 'author_name': 'Demo Owner', 'at': _ago(Duration(hours: 1 + i * 9))}],
        'created_at': at,
        'last_message_at': at,
      });
    }

    final chats = s['chats'] as List<Json>;
    final lines = [
      ('customer', 'Hello, can you make the isombe less spicy?'),
      ('vendor', 'Of course! We will prepare it mild for you.'),
      ('customer', 'Thank you. How long will it take?'),
      ('vendor', 'About 25 minutes. The delivery worker will call you.'),
    ];
    for (var i = 0; i < 4; i++) {
      final customer = _find('customers', 'c${i + 1}')!;
      final vendor = (s['vendors'] as List<Json>)[i];
      final messages = [
        for (final (k, (role, body)) in lines.take(2 + i % 3).indexed)
          {'id': 'cm$i$k', 'author_role': role, 'body': body, 'created_at': _ago(Duration(minutes: 200 - i * 40 - k * 6))},
      ];
      chats.add({'id': 'chat${i + 1}', 'customer': customer, 'vendor': vendor, 'messages': messages});
    }

    s['notifications'] = <Json>[
      _note('vendor_application', 'New kitchen application', 'Fresh Juice Corner wants to join. Review their documents.', '/admin-dashboard/vendors?vendor=v6', 40),
      _note('complaint_opened', 'Urgent complaint', 'Charged twice for one order (SUP-1043).', '/admin-dashboard/complaints?complaint=cmp2', 75),
      _note('late_pickup', 'Late pickup', 'An order is waiting at Inzu Heritage Kitchen past its pickup time.', '/admin-dashboard/deliveries?tab=late', 10),
      _note('payout_requested', 'Withdrawal requested', "Mama Keza's Home Meals asked for 120,000 RWF.", '/admin-dashboard/payouts?payout=wd1', 120, read: true),
      _note('driver_application', 'New delivery worker', 'Patrick Niyonzima signed up.', '/admin-dashboard/drivers?driver=d5', 300, read: true),
    ];
  }

  Json _note(String type, String title, String body, String link, int minutesAgo, {bool read = false}) =>
      {'id': _id('n'), 'type': type, 'title': title, 'body': body, 'read': read, 'data': {'link': link}, 'created_at': _ago(Duration(minutes: minutesAgo))};

  void _seedMoney() {
    final withdrawals = s['withdrawals'] as List<Json>;
    withdrawals.addAll([
      {'id': 'wd1', 'payee_type': 'vendor', 'payee_id': 'v2', 'payee_name': "Mama Keza's Home Meals", 'amount_rwf': 120000, 'method_label': 'MTN Mobile Money', 'account_number': '0788200212', 'account_name': 'Keza Mukamana', 'status': 'processing', 'created_at': _ago(const Duration(hours: 2))},
      {'id': 'wd2', 'payee_type': 'driver', 'payee_id': 'd1', 'payee_name': 'Jean Bosco Habimana', 'amount_rwf': 35000, 'method_label': 'MTN Mobile Money', 'account_number': '0788100201', 'account_name': 'Jean Bosco Habimana', 'status': 'processing', 'created_at': _ago(const Duration(hours: 5))},
      {'id': 'wd3', 'payee_type': 'vendor', 'payee_id': 'v1', 'payee_name': 'Inzu Heritage Kitchen', 'amount_rwf': 300000, 'method_label': 'Bank Transfer', 'bank_name': 'Bank of Kigali', 'account_number': '00040123456789', 'account_name': 'Inzu Heritage Ltd', 'status': 'completed', 'reference': 'BK-55120', 'created_at': _ago(const Duration(days: 2))},
      {'id': 'wd4', 'payee_type': 'driver', 'payee_id': 'd3', 'payee_name': 'Eric Nshimiyimana', 'amount_rwf': 20000, 'method_label': 'Airtel Money', 'account_number': '0733100203', 'account_name': 'Eric Nshimiyimana', 'status': 'failed', 'reference': '', 'failure_reason': 'Number not registered for mobile money', 'created_at': _ago(const Duration(days: 4))},
    ]);
    final orders = s['orders'] as List<Json>;
    final refunds = s['refunds'] as List<Json>;
    for (final order in orders.where((o) => o['status'] == 'cancelled')) {
      final customer = _find('customers', order['customer_id'])!;
      final done = order['payment_status'] == 'refunded';
      refunds.add({
        'id': _id('rf'),
        'order_id': order['id'],
        'order_number': order['order_number'],
        'customer': {'name': customer['name'], 'phone': customer['phone']},
        'amount_rwf': order['total_amount_rwf'],
        'destination': {'label': 'MTN Mobile Money ${customer['phone']}'},
        'status': done ? 'completed' : 'pending',
        'reference': done ? 'MOMO-77120' : null,
        'cancelled_by': 'vendor',
        'reason': order['cancel_reason'],
        'created_at': order['created_at'],
      });
    }
  }

  void _seedTeam() {
    s['team'] = <Json>[
      {'id': 'a1', 'name': 'Demo Owner', 'email': 'admin@foodkitchen.rw', 'role': 'super_admin', 'role_label': 'Owner', 'is_owner': true, 'status': 'active', 'two_factor_enabled': false, 'phone': '0788000001', 'last_login_at': _ago(const Duration(days: 1))},
      {'id': 'a2', 'name': 'Aline Uwase', 'email': 'aline@foodkitchen.rw', 'role': 'operations', 'role_label': 'Operations manager', 'status': 'active', 'two_factor_enabled': true, 'phone': '0788300301', 'last_login_at': _ago(const Duration(hours: 6))},
      {'id': 'a3', 'name': 'Moses Kalisa', 'email': 'moses@foodkitchen.rw', 'role': 'finance', 'role_label': 'Finance', 'status': 'active', 'two_factor_enabled': false, 'phone': '0788300302', 'last_login_at': _ago(const Duration(days: 3))},
      {'id': 'a4', 'name': '', 'email': 'support1@foodkitchen.rw', 'role': 'support', 'role_label': 'Support agent', 'status': 'invited', 'two_factor_enabled': false, 'phone': '', 'invite_expires_at': _in(const Duration(days: 5)), 'last_login_at': null},
    ];
    _log('team.invite_sent', 'admin', 'support1@foodkitchen.rw', minutesAgo: 600);
    _log('vendor.suspended', 'vendor', 'Street Brochette Truck', minutesAgo: 1500);
    _log('payout.completed', 'payout', 'Inzu Heritage Kitchen · 300,000 RWF', minutesAgo: 2900);
  }

  static const _roles = [
    {'id': 'operations', 'label': 'Operations manager', 'description': 'Runs orders, deliveries, kitchens and delivery workers.', 'permissions': ['dashboard:read', 'orders:read', 'orders:write', 'deliveries:read', 'deliveries:write', 'vendors:read', 'vendors:write', 'drivers:read', 'drivers:write', 'categories:read', 'categories:write']},
    {'id': 'support', 'label': 'Support agent', 'description': 'Answers complaints and reads customer–kitchen chats.', 'permissions': ['dashboard:read', 'orders:read', 'complaints:read', 'complaints:write', 'chats:read', 'users:read']},
    {'id': 'finance', 'label': 'Finance', 'description': 'Payments, payouts, refunds and the platform books.', 'permissions': ['dashboard:read', 'payments:read', 'payouts:read', 'payouts:write', 'refunds:read', 'refunds:write', 'wallet:read', 'commissions:read', 'analytics:read']},
  ];
  static const _permissionCategories = [
    {'id': 'operations', 'label': 'Operations'},
    {'id': 'support', 'label': 'Support'},
    {'id': 'finance', 'label': 'Finance'},
  ];
  static const _permissions = [
    {'id': 'dashboard:read', 'label': 'See the overview', 'category': 'operations'},
    {'id': 'orders:read', 'label': 'See orders', 'category': 'operations'},
    {'id': 'orders:write', 'label': 'Change orders', 'category': 'operations'},
    {'id': 'deliveries:read', 'label': 'See deliveries', 'category': 'operations'},
    {'id': 'deliveries:write', 'label': 'Change delivery rules', 'category': 'operations'},
    {'id': 'vendors:read', 'label': 'See kitchens', 'category': 'operations'},
    {'id': 'vendors:write', 'label': 'Approve kitchens', 'category': 'operations'},
    {'id': 'drivers:read', 'label': 'See delivery workers', 'category': 'operations'},
    {'id': 'drivers:write', 'label': 'Approve delivery workers', 'category': 'operations'},
    {'id': 'categories:read', 'label': 'See categories', 'category': 'operations'},
    {'id': 'categories:write', 'label': 'Edit categories', 'category': 'operations'},
    {'id': 'complaints:read', 'label': 'See complaints', 'category': 'support'},
    {'id': 'complaints:write', 'label': 'Answer complaints', 'category': 'support'},
    {'id': 'chats:read', 'label': 'Read chats', 'category': 'support'},
    {'id': 'users:read', 'label': 'See customers', 'category': 'support'},
    {'id': 'payments:read', 'label': 'See payments', 'category': 'finance'},
    {'id': 'payouts:read', 'label': 'See payouts', 'category': 'finance'},
    {'id': 'payouts:write', 'label': 'Pay out', 'category': 'finance'},
    {'id': 'refunds:read', 'label': 'See refunds', 'category': 'finance'},
    {'id': 'refunds:write', 'label': 'Send refunds', 'category': 'finance'},
    {'id': 'wallet:read', 'label': 'See the books', 'category': 'finance'},
    {'id': 'commissions:read', 'label': 'See commissions', 'category': 'finance'},
    {'id': 'analytics:read', 'label': 'See analytics', 'category': 'finance'},
  ];

  // ---- Helpers ------------------------------------------------------------

  List<Json> _list(String key) => s[key] as List<Json>;
  Json? _find(String key, dynamic id) => _list(key).where((e) => e['id'] == id).firstOrNull;
  Json _must(String key, dynamic id, String what) => _find(key, id) ?? _fail(404, '$what not found.');

  void _log(String action, String targetType, String label, {int minutesAgo = 0}) {
    _list('actions').insert(0, {
      'id': _id('act'),
      'admin_name': 'Demo Owner',
      'admin_email': 'admin@foodkitchen.rw',
      'action': action,
      'target_type': targetType,
      'target_label': label,
      'ip': '127.0.0.1',
      'created_at': _ago(Duration(minutes: minutesAgo)),
    });
  }

  Json _page(List<Json> list, Uri uri, [int defaultLimit = 20]) {
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '') ?? defaultLimit;
    final page = math.max(1, int.tryParse(uri.queryParameters['page'] ?? '') ?? 1);
    final start = math.min((page - 1) * limit, list.length);
    return {'items': list.sublist(start, math.min(start + limit, list.length)), 'page': page, 'limit': limit, 'total': list.length};
  }

  bool _match(dynamic value, String q) => value != null && value.toString().toLowerCase().contains(q);

  String _q(Uri uri, String key) => uri.queryParameters[key] ?? '';

  DateTime _date(dynamic iso) => DateTime.parse(iso.toString());

  bool _isToday(dynamic iso) {
    final d = _date(iso).toLocal();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // ---- Projections --------------------------------------------------------

  /// Like the backend: approved (or suspended) kitchens change type only on request.
  static bool _typeLocked(Json v) => const ['approved', 'suspended'].contains(v['status'] ?? 'approved');

  Json _adminVendor(Json v) {
    final override = v['nationwide_override'];
    final byType = v['vendor_type'] == 'caterer';
    return {
      ...v,
      // Approved kitchens: the type only changes through the vendor's request.
      'vendor_type_locked': _typeLocked(v),
      'nationwide': {
        'enabled': override ?? byType,
        'source': override == null ? 'type' : 'admin',
        'by_type': byType,
        'travel_base_fee_rwf': 2000,
        'travel_per_km_rwf': 300,
      },
    };
  }

  Json _adminDriver(Json d) => {
        ...d,
        'status': d['verification_status'],
        'active_deliveries_count': _list('orders').where((o) => o['driver_id'] == d['id'] && const ['assigned', 'picked_up', 'out_for_delivery'].contains(o['status'])).length,
        'location': {
          'latitude': d['latitude'],
          'longitude': d['longitude'],
          'updated_at': d['latitude'] == null ? null : _ago(Duration(minutes: d['is_online'] == true ? 1 : 45)),
          'counts_for_dispatch': d['is_online'] == true,
        },
      };

  Json _adminOrder(Json o) {
    final vendor = _find('vendors', o['vendor_id']);
    final customer = _find('customers', o['customer_id']);
    final driver = _find('drivers', o['driver_id']);
    final pickup = o['fulfillment'] == 'pickup';
    return {
      ...o,
      'status_label': _labels[o['status']],
      'fulfillment_label': pickup ? 'Customer pickup' : 'Delivery',
      'order_type_label': o['order_type'] == 'scheduled' ? 'Scheduled' : 'Immediate',
      'vendor': {'id': vendor?['id'], 'name': vendor?['name'], 'phone': vendor?['phone']},
      'customer': {'id': customer?['id'], 'name': customer?['name'], 'phone': customer?['phone']},
      'driver': driver == null ? null : {'id': driver['id'], 'name': driver['name'], 'phone': driver['phone']},
      'pickup': pickup
          ? {
              'code_sent_at': o['created_at'],
              'wrong_attempts': 0,
              'max_attempts': s['rules']['max_wrong_codes'],
              'collected_at': o['status'] == 'delivered' ? o['ready_at'] : null,
              'locked': false,
            }
          : null,
    };
  }

  Json? _delivery(Json o) {
    if (o['fulfillment'] != 'delivery' || const ['placed', 'confirmed', 'preparing', 'cancelled'].contains(o['status'])) return null;
    final status = switch (o['status']) {
      'ready' => 'ready_for_pickup',
      'assigned' => 'assigned_to_driver',
      'delivered' => 'delivered',
      final other => other,
    };
    final ready = o['ready_at'] ?? o['created_at'];
    return {
      'id': 'del-${o['id']}',
      'order_id': o['id'],
      'order_number': o['order_number'],
      'status': status,
      'status_label': _labels[o['status']],
      'kitchen_ready': true,
      'ready_at': ready,
      'assigned_at': o['driver_id'] == null ? null : ready,
      'pickup_due_at': _date(ready).add(Duration(minutes: s['timing']['charge_after_minutes'] as int)).toIso8601String(),
      'picked_up_at': const ['picked_up', 'out_for_delivery', 'delivered'].contains(o['status']) ? _date(ready).add(const Duration(minutes: 8)).toIso8601String() : null,
      'completed_at': o['status'] == 'delivered' ? _date(ready).add(const Duration(minutes: 30)).toIso8601String() : null,
      'promised_earnings_rwf': o['delivery_fee_rwf'],
      'route_distance_km': 2.4 + (o['delivery_fee_rwf'] as int) / 1000,
      'late_pickup': o['late'] == true ? {'minutes_late': null, 'charge_status': 'waived'} : null,
      'vendor': {'name': _find('vendors', o['vendor_id'])?['name']},
      'driver': o['driver_id'] == null ? null : _adminDriver(_find('drivers', o['driver_id'])!),
      'offered_to': o['driver_id'] == null ? 3 : 1,
      'updated_at': ready,
    };
  }

  /// The customer's drop-off point: a little away from the kitchen.
  Json _destination(Json o) {
    final loc = _find('vendors', o['vendor_id'])!['location'] as Map;
    final n = int.parse(o['id'].toString().substring(1));
    return {'latitude': (loc['latitude'] as num) + 0.012 * math.cos(n), 'longitude': (loc['longitude'] as num) + 0.012 * math.sin(n), 'address': 'Customer address, house ${10 + n}'};
  }

  /// A rider moving along a gently curved road from the kitchen to the customer.
  Json _live(Json o) {
    final active = const ['assigned', 'picked_up', 'out_for_delivery'].contains(o['status']);
    if (!active) return {'active': false};
    final kitchen = _find('vendors', o['vendor_id'])!;
    final k = kitchen['location'] as Map;
    final d = _destination(o);
    final from = [(k['longitude'] as num).toDouble(), (k['latitude'] as num).toDouble()];
    final to = [(d['longitude'] as num).toDouble(), (d['latitude'] as num).toDouble()];
    final route = [
      for (var i = 0; i <= 20; i++)
        [from[0] + (to[0] - from[0]) * i / 20 + 0.002 * math.sin(i / 20 * math.pi), from[1] + (to[1] - from[1]) * i / 20],
    ];
    final toKitchen = o['status'] == 'assigned';
    // Progress advances every few seconds, then loops.
    final t = (DateTime.now().millisecondsSinceEpoch ~/ 5000) % 20;
    final at = toKitchen ? [from[0] - 0.006 + 0.0003 * t, from[1] - 0.004 + 0.0002 * t] : route[t];
    final driver = _find('drivers', o['driver_id'])!;
    final remaining = toKitchen ? route.sublist(0, 1) : route.sublist(t);
    return {
      'active': true,
      'phase': toKitchen ? 'to_kitchen' : 'to_customer',
      'phase_label': toKitchen ? 'Going to the kitchen' : 'On the way to the customer',
      'driver': {'name': driver['name'], 'location': {'latitude': at[1], 'longitude': at[0], 'heading': 45, 'updated_at': _now, 'stale': false}},
      'kitchen': {'latitude': k['latitude'], 'longitude': k['longitude'], 'name': kitchen['name']},
      'destination': d,
      'route': {'duration_s': 60 + remaining.length * 45, 'distance_m': remaining.length * 180, 'geometry': toKitchen ? [at, from] : remaining},
    };
  }

  Json _complaintCounts() {
    final list = _list('complaints');
    return {
      'unread': list.where((c) => c['unread'] == true).length,
      for (final status in ['open', 'in_review', 'resolved', 'rejected']) status: list.where((c) => c['status'] == status).length,
    };
  }

  int get _commissionEarned => _list('orders').where((o) => o['status'] == 'delivered').fold<int>(0, (sum, o) => sum + (o['subtotal_rwf'] as int) * _commissionPercent ~/ 100) + 410000;

  Json _books() {
    final owner = s['owner'] as Json;
    final ownerBalance = _commissionEarned - (owner['withdrawn_rwf'] as int) + (owner['adjustments_rwf'] as int);
    final vendorPayable = _list('vendors').fold<int>(0, (sum, v) => sum + (v['available_balance_rwf'] as int));
    final driverPayable = _list('drivers').fold<int>(0, (sum, d) => sum + (d['available_balance_rwf'] as int));
    final held = _list('orders').where((o) => !const ['delivered', 'cancelled'].contains(o['status'])).fold<int>(0, (sum, o) => sum + (o['total_amount_rwf'] as int));
    final refundsOwed = _list('refunds').where((r) => r['status'] != 'completed').fold<int>(0, (sum, r) => sum + (r['amount_rwf'] as int));
    return {
      'cash_balance_rwf': ownerBalance + vendorPayable + driverPayable + held + refundsOwed,
      'held_balance_rwf': held,
      'refunds_owed_rwf': refundsOwed,
      'vendor_payable_rwf': vendorPayable,
      'driver_payable_rwf': driverPayable,
      'owner_balance_rwf': ownerBalance,
      'commission_balance_rwf': ownerBalance,
      'total_commission_rwf': _commissionEarned,
      'balanced': true,
      'unreconciled_rwf': 0,
    };
  }

  List<Json> get _payments => [
        for (final o in _list('orders'))
          {
            'id': 'pay-${o['id']}',
            'order_number': o['order_number'],
            'customer': {'name': _find('customers', o['customer_id'])?['name']},
            'amount_rwf': o['total_amount_rwf'],
            'method': o['payment_method'],
            'provider': o['payment_method'],
            'status': o['payment_status'] == 'paid' ? 'successful' : o['payment_status'],
            'created_at': o['created_at'],
          },
      ];

  Json _rules() {
    final r = s['rules'] as Json;
    final fees = s['fees'] as Json;
    final timing = s['timing'] as Json;
    return {
      'dispatch': {
        'radius_km': r['radius_km'],
        'max_drivers_per_broadcast': r['max_drivers_per_broadcast'],
        'driver_location_max_age_minutes': r['driver_location_max_age_minutes'],
        'rebroadcast_every_seconds': r['rebroadcast_every_seconds'],
        'max_active_deliveries_per_driver': r['max_active_deliveries_per_driver'],
        'platform_delivery_max_km': r['platform_delivery_max_km'],
        'offered_when': 'A delivery order is offered to delivery workers once it is paid (scheduled orders: when the kitchen marks it ready).',
        'updated_at': r['updated_at'],
      },
      'customer_pickup': {'max_wrong_codes': r['max_wrong_codes'], 'code_digits': 6},
      'limits': {
        'radius_km': [1, 30, 1],
        'max_offer_recipients': [1, 50, 0],
        'location_max_age_minutes': [1, 120, 0],
        'rebroadcast_every_seconds': [15, 600, 0],
        'max_active_deliveries': [1, 5, 0],
        'platform_delivery_max_km': [1, 100, 1],
        'pickup_code_max_attempts': [1, 10, 0],
      },
      'pickup_clock': {'warning_after_minutes': timing['warning_minutes'], 'grace_minutes': timing['charge_after_minutes'], 'reassign_after_minutes': timing['reassign_after_minutes']},
      'fees': {'ranges': fees['ranges'], 'base_rwf': 500, 'per_km_rwf': 200, 'minimum_rwf': 800, 'driver_share_percent': 100},
      'tracking': {'routes_provider': 'Demo routes (no map service)', 'google_key_configured': false, 'place_search_provider': 'Demo'},
      'sms': {'note': 'Demo mode: codes are shown on screen (123456)', 'configured': false},
    };
  }

  // ---- Router -------------------------------------------------------------

  /// One API call. [path] includes the query string, as the app sends it.
  Future<dynamic> handle(String method, String path, Object? rawBody, String? token) async {
    await Future<void>.delayed(Duration(milliseconds: 120 + _rand.nextInt(180)));
    final uri = Uri.parse('http://demo$path');
    final p = uri.pathSegments;
    final body = rawBody is Map ? rawBody.cast<String, dynamic>() : <String, dynamic>{};
    final route = '$method /${p.join('/')}';
    String seg(int i) => i < p.length ? p[i] : '';

    // Public routes.
    if (route == 'POST /admin/auth/login') {
      if (jstr(body['email']).isEmpty || jstr(body['password']).isEmpty) _fail(400, 'Enter your email and password.');
      final admin = s['admin'] as Json;
      if (admin['two_factor_enabled'] == true) {
        return {'two_factor_required': true, 'challenge_token': 'demo-challenge', 'sent_to': admin['phone'], 'dev_otp': demoCode};
      }
      return {'token': _token, 'admin': admin};
    }
    if (route == 'POST /admin/auth/verify-2fa') {
      _code(body['code']);
      return {'token': _token, 'admin': s['admin']};
    }
    if (route == 'POST /admin/auth/logout') return {'ok': true};
    if (seg(2) == 'invitations') {
      if (method == 'GET') {
        return {'invitation': {'email': 'new.member@foodkitchen.rw', 'role_label': 'Support agent', 'role_description': 'Answers complaints and reads customer–kitchen chats.'}};
      }
      return {'ok': true};
    }
    if (token != _token) _fail(401, 'Missing bearer token. Log in to continue.', 'UNAUTHORIZED');

    return _route(method, route, p, uri, body);
  }

  /// A private vendor document: a small generated PDF.
  Future<(Uint8List, String)> file(String path) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final p = Uri.parse('http://demo$path').pathSegments;
    final vendor = _find('vendors', p.length > 2 ? p[2] : '');
    final doc = p.length > 4 ? int.tryParse(p[4]) ?? 0 : 0;
    final title = '${vendor?['name'] ?? 'Vendor'} - ${doc == 0 ? 'National ID' : 'RDB business certificate'} (demo)';
    return (_pdf(title), 'application/pdf');
  }

  dynamic _route(String method, String route, List<String> p, Uri uri, Json body) {
    final admin = s['admin'] as Json;
    String seg(int i) => i < p.length ? p[i] : '';
    final id = seg(2);

    switch (route) {
      // ---- Account ----
      case 'GET /admin/auth/me':
        return {'admin': admin, 'limits': {'large_money_action_rwf': 50000}, 'idle_timeout_minutes': 120};
      case 'POST /admin/auth/change-password':
        if (jstr(body['current_password']).isEmpty) _fail(400, 'Enter your current password.');
        admin['uses_default_password'] = false;
        _log('admin.password_changed', 'admin', admin['email']);
        return {'ok': true};
      case 'POST /admin/auth/2fa/start':
        return {'sent_to': body['phone'], 'dev_otp': demoCode};
      case 'POST /admin/auth/2fa/enable':
        _code(body['code']);
        admin['two_factor_enabled'] = true;
        admin['phone'] = body['phone'];
        return {'admin': admin};
      case 'POST /admin/auth/2fa/disable':
        _code(body['code']);
        admin['two_factor_enabled'] = false;
        return {'admin': admin};
      case 'POST /admin/auth/action-code':
        return {'sent_to': jstr(admin['phone'], '+250 78• ••• 001'), 'dev_otp': demoCode};

      // ---- Notifications ----
      case 'GET /admin/notifications':
        final list = _list('notifications');
        return {'notifications': list.take(20).toList(), 'unread_count': list.where((n) => n['read'] != true).length};
      case 'POST /admin/notifications/read-all':
        for (final n in _list('notifications')) {
          n['read'] = true;
        }
        return {'ok': true};

      // ---- Overview ----
      case 'GET /admin/dashboard/overview':
        final orders = _list('orders');
        final today = orders.where((o) => _isToday(o['created_at'])).toList();
        final sales = today.where((o) => o['status'] != 'cancelled').fold<int>(0, (sum, o) => sum + (o['subtotal_rwf'] as int));
        int count(String key, String field, String value) => _list(key).where((e) => e[field] == value).length;
        return {
          'commission_percent': _commissionPercent,
          'today': {
            'orders': today.length,
            'sales_rwf': sales,
            'completed_orders': today.where((o) => o['status'] == 'delivered').length,
            'commission_rwf': sales * _commissionPercent ~/ 100,
            'delivery_fees_rwf': today.fold<int>(0, (sum, o) => sum + (o['delivery_fee_rwf'] as int)),
          },
          'orders': {'pending': count('orders', 'status', 'placed'), 'live': orders.where((o) => !const ['delivered', 'cancelled'].contains(o['status'])).length},
          'deliveries': {'active': orders.where((o) => const ['assigned', 'picked_up', 'out_for_delivery'].contains(o['status'])).length},
          'complaints': {'open': _list('complaints').where((c) => const ['open', 'in_review'].contains(c['status'])).length},
          'vendors': {'total': _list('vendors').length, 'pending': count('vendors', 'status', 'pending'), 'approved': count('vendors', 'status', 'approved'), 'suspended': count('vendors', 'status', 'suspended')},
          'drivers': {'total': _list('drivers').length, 'online': _list('drivers').where((d) => d['is_online'] == true).length, 'pending': count('drivers', 'verification_status', 'pending'), 'suspended': count('drivers', 'verification_status', 'suspended')},
          'customers': {'total': _list('customers').length, 'active': count('customers', 'status', 'active')},
          'operations': {
            'orders_awaiting_driver': orders.where((o) => o['fulfillment'] == 'delivery' && o['status'] == 'ready' && o['driver_id'] == null).length,
            'late_pickups_waiting': orders.where((o) => o['late'] == true && o['status'] == 'assigned').length,
            'late_pickups_pending_charge': 0,
            'pickups_awaiting_collection': orders.where((o) => o['fulfillment'] == 'pickup' && o['status'] == 'ready').length,
            'pickups_locked': 0,
            'kitchens_open': _list('vendors').where((v) => v['status'] == 'approved' && v['is_open'] == true).length,
            'drivers_matchable': _list('drivers').where((d) => d['is_online'] == true && d['verification_status'] == 'approved').length,
            'pickup_orders_last_24h': orders.where((o) => o['fulfillment'] == 'pickup' && DateTime.now().difference(_date(o['created_at'])).inHours < 24).length,
          },
          'recent_orders': orders.take(8).map(_adminOrder).toList(),
        };

      // ---- Vendors ----
      case 'GET /admin/vendors/counts':
        int c(String status) => _list('vendors').where((v) => v['status'] == status).length;
        return {'total': _list('vendors').length, 'pending': c('pending'), 'approved': c('approved'), 'rejected': c('rejected'), 'suspended': c('suspended')};
      case 'GET /admin/vendors':
        final status = _q(uri, 'status');
        final q = _q(uri, 'search').toLowerCase();
        final types = _q(uri, 'vendor_type').split(',').where((t) => t.isNotEmpty).toSet();
        final byStatus = _list('vendors').where((v) => status.isEmpty || v['status'] == status).toList();
        final list = byStatus.where((v) => (q.isEmpty || _match(v['name'], q) || _match(v['phone'], q)) && (types.isEmpty || types.contains(v['vendor_type']))).map(_adminVendor).toList();
        final typeCounts = <String, int>{};
        for (final v in byStatus) {
          typeCounts.update(v['vendor_type'], (n) => n + 1, ifAbsent: () => 1);
        }
        return {..._page(list, uri), 'type_counts': [for (final e in typeCounts.entries) {'code': e.key, 'count': e.value}]};
      case 'GET /admin/drivers/counts':
        int c(String status) => _list('drivers').where((d) => d['verification_status'] == status).length;
        return {'total': _list('drivers').length, 'online': _list('drivers').where((d) => d['is_online'] == true).length, 'pending': c('pending'), 'approved': c('approved'), 'suspended': c('suspended'), 'rejected': c('rejected')};
      case 'GET /admin/drivers':
        final status = _q(uri, 'status');
        final online = _q(uri, 'online');
        final q = _q(uri, 'search').toLowerCase();
        return _page(
          _list('drivers')
              .where((d) => (status.isEmpty || d['verification_status'] == status) && (online.isEmpty || '${d['is_online']}' == online) && (q.isEmpty || _match(d['name'], q) || _match(d['phone'], q)))
              .map(_adminDriver)
              .toList(),
          uri,
        );

      // ---- Users ----
      case 'GET /admin/users':
        final role = _q(uri, 'role');
        final status = _q(uri, 'status');
        final q = _q(uri, 'search').toLowerCase();
        final users = [
          for (final c in _list('customers'))
            {'id': c['id'], 'role': 'customer', 'name': c['name'], 'identifier': c['phone'], 'secondary': '', 'status': c['status'], 'avatar_url': '', 'last_location': c['location'], 'created_at': c['created_at']},
          for (final v in _list('vendors')) {'id': v['id'], 'role': 'vendor', 'name': v['name'], 'identifier': v['phone'], 'secondary': v['vendor_type'], 'status': v['status'], 'avatar_url': '', 'last_location': null, 'created_at': v['created_at']},
          for (final d in _list('drivers')) {'id': d['id'], 'role': 'driver', 'name': d['name'], 'identifier': d['phone'], 'secondary': d['vehicle_type'], 'status': d['verification_status'], 'avatar_url': '', 'last_location': null, 'created_at': d['created_at']},
        ];
        return _page(users.where((u) => (role.isEmpty || u['role'] == role) && (status.isEmpty || u['status'] == status) && (q.isEmpty || _match(u['name'], q) || _match(u['identifier'], q))).toList(), uri);

      // ---- Orders ----
      case 'GET /admin/orders':
        final status = _q(uri, 'status');
        final fulfillment = _q(uri, 'fulfillment');
        final q = _q(uri, 'search').toLowerCase();
        final from = DateTime.tryParse(_q(uri, 'from'));
        final to = DateTime.tryParse(_q(uri, 'to'));
        return _page(
          _list('orders')
              .where((o) {
                final created = _date(o['created_at']).toLocal();
                return (status.isEmpty || o['status'] == status) &&
                    (fulfillment.isEmpty || o['fulfillment'] == fulfillment) &&
                    (from == null || !created.isBefore(from)) &&
                    (to == null || !created.isAfter(to)) &&
                    (q.isEmpty || _match(o['order_number'], q) || _match(_find('customers', o['customer_id'])?['name'], q) || _match(_find('vendors', o['vendor_id'])?['name'], q));
              })
              .map(_adminOrder)
              .toList(),
          uri,
        );

      // ---- Deliveries & operations ----
      case 'GET /admin/operations/live-map':
        final active = _list('orders').where((o) => o['fulfillment'] == 'delivery' && const ['ready', 'assigned', 'picked_up', 'out_for_delivery'].contains(o['status']));
        return {
          'generated_at': _now,
          'kitchens': [
            for (final v in _list('vendors').where((v) => v['status'] == 'approved' && v['is_open'] == true))
              {'name': v['name'], 'neighborhood': v['neighborhood'], 'latitude': v['location']['latitude'], 'longitude': v['location']['longitude']},
          ],
          'deliveries': [
            for (final o in active)
              {
                'order_number': o['order_number'],
                'status': _delivery(o)!['status'],
                'status_label': _labels[o['status']],
                'late': o['late'] == true,
                'offered_to': 3,
                'destination': _destination(o),
                'kitchen': _find('vendors', o['vendor_id'])!['location'],
                'driver': o['driver_id'] == null
                    ? null
                    : {'id': o['driver_id'], 'name': _find('drivers', o['driver_id'])!['name'], 'location': (_live(o)['driver'] as Map)['location']},
              },
          ],
          'drivers': [
            for (final d in _list('drivers').where((d) => d['is_online'] == true && d['latitude'] != null)) {..._adminDriver(d), 'counts_for_dispatch': true},
          ],
        };
      case 'GET /admin/deliveries/live':
        return _page(_list('orders').where((o) => o['fulfillment'] == 'delivery' && const ['ready', 'assigned', 'picked_up', 'out_for_delivery'].contains(o['status'])).map((o) => _delivery(o)!).toList(), uri);
      case 'GET /admin/operations/late-pickups':
        final charge = _q(uri, 'charge_status');
        final late = [
          for (final o in _list('orders').where((o) => o['late'] == true))
            {
              'key': 'late-${o['id']}',
              'order_id': o['id'],
              'order_number': o['order_number'],
              'vendor': {'name': _find('vendors', o['vendor_id'])?['name']},
              'driver': {'name': _find('drivers', o['driver_id'])?['name'], 'phone': _find('drivers', o['driver_id'])?['phone']},
              'ready_at': o['ready_at'],
              'pickup_due_at': _delivery(o)?['pickup_due_at'],
              'minutes_late': 7,
              'still_waiting': o['status'] == 'assigned',
              'reassigned_at': null,
              'picked_up_at': _delivery(o)?['picked_up_at'],
              'charge_status': 'waived',
              'note': 'Late pickups are not charged.',
              'can_reassign': o['status'] == 'assigned',
            },
        ].where((row) => charge.isEmpty || row['charge_status'] == charge).toList();
        return {..._page(late, uri), 'pending_charges': 0, 'still_waiting': late.where((r) => r['still_waiting'] == true).length};
      case 'GET /admin/operations/rules':
        return _rules();
      case 'PUT /admin/operations/rules':
        final r = s['rules'] as Json;
        r['radius_km'] = body['radius_km'];
        r['max_drivers_per_broadcast'] = body['max_offer_recipients'];
        r['driver_location_max_age_minutes'] = body['location_max_age_minutes'];
        r['rebroadcast_every_seconds'] = body['rebroadcast_every_seconds'];
        r['max_active_deliveries_per_driver'] = body['max_active_deliveries'];
        r['platform_delivery_max_km'] = body['platform_delivery_max_km'];
        r['max_wrong_codes'] = body['pickup_code_max_attempts'];
        r['updated_at'] = _now;
        _log('settings.dispatch_rules', 'settings', 'Delivery & pickup rules');
        return _rules();
      case 'GET /admin/settings/delivery-fees':
        return s['fees'];
      case 'PUT /admin/settings/delivery-fees':
        s['fees'] = {'ranges': body['ranges'], 'updated_at': _now};
        _log('settings.delivery_fees', 'settings', 'Delivery fee by distance');
        return s['fees'];
      case 'GET /admin/settings/banks':
        return s['banks'];
      case 'PUT /admin/settings/banks':
        s['banks'] = {'banks': body['banks'], 'updated_at': _now};
        _log('settings.banks', 'settings', 'Bank account numbers');
        return s['banks'];
      case 'GET /admin/operations/delivery-timing':
        return {'timing': s['timing']};
      case 'PUT /admin/operations/delivery-timing':
        s['timing'] = {...body, 'updated_at': _now};
        _log('settings.delivery_timing', 'settings', 'Delivery timing');
        return {'timing': s['timing']};

      // ---- Payments & commissions ----
      case 'GET /admin/payments/summary':
        final rows = _payments;
        final statuses = rows.map((r) => r['status']).toSet();
        final ok = rows.where((r) => r['status'] == 'successful');
        return {
          'successful_total_rwf': ok.fold<int>(0, (sum, r) => sum + (r['amount_rwf'] as int)),
          'successful_count': ok.length,
          'by_status': [
            for (final status in statuses)
              {'status': status, 'count': rows.where((r) => r['status'] == status).length, 'total_rwf': rows.where((r) => r['status'] == status).fold<int>(0, (sum, r) => sum + (r['amount_rwf'] as int))},
          ],
        };
      case 'GET /admin/payments':
        final status = _q(uri, 'status');
        final payMethod = _q(uri, 'method');
        return _page(_payments.where((r) => (status.isEmpty || r['status'] == status) && (payMethod.isEmpty || r['method'] == payMethod)).toList(), uri);
      case 'GET /admin/commissions':
        return {'items': _list('commissions')};
      case 'POST /admin/commissions':
        final rule = _commission({'id': _id('com')}, body);
        _list('commissions').add(rule);
        _log('commission.created', 'commission', rule['name']);
        return {'commission': rule};

      // ---- Payouts ----
      case 'GET /admin/payouts':
        final status = _q(uri, 'status');
        final type = _q(uri, 'payee_type');
        return _page(_list('withdrawals').where((w) => (status.isEmpty || w['status'] == status) && (type.isEmpty || w['payee_type'] == type)).toList(), uri);
      case 'GET /admin/payouts/summary':
        final type = _q(uri, 'payee_type');
        final rows = _list('withdrawals').where((w) => type.isEmpty || w['payee_type'] == type).toList();
        return {
          'by_status': [
            for (final status in rows.map((w) => w['status']).toSet())
              {'status': status, 'count': rows.where((w) => w['status'] == status).length, 'total_rwf': rows.where((w) => w['status'] == status).fold<int>(0, (sum, w) => sum + (w['amount_rwf'] as int))},
          ],
        };
      case 'GET /admin/payouts/balances':
        final drivers = _q(uri, 'payee_type') == 'driver';
        final rows = drivers
            ? [..._list('drivers')]
            : [for (final v in _list('vendors')) {...v, 'estimated_commission_rwf': (v['total_sales_rwf'] as int) * _commissionPercent ~/ 100}];
        rows.sort((a, b) => (b['available_balance_rwf'] as int).compareTo(a['available_balance_rwf'] as int));
        return _page(rows, uri);

      // ---- Refunds ----
      case 'GET /admin/refunds':
        final status = _q(uri, 'status');
        final q = _q(uri, 'search').toLowerCase();
        final all = _list('refunds');
        Json sum(String st) {
          final rows = all.where((r) => r['status'] == st);
          return {'count': rows.length, 'amount_rwf': rows.fold<int>(0, (t, r) => t + (r['amount_rwf'] as int))};
        }
        return {
          ..._page(all.where((r) => (status.isEmpty || r['status'] == status) && (q.isEmpty || _match(r['order_number'], q) || _match(r['customer']['phone'], q) || _match(r['reference'], q))).toList(), uri),
          'summary': {'pending': sum('pending'), 'failed': sum('failed'), 'completed': sum('completed')},
          'payout_service': {'automatic': false, 'label': 'Manual (demo)'},
        };

      // ---- Categories ----
      case 'GET /admin/categories':
        final list = [..._list('categories')]..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
        return {'items': list};
      case 'POST /admin/categories':
        final category = {'id': _id('cat'), 'created_by_vendor': null, ...body};
        _list('categories').add(category);
        _log('category.created', 'category', category['name']);
        return {'category': category};
      case 'PATCH /admin/categories/reorder':
        for (final item in (body['items'] as List? ?? const [])) {
          _find('categories', item['id'])?['sort_order'] = item['sort_order'];
        }
        return {'ok': true};

      // ---- Complaints & chats ----
      case 'GET /admin/complaints':
        final status = _q(uri, 'status');
        final category = _q(uri, 'category');
        final priority = _q(uri, 'priority');
        final q = _q(uri, 'search').toLowerCase();
        final list = _list('complaints')
            .where((c) => (status.isEmpty || c['status'] == status) && (category.isEmpty || c['category'] == category) && (priority.isEmpty || c['priority'] == priority) && (q.isEmpty || _match(c['subject'], q) || _match(c['reference'], q)))
            .toList()
          ..sort((a, b) => (b['unread'] == true ? 1 : 0).compareTo(a['unread'] == true ? 1 : 0));
        return {..._page(list, uri), 'counts': _complaintCounts()};
      case 'POST /admin/complaints':
        final complaint = {
          'id': _id('cmp'),
          'reference': 'SUP-${_seq + 100}',
          'subject': body['subject'],
          'description': body['description'],
          'category': body['category'],
          'priority': body['priority'],
          'status': 'open',
          'unread': false,
          'raised_by': {'role': 'guest', 'user_id': null, 'name': body['name'], 'phone': body['phone']},
          'messages': <Json>[],
          'notes': <Json>[],
          'created_at': _now,
          'last_message_at': _now,
        };
        _list('complaints').insert(0, complaint);
        _log('complaint.created', 'complaint', complaint['reference']);
        return {'complaint': complaint};
      case 'GET /admin/chats':
        final q = _q(uri, 'search').toLowerCase();
        return _page([
          for (final c in _list('chats'))
            if (q.isEmpty || _match(c['customer']['name'], q) || _match(c['vendor']['name'], q) || _match(c['customer']['phone'], q))
              {
                'id': c['id'],
                'customer': {'name': c['customer']['name'], 'phone': c['customer']['phone']},
                'vendor': {'name': c['vendor']['name'], 'vendor_type': c['vendor']['vendor_type']},
                'last_message_role': (c['messages'] as List).last['author_role'],
                'last_message_preview': (c['messages'] as List).last['body'],
                'last_message_at': (c['messages'] as List).last['created_at'],
                'messages_count': (c['messages'] as List).length,
              },
        ], uri);

      // ---- Books & analytics & audit ----
      case 'GET /admin/platform/wallet':
        final books = _books();
        final type = _q(uri, 'type');
        // The same entries, wording and order as the website's demo ledger.
        Json tx(String id, String type, String direction, num amount, dynamic at, String description, {dynamic order, dynamic reference}) => {
              'id': id,
              'type': type,
              'direction': direction,
              'amount_rwf': amount,
              'order_number': order,
              'reference': reference,
              'description': description,
              'created_at': at,
            };
        final ledger = <Json>[
          for (final o in _list('orders').where((o) => o['payment_status'] != 'pending')) ...[
            tx('tx-pay-${o['id']}', 'order_payment', 'credit', o['total_amount_rwf'], o['created_at'], 'Payment for ${o['order_number']}', order: o['order_number']),
            if (o['status'] == 'delivered') ...[
              tx('tx-ven-${o['id']}', 'vendor_earning', 'debit', (o['subtotal_rwf'] as int) - (o['subtotal_rwf'] as int) * _commissionPercent ~/ 100, o['created_at'],
                  '${_find('vendors', o['vendor_id'])?['name']} earned', order: o['order_number']),
              if (o['driver_id'] != null)
                tx('tx-drv-${o['id']}', 'driver_earning', 'debit', o['delivery_fee_rwf'], o['created_at'], 'Delivery worker earned', order: o['order_number']),
              tx('tx-com-${o['id']}', 'commission', 'credit', (o['subtotal_rwf'] as int) * _commissionPercent ~/ 100, o['created_at'], 'Commission and delivery margin',
                  order: o['order_number']),
            ],
          ],
          for (final r in _list('refunds').where((r) => r['status'] == 'completed'))
            tx('tx-${r['id']}', 'refund', 'debit', r['amount_rwf'], r['created_at'], 'Refund sent to the customer', order: r['order_number'], reference: r['reference']),
          for (final w in _list('withdrawals').where((w) => w['status'] == 'completed'))
            tx('tx-${w['id']}', 'withdrawal', 'debit', w['amount_rwf'], w['created_at'], 'Withdrawal to ${w['payee_name']}', reference: w['reference']),
        ].where((t) => type.isEmpty || t['type'] == type).toList()
          ..sort((a, b) => b['created_at'].toString().compareTo(a['created_at'].toString()));
        final paged = _page(ledger, uri);
        return {
          'account': {
            ...books,
            'reconciliation': {'balanced': true, 'unreconciled_rwf': 0},
            'total_collected_rwf': _payments.where((p) => p['status'] != 'pending').fold<int>(0, (t, p) => t + (p['amount_rwf'] as int)),
            'total_refunded_rwf': _list('refunds').where((r) => r['status'] == 'completed').fold<int>(0, (t, r) => t + (r['amount_rwf'] as int)),
            'total_vendor_payouts_rwf': _list('withdrawals').where((w) => w['status'] == 'completed' && w['payee_type'] == 'vendor').fold<int>(0, (t, w) => t + (w['amount_rwf'] as int)),
            'total_driver_payouts_rwf': _list('withdrawals').where((w) => w['status'] == 'completed' && w['payee_type'] == 'driver').fold<int>(0, (t, w) => t + (w['amount_rwf'] as int)),
            'computed_at': _now,
          },
          'transactions': paged['items'],
          'page': paged['page'],
          'limit': paged['limit'],
          'total': paged['total'],
        };
      case 'GET /admin/analytics/overview':
        final done = _list('orders').where((o) => o['status'] == 'delivered').toList();
        final gross = done.fold<int>(0, (t, o) => t + (o['subtotal_rwf'] as int));
        final byVendor = <String, Json>{};
        for (final o in done) {
          final v = _find('vendors', o['vendor_id'])!;
          final row = byVendor.putIfAbsent(v['id'], () => {'vendor_id': v['id'], 'name': v['name'], 'orders': 0, 'gross_rwf': 0});
          row['orders'] = (row['orders'] as int) + 1;
          row['gross_rwf'] = (row['gross_rwf'] as int) + (o['subtotal_rwf'] as int);
        }
        final top = byVendor.values.toList()..sort((a, b) => (b['gross_rwf'] as int).compareTo(a['gross_rwf'] as int));
        final deliveries = <String, int>{};
        // Grouped by delivery step, as the website shows them.
        for (final o in _list('orders').where((o) => o['fulfillment'] == 'delivery')) {
          final step = switch (o['status']) {
            'placed' || 'confirmed' || 'preparing' => 'pending',
            'ready' || 'assigned' => 'ready_for_pickup',
            'picked_up' || 'out_for_delivery' => 'out_for_delivery',
            final other => other.toString(),
          };
          deliveries.update(step, (n) => n + 1, ifAbsent: () => 1);
        }
        return {
          'sales': {'gross_rwf': gross, 'orders': done.length, 'commission_rwf': gross * _commissionPercent ~/ 100, 'commission_percent': _commissionPercent, 'delivery_fees_rwf': done.fold<int>(0, (t, o) => t + (o['delivery_fee_rwf'] as int))},
          'signups': {'customers': 6, 'vendors': 2, 'drivers': 1},
          'orders_created': _list('orders').length,
          'top_vendors': top.take(5).toList(),
          'deliveries_by_status': deliveries,
          'complaints_by_status': {for (final e in _complaintCounts().entries.where((e) => e.key != 'unread')) e.key: e.value},
        };
      case 'GET /admin/analytics/sales':
        final hourly = _q(uri, 'granularity') == 'hour';
        final buckets = <String, int>{};
        for (final o in _list('orders').where((o) => o['status'] == 'delivered')) {
          final d = _date(o['created_at']).toLocal();
          final key = hourly ? '${isoDayOf(d)} ${d.hour.toString().padLeft(2, '0')}:00' : isoDayOf(d);
          buckets.update(key, (n) => n + (o['subtotal_rwf'] as int), ifAbsent: () => o['subtotal_rwf'] as int);
        }
        final keys = buckets.keys.toList()..sort();
        return {'series': [for (final k in keys) {'period': k, 'gross_rwf': buckets[k]}]};
      case 'GET /admin/analytics/payouts':
        final rows = _list('withdrawals');
        final vendors = [..._list('vendors')]..sort((a, b) => (b['available_balance_rwf'] as int).compareTo(a['available_balance_rwf'] as int));
        return {
          'withdrawals_by_status': [
            for (final status in rows.map((w) => w['status']).toSet())
              {'status': status, 'count': rows.where((w) => w['status'] == status).length, 'total_rwf': rows.where((w) => w['status'] == status).fold<int>(0, (t, w) => t + (w['amount_rwf'] as int))},
          ],
          'top_vendor_balances': [for (final v in vendors.take(5)) {'vendor_id': v['id'], 'name': v['name'], 'available_balance_rwf': v['available_balance_rwf']}],
        };
      case 'GET /admin/actions':
        final action = _q(uri, 'action').toLowerCase();
        final target = _q(uri, 'target_type').toLowerCase();
        return _page(_list('actions').where((a) => (action.isEmpty || _match(a['action'], action)) && (target.isEmpty || _match(a['target_type'], target))).toList(), uri, 25);

      // ---- Team ----
      case 'GET /admin/team':
        return {'members': _list('team'), 'roles': _roles, 'categories': _permissionCategories, 'permissions': _permissions};
      case 'POST /admin/team/invitations':
        final role = _roles.firstWhere((r) => r['id'] == body['role'], orElse: () => _roles.first);
        final member = {
          'id': _id('a'),
          'name': body['name'],
          'email': body['email'],
          'role': role['id'],
          'role_label': role['label'],
          'status': 'invited',
          'two_factor_enabled': false,
          'phone': '',
          'invite_expires_at': _in(const Duration(days: 7)),
          'last_login_at': null,
        };
        _list('team').add(member);
        _log('team.invite_sent', 'admin', member['email']);
        // Demo mode sends no email, so the link is shown to share by hand.
        return {'member': member, 'invite_url': 'https://kitchenlink.rw/admin-invite?token=demo-${member['id']}'};

      // ---- Owner's money ----
      case 'GET /admin/platform/owner':
        return _ownerOverview();
      case 'POST /admin/platform/owner/withdrawals':
        _code(body['otp_code']);
        final overview = _ownerOverview();
        final max = overview['withdrawable']['max_now_rwf'] as int;
        final amount = jint(body['amount_rwf']);
        if (amount <= 0 || amount > max) _fail(400, 'Enter a whole amount up to ${_rwf(max)}.');
        final owner = s['owner'] as Json;
        final dest = (owner['destinations'] as List).firstWhere((d) => d['id'] == body['destination_id']);
        (owner['withdrawals'] as List).insert(0, {
          'id': _id('pw'),
          'amount_rwf': amount,
          'status': 'processing',
          'source': body['source'],
          'created_at': _now,
          'destination': {'label': dest['label'], 'provider': dest['provider'], 'account_name': dest['account_name'], 'account_number': dest['account_number']},
        });
        _log('platform.withdrawal_requested', 'platform', _rwf(amount));
        return {'ok': true};
      case 'POST /admin/platform/owner/destinations':
        _code(body['otp_code']);
        final owner = s['owner'] as Json;
        (owner['destinations'] as List).add({
          'id': _id('dest'),
          'type': body['type'],
          'label': body['label'],
          'provider': body['provider'],
          'account_name': body['account_name'],
          'account_number': body['account_number'],
          'ready': false,
          'activates_at': _in(const Duration(hours: 48)),
        });
        _log('platform.destination_added', 'platform', jstr(body['label']));
        return {'ok': true};
      case 'POST /admin/platform/owner/adjustments':
        _code(body['otp_code']);
        final owner = s['owner'] as Json;
        owner['adjustments_rwf'] = (owner['adjustments_rwf'] as int) + jint(body['amount_rwf']);
        _log('platform.adjustment', 'platform', '${jint(body['amount_rwf'])} RWF · ${body['reason']}');
        return {'ok': true};
      case 'POST /admin/platform/owner/reconciliations':
        final books = _books();
        final statement = jint(body['statement_balance_rwf']);
        final diff = statement - (books['cash_balance_rwf'] as int);
        ((s['owner'] as Json)['reconciliations'] as List).insert(0, {
          'id': _id('rec'),
          'account_label': body['account_label'],
          'statement_date': body['statement_date'],
          'statement_balance_rwf': statement,
          'system_cash_rwf': books['cash_balance_rwf'],
          'difference_rwf': diff,
          'matches': diff == 0,
        });
        return {'ok': true};
      case 'PUT /admin/platform/owner/payout-settings':
        _code(body['otp_code']);
        final owner = s['owner'] as Json;
        final settings = owner['payout_settings'] as Json;
        final isBank = body['method'] == 'bank';
        final account = {
          'provider': isBank ? body['bank_name'] : body['network'],
          'account_name': body['account_name'],
          'account_number': isBank ? body['account_number'] : body['phone'],
        };
        final old = settings['account'] as Map;
        final changed = old['provider'] != account['provider'] || old['account_number'] != account['account_number'];
        settings['method'] = body['method'];
        settings['account'] = {...account, 'ready': !changed && old['ready'] == true, 'activates_at': changed ? _in(const Duration(hours: 48)) : old['activates_at']};
        settings['schedule'] = body['schedule'];
        _log('platform.payout_settings', 'platform', 'Payout settings');
        return {'ok': true, 'account_changed': changed};
    }

    // Routes with an id in the path.
    if (p.length >= 3) {
      final tail = p.sublist(3).join('/');
      switch ((method, seg(1), tail)) {
        case ('POST', 'notifications', 'read'):
          _find('notifications', id)?['read'] = true;
          return {'ok': true};

        case ('GET', 'vendors', ''):
          final vendor = _adminVendor(_must('vendors', id, 'Vendor'));
          return {
            'vendor': vendor,
            'recent_orders': _list('orders').where((o) => o['vendor_id'] == id).take(5).map(_adminOrder).toList(),
          };
        case ('PATCH', 'vendors', 'status'):
          final vendor = _must('vendors', id, 'Vendor');
          final status = jstr(body['status']);
          if (status == 'approved' && vendor['documents_reviewed_at'] == null) {
            _fail(409, "Review this vendor's verification documents before approving.", 'DOCUMENTS_NOT_REVIEWED');
          }
          vendor['status'] = status;
          vendor['suspension_reason'] = status == 'suspended' ? body['reason'] : null;
          vendor['rejection_reason'] = status == 'rejected' ? body['reason'] : null;
          if (status != 'approved') vendor['is_open'] = false;
          _log('vendor.$status', 'vendor', vendor['name']);
          return {'vendor': _adminVendor(vendor), 'cancelled_orders': 0};
        case ('PATCH', 'vendors', 'type'):
          final vendor = _must('vendors', id, 'Vendor');
          final request = vendor['vendor_type_request'];
          final decision = body['decision'] == 'approve' || body['decision'] == 'reject' ? body['decision'] : null;
          if (decision != null && request is! Map) _fail(409, 'This vendor has no pending type change request.', 'NO_TYPE_REQUEST');
          if (decision == null && _typeLocked(vendor)) {
            _fail(409, 'This kitchen is approved, so its type can only change when the vendor asks for it from their profile.', 'VENDOR_TYPE_LOCKED');
          }
          if (decision == 'approve' && request is Map) vendor['vendor_type'] = request['vendor_type'];
          if (decision == null && body['vendor_type'] != null) vendor['vendor_type'] = body['vendor_type'];
          vendor['vendor_type_request'] = null;
          _log('vendor.type_changed', 'vendor', vendor['name']);
          return {'vendor': _adminVendor(vendor)};
        case ('PATCH', 'vendors', 'nationwide'):
          final vendor = _must('vendors', id, 'Vendor');
          vendor['nationwide_override'] = body['enabled'];
          _log('vendor.nationwide', 'vendor', vendor['name']);
          return {'vendor': _adminVendor(vendor)};
        case ('POST', 'vendors', 'documents/review'):
          final vendor = _must('vendors', id, 'Vendor');
          vendor['documents_reviewed_at'] = _now;
          _log('vendor.documents_reviewed', 'vendor', vendor['name']);
          return {'vendor': _adminVendor(vendor)};

        case ('GET', 'drivers', ''):
          return {'driver': _adminDriver(_must('drivers', id, 'Delivery worker'))};
        case ('PATCH', 'drivers', 'status'):
          final driver = _must('drivers', id, 'Delivery worker');
          driver['verification_status'] = body['status'];
          if (body['status'] != 'approved') driver['is_online'] = false;
          _log('driver.${body['status']}', 'driver', driver['name']);
          return {'driver': _adminDriver(driver), 'released_deliveries': 0};

        case ('PATCH', 'users', 'status'):
          final role = body['role'];
          final key = role == 'customer' ? 'customers' : role == 'vendor' ? 'vendors' : 'drivers';
          final user = _must(key, id, 'User');
          user[role == 'driver' ? 'verification_status' : 'status'] = body['status'];
          _log('$role.${body['status']}', role.toString(), user['name']);
          return {'ok': true};
        case ('POST', 'users', 'erase'):
          final customer = _must('customers', id, 'Customer');
          if (_list('orders').any((o) => o['customer_id'] == id && !const ['delivered', 'cancelled'].contains(o['status']))) {
            _fail(409, 'This customer has an order in progress. Try again once it is finished.', 'ORDER_IN_PROGRESS');
          }
          customer
            ..['name'] = 'Erased customer'
            ..['phone'] = ''
            ..['location'] = null
            ..['status'] = 'erased';
          _log('customer.erased', 'customer', id);
          return {'ok': true};

        case ('GET', 'orders', ''):
          final order = _must('orders', id, 'Order');
          final d = _delivery(order);
          return {
            'order': _adminOrder(order),
            'delivery': d,
            'dispatch': d == null
                ? null
                : {
                    'radius_km': s['rules']['radius_km'],
                    'last_broadcast_at': order['ready_at'],
                    'replaced_late': <Json>[],
                    'offers': [
                      for (final drv in _list('drivers').where((x) => x['is_online'] == true).take(3))
                        {'driver_id': drv['id'], 'driver_name': drv['name'], 'response': drv['id'] == order['driver_id'] ? 'accepted' : order['driver_id'] == null ? 'offered' : 'cancelled'},
                    ],
                  },
          };
        case ('PATCH', 'orders', 'status'):
          final order = _must('orders', id, 'Order');
          _setStatus(order, jstr(body['status']), jstr(body['note'], 'Changed by an admin'));
          return {'order': _adminOrder(order)};
        case ('POST', 'orders', 'cancel'):
          final order = _must('orders', id, 'Order');
          if (const ['delivered', 'cancelled'].contains(order['status'])) _fail(409, 'This order is already closed.');
          order['cancel_reason'] = jstr(body['reason'], 'Cancelled by KitchenLink support');
          _setStatus(order, 'cancelled', order['cancel_reason']);
          final customer = _find('customers', order['customer_id'])!;
          _list('refunds').insert(0, {
            'id': _id('rf'),
            'order_id': order['id'],
            'order_number': order['order_number'],
            'customer': {'name': customer['name'], 'phone': customer['phone']},
            'amount_rwf': order['total_amount_rwf'],
            'destination': {'label': 'MTN Mobile Money ${customer['phone']}'},
            'status': 'pending',
            'cancelled_by': 'admin',
            'reason': order['cancel_reason'],
            'created_at': _now,
          });
          return {'order': _adminOrder(order)};
        case ('GET', 'orders', 'nearby-drivers'):
          final order = _must('orders', id, 'Order');
          final includeOffline = _q(uri, 'include_offline') == 'true';
          final kitchen = _find('vendors', order['vendor_id'])!['location'] as Map;
          final current = _find('drivers', order['driver_id']);
          final drivers = <Json>[];
          for (final d in _list('drivers').where((d) => d['verification_status'] == 'approved' && d['id'] != order['driver_id'] && (includeOffline || d['is_online'] == true))) {
            final known = d['latitude'] != null;
            final km = known ? _km(kitchen['latitude'], kitchen['longitude'], d['latitude'], d['longitude']) : null;
            final active = _adminDriver(d)['active_deliveries_count'] as int;
            drivers.add({
              'id': d['id'],
              'name': d['name'],
              'phone': d['phone'],
              'vehicle_type': d['vehicle_type'],
              'plate_number': d['plate_number'],
              'is_online': d['is_online'],
              'location_known': known,
              'distance_km': km,
              'within_radius': km != null && km <= (s['rules']['radius_km'] as num),
              'location_updated_at': known ? _ago(Duration(minutes: d['is_online'] == true ? 1 : 45)) : null,
              'location_fresh': d['is_online'] == true,
              'active_deliveries': active,
              'has_capacity': active < (s['rules']['max_active_deliveries_per_driver'] as int),
            });
          }
          drivers.sort((a, b) => ((a['distance_km'] ?? 999) as num).compareTo((b['distance_km'] ?? 999) as num));
          return {
            'order_number': order['order_number'],
            'collected': const ['picked_up', 'out_for_delivery', 'delivered'].contains(order['status']),
            'kitchen': {'name': _find('vendors', order['vendor_id'])!['name']},
            'kitchen_ready': order['ready_at'] != null,
            'current_driver': current == null ? null : {'name': current['name'], 'phone': current['phone']},
            'late': order['late'] == true,
            'pickup_due_at': _delivery(order)?['pickup_due_at'],
            'radius_km': s['rules']['radius_km'],
            'drivers': drivers,
          };
        case ('POST', 'orders', 'reassign-driver'):
          final order = _must('orders', id, 'Order');
          final driver = _must('drivers', body['driver_id'], 'Delivery worker');
          order['driver_id'] = driver['id'];
          order['late'] = false;
          if (order['status'] == 'ready') order['status'] = 'assigned';
          (order['status_history'] as List).add({'status': order['status'], 'label': 'Given to ${driver['name']}', 'at': _now, 'note': jstr(body['note'])});
          _log('order.reassigned', 'order', '${order['order_number']} → ${driver['name']}');
          return {'order': _adminOrder(order)};

        case ('GET', 'deliveries', 'live'):
          final order = _list('orders').where((o) => 'del-${o['id']}' == id).firstOrNull;
          return order == null ? {'active': false} : _live(order);

        case ('PUT', 'commissions', ''):
          final rule = _must('commissions', id, 'Commission rule');
          _commission(rule, body);
          _log('commission.updated', 'commission', rule['name']);
          return {'commission': rule};
        case ('DELETE', 'commissions', ''):
          _list('commissions').removeWhere((c) => c['id'] == id);
          _log('commission.deleted', 'commission', id);
          return {'ok': true};

        case ('PATCH', 'payouts', ''):
          final w = _must('withdrawals', id, 'Withdrawal');
          if (w['status'] == 'processing') {
            if (body['status'] == 'completed' && (w['amount_rwf'] as int) >= 50000) _code(body['action_code']);
            if (body['status'] == 'completed' && jstr(body['reference']).trim().isEmpty) _fail(400, 'Enter the transaction reference.');
            w['status'] = body['status'];
            w['failure_reason'] = body['status'] == 'failed' ? body['reason'] : null;
            final payee = _find(w['payee_type'] == 'driver' ? 'drivers' : 'vendors', w['payee_id']);
            if (payee != null && body['status'] == 'completed') {
              payee['available_balance_rwf'] = math.max(0, (payee['available_balance_rwf'] as int) - (w['amount_rwf'] as int));
            }
          }
          w['reference'] = body['reference'];
          _log('payout.${w['status']}', 'payout', '${w['payee_name']} · ${_rwf(w['amount_rwf'])}');
          return {'withdrawal': w};

        case ('PATCH', 'refunds', ''):
          final refund = _must('refunds', id, 'Refund');
          refund['status'] = body['status'];
          refund['reference'] = body['reference'];
          refund['failure_reason'] = body['status'] == 'failed' ? body['reason'] : null;
          _log('refund.${body['status']}', 'refund', refund['order_number']);
          return {'refund': refund};

        case ('PUT', 'categories', ''):
          final category = _must('categories', id, 'Category');
          category.addAll(body);
          _log('category.updated', 'category', category['name']);
          return {'category': category};
        case ('DELETE', 'categories', ''):
          final category = _must('categories', id, 'Category');
          if (category['created_by_vendor'] != null && _q(uri, 'force') != 'true') {
            _fail(409, 'This category is used by vendors.', 'CATEGORY_IN_USE');
          }
          _list('categories').removeWhere((c) => c['id'] == id);
          _log('category.deleted', 'category', category['name']);
          return {'ok': true};

        case ('GET', 'complaints', ''):
          final complaint = _must('complaints', id, 'Complaint');
          complaint['unread'] = false;
          return {'complaint': complaint};
        case ('PATCH', 'complaints', ''):
          final complaint = _must('complaints', id, 'Complaint');
          if (body['status'] != null) complaint['status'] = body['status'];
          if (body['priority'] != null) complaint['priority'] = body['priority'];
          if (body['note'] != null) (complaint['notes'] as List).add({'body': body['note'], 'author_name': 'Demo Owner', 'at': _now});
          if (body['reply'] != null) {
            (complaint['messages'] as List).add({'id': _id('msg'), 'author_role': 'admin', 'author_name': 'Demo Owner', 'body': body['reply'], 'at': _now});
            complaint['last_message_at'] = _now;
          }
          _log('complaint.updated', 'complaint', complaint['reference']);
          return {'complaint': complaint};

        case ('GET', 'chats', ''):
          final chat = _must('chats', id, 'Chat');
          return {
            'conversation': {'customer': chat['customer'], 'vendor': chat['vendor']},
            'messages': chat['messages'],
            'has_more': false,
          };

        case ('PATCH', 'team', 'role'):
          _code(body['action_code']);
          final member = _must('team', id, 'Team member');
          final role = _roles.firstWhere((r) => r['id'] == body['role']);
          member['role'] = role['id'];
          member['role_label'] = role['label'];
          _log('team.role_changed', 'admin', member['email']);
          return {'member': member};
        case ('POST', 'team', 'resend-invitation'):
          final member = _must('team', id, 'Team member');
          member['status'] = 'invited';
          member['invite_expires_at'] = _in(const Duration(days: 7));
          _log('team.invite_sent', 'admin', member['email']);
          return {'member': member, 'invite_url': 'https://kitchenlink.rw/admin-invite?token=demo-${member['id']}'};
        case ('POST', 'team', 'deactivate'):
          final member = _must('team', id, 'Team member');
          member['status'] = 'deactivated';
          _log('team.deactivated', 'admin', member['email']);
          return {'member': member};
        case ('POST', 'team', 'reactivate'):
          _code(body['action_code']);
          final member = _must('team', id, 'Team member');
          member['status'] = 'active';
          _log('team.reactivated', 'admin', member['email']);
          return {'member': member};
        case ('DELETE', 'team', ''):
          final member = _must('team', id, 'Team member');
          _list('team').remove(member);
          _log('team.removed', 'admin', member['email']);
          return {'ok': true};
      }

      // /admin/platform/owner/<thing>/<id>/<action>
      if (seg(1) == 'platform' && seg(2) == 'owner' && p.length >= 6) {
        final owner = s['owner'] as Json;
        final itemId = seg(4);
        switch ((seg(3), seg(5))) {
          case ('withdrawals', 'complete'):
            final w = (owner['withdrawals'] as List).firstWhere((w) => w['id'] == itemId) as Map;
            w['status'] = 'completed';
            w['reference'] = body['reference'];
            owner['withdrawn_rwf'] = (owner['withdrawn_rwf'] as int) + (w['amount_rwf'] as int);
            _log('platform.withdrawal_completed', 'platform', _rwf(w['amount_rwf']));
            return {'ok': true};
          case ('withdrawals', 'cancel'):
            final w = (owner['withdrawals'] as List).firstWhere((w) => w['id'] == itemId) as Map;
            w['status'] = 'cancelled';
            w['failure_reason'] = jstr(body['reason'], 'Cancelled');
            return {'ok': true};
          case ('destinations', 'remove'):
            _code(body['otp_code']);
            (owner['destinations'] as List).removeWhere((d) => d['id'] == itemId);
            _log('platform.destination_removed', 'platform', itemId);
            return {'ok': true};
        }
      }
    }
    _fail(404, 'This screen is not available in demo mode.', 'NOT_FOUND');
  }

  Json _commission(Json rule, Json body) {
    rule.addAll(body);
    rule['vendor_name'] = body['scope'] == 'vendor' ? (_find('vendors', body['vendor_id'])?['name']) : null;
    rule['category_name'] = body['scope'] == 'category' ? (_find('categories', body['category_id'])?['name']) : null;
    rule['vendor_type_label'] = null;
    return rule;
  }

  void _setStatus(Json order, String status, String note) {
    order['status'] = status;
    if (status == 'ready' && order['ready_at'] == null) order['ready_at'] = _now;
    if (status == 'delivered' || status == 'cancelled') order['late'] = false;
    (order['status_history'] as List).add({'status': status, 'label': _labels[status] ?? status, 'at': _now, 'note': note});
    _log('order.$status', 'order', order['order_number']);
  }

  Json _ownerOverview() {
    final owner = s['owner'] as Json;
    final books = _books();
    final withdrawals = (owner['withdrawals'] as List).cast<Json>();
    final processing = withdrawals.where((w) => w['status'] == 'processing').fold<int>(0, (t, w) => t + (w['amount_rwf'] as int));
    final reserve = (books['owner_balance_rwf'] as int) * 10 ~/ 100;
    final available = math.max(0, (books['owner_balance_rwf'] as int) - reserve - processing);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = withdrawals.where((w) => w['status'] == 'completed' && _date(w['created_at']).isAfter(weekAgo)).fold<int>(0, (t, w) => t + (w['amount_rwf'] as int));
    final destinations = (owner['destinations'] as List).cast<Json>();
    final admin = s['admin'] as Json;
    return {
      'security': {'uses_default_password': admin['uses_default_password'], 'two_factor_enabled': admin['two_factor_enabled'], 'default_jwt_secret': false},
      'books': books,
      'withdrawable': {
        'available_rwf': available,
        'reserve_percent': 10,
        'reserve_rwf': reserve,
        'max_now_rwf': math.min(available, math.min(500000, math.max(0, 2000000 - thisWeek))),
        'max_per_withdrawal_rwf': 500000,
        'withdrawn_this_week_rwf': thisWeek,
        'max_weekly_rwf': 2000000,
        'processing_rwf': processing,
      },
      'blockers': [
        if (!destinations.any((d) => d['ready'] == true)) {'code': 'NO_DESTINATION', 'message': 'Add a company payout account first (it unlocks after a waiting period).'},
        if (available <= 0 && processing == 0) {'code': 'NOTHING_AVAILABLE', 'message': 'Nothing is available to withdraw yet.'},
      ],
      'destinations': destinations,
      'withdrawals': withdrawals,
      'payout_settings': owner['payout_settings'],
      'sweep': {'last_at': _ago(const Duration(days: 4)), 'last_amount_rwf': 0},
      'reconciliations': owner['reconciliations'],
    };
  }

  static String _rwf(dynamic value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0 && digits[i - 1] != '-') out.write(',');
      out.write(digits[i]);
    }
    return '$out RWF';
  }

  static double _km(dynamic lat1, dynamic lng1, dynamic lat2, dynamic lng2) {
    double rad(dynamic d) => (d as num) * math.pi / 180;
    final a = math.pow(math.sin((rad(lat2) - rad(lat1)) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin((rad(lng2) - rad(lng1)) / 2), 2);
    return double.parse((6371 * 2 * math.asin(math.sqrt(a))).toStringAsFixed(1));
  }

  static String isoDayOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A one-page PDF saying what the document is (demo stand-in).
  static Uint8List _pdf(String title) {
    final safe = title.replaceAll(RegExp(r'[()\\]'), '');
    final stream = 'BT /F1 18 Tf 60 760 Td ($safe) Tj 0 -30 Td /F1 12 Tf (Demo document - no real file in demo mode.) Tj ET';
    final objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
      '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = out.length;
    out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
    return Uint8List.fromList(latin1.encode(out.toString()));
  }
}

String jstr(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

int jint(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
