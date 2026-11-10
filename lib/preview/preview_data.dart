// SAMPLE DATA for vendor preview mode. None of this came from the KitchenLink
// backend: it is made up here, in the same JSON shape the backend's vendor
// endpoints return (see KitchenLink-backend/src/utils/serializers.js and
// KitchenLink-frontend/src/demo/), so the app's real models parse it exactly
// as they parse a real response.
//
// The kitchen, people and figures are modelled on the website's own demo
// data (`npm run demo`). Times are relative to "now" so the lists look live.
import 'dart:math' as math;

typedef _Json = Map<String, dynamic>;

const _commission = 10; // percent, like the backend's default

/// The preview "backend": answers GET requests from sample data.
class PreviewData {
  PreviewData(this.now) {
    _build();
  }

  final DateTime now;

  late final _Json _vendor;
  late final List<_Json> _orders;
  late final List<_Json> _menu;
  late final List<_Json> _categories;
  late final List<_Json> _notifications;
  late final List<_Json> _chats;
  late final List<_Json> _tickets;
  late final List<_Json> _withdrawals;
  late final List<_Json> _offers;
  late final _Json _special;
  late final _Json _dashboard;
  late final _Json _wallet;

  String _ago(int minutes) =>
      now.toUtc().subtract(Duration(minutes: minutes)).toIso8601String();
  String _in(int minutes) =>
      now.toUtc().add(Duration(minutes: minutes)).toIso8601String();
  String _day(int daysAhead) {
    final date = now.add(Duration(days: daysAhead));
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // --------------------------------------------------------------- routing

  /// The JSON answering `GET [path]`, or null when preview has nothing there.
  Object? get(String path, Map<String, dynamic> query) {
    final segments = path
        .split('?')
        .first
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    final head = segments.join('/');
    String at(int i) => i < segments.length ? segments[i] : '';

    // Public lists the vendor screens read.
    if (head == 'vendors/types') return {'types': _vendorTypes};
    if (head == 'home/categories') return {'categories': _categories};
    if (head == 'banks') return _banks;
    if (head == 'geo/places/autocomplete') {
      return {'suggestions': _suggestions(query['q']?.toString() ?? '')};
    }
    if (head == 'geo/places/details') return {'place': _places.first};
    if (head == 'geo/places/reverse') {
      return {'area': 'Kimihurura', 'street': 'KG 7 Ave'};
    }

    if (at(0) != 'vendor') return null;
    switch (at(1)) {
      case 'auth':
        return at(2) == 'me' ? {'vendor': _vendor} : null;
      case 'dashboard':
        return _dashboard;
      case 'orders':
        return segments.length == 2 ? _orderPage(query) : _orderById(at(2));
      case 'menu':
        return segments.length == 2 ? _menuPage() : null;
      case 'wallet':
        return _wallet;
      case 'notifications':
        return _notificationPage(query);
      case 'chats':
        if (at(2) == 'unread-count') return {'unread_count': _unread(_chats)};
        return segments.length == 2
            ? {'conversations': _chats.map(_conversation).toList()}
            : _thread(at(2));
      case 'support':
        if (at(2) == 'unread-count') {
          return {
            'unread_count': _tickets.where((t) => t['unread'] == true).length,
          };
        }
        if (segments.length == 2) {
          return {
            'tickets': _tickets.map((t) => {...t}..remove('messages')).toList(),
            'unread_count': _tickets.where((t) => t['unread'] == true).length,
            'categories': ['order', 'delivery', 'payment', 'refund', 'app', 'vendor', 'driver', 'account', 'other'],
          };
        }
        final ticket = _tickets.where((t) => t['id'] == at(2));
        return ticket.isEmpty ? null : {'ticket': ticket.first};
      case 'special':
        return {'special': _special};
      case 'offers':
        return {'offers': _offers};
      case 'ordering':
        return {'ordering': _ordering};
      case 'nationwide':
        return {'nationwide': _nationwide};
      case 'event-package':
        return _eventPackage;
    }
    return null;
  }

  // ---------------------------------------------------------------- orders

  _Json _orderPage(Map<String, dynamic> query) {
    final status = query['status']?.toString();
    final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
    final limit = int.tryParse('${query['limit'] ?? 20}') ?? 20;
    final matching = [
      for (final order in _orders)
        if (status == null || status.isEmpty || order['status'] == status)
          order,
    ];
    final start = math.min((page - 1) * limit, matching.length);
    final end = math.min(start + limit, matching.length);
    return {
      'orders': matching.sublist(start, end),
      'meta': {'page': page, 'limit': limit, 'total': matching.length},
    };
  }

  _Json? _orderById(String id) {
    for (final order in _orders) {
      if (order['id'] == id) return order;
    }
    return null;
  }

  // ------------------------------------------------------------------ menu

  _Json _menuPage() => {
    'items': _menu,
    'meta': {'page': 1, 'limit': _menu.length, 'total': _menu.length},
  };

  // --------------------------------------------------------- notifications

  _Json _notificationPage(Map<String, dynamic> query) {
    final unreadOnly = query['unread']?.toString() == 'true';
    final items = [
      for (final n in _notifications)
        if (!unreadOnly || n['read'] != true) n,
    ];
    return {
      'notifications': items,
      'unread_count': _notifications.where((n) => n['read'] != true).length,
    };
  }

  // ----------------------------------------------------------------- chats

  int _unread(List<_Json> chats) =>
      chats.fold(0, (sum, c) => sum + (c['unread_count'] as int));

  _Json _conversation(_Json chat) {
    final messages = chat['messages'] as List<_Json>;
    final last = messages.last;
    return {
      'id': chat['id'],
      'with': {
        'id': chat['customer_id'],
        'name': chat['customer_name'],
        'avatar_url': '',
      },
      'last_message_preview': last['body'],
      'last_message_at': last['created_at'],
      'last_message_mine': last['mine'],
      'unread_count': chat['unread_count'],
    };
  }

  _Json? _thread(String id) {
    for (final chat in _chats) {
      if (chat['id'] != id) continue;
      return {
        'conversation': _conversation(chat),
        'messages': chat['messages'],
        'has_more': false,
        'privacy_note': 'Sample conversation (preview mode). Phone numbers are never shown to customers.',
      };
    }
    return null;
  }

  // ----------------------------------------------------------------- build

  void _build() {
    _categories = [
      {'id': 'cat-rwandan', 'name': 'Rwandan'},
      {'id': 'cat-grill', 'name': 'Grills'},
      {'id': 'cat-drinks', 'name': 'Drinks'},
      {'id': 'cat-healthy', 'name': 'Healthy'},
      {'id': 'cat-breakfast', 'name': 'Breakfast'},
    ];

    _menu = [
      _dish(
        'm1',
        'Isombe with Rice',
        4500,
        'cat-rwandan',
        'Cassava leaves slow-cooked with peanut paste, served with rice.',
        25,
        popular: true,
        orders: 142,
      ),
      _dish(
        'm2',
        'Beef Brochettes (3)',
        5000,
        'cat-grill',
        'Charcoal-grilled beef skewers with roasted potatoes.',
        20,
        popular: true,
        orders: 188,
        options: [
          _option('Sauce', 'Pili-pili', 0),
          _option('Sauce', 'Garlic', 0),
          _option('Side', 'Extra chips', 1000),
          _option('Side', 'Kachumbari', 500),
        ],
      ),
      _dish(
        'm3',
        'Matoke & Beans',
        3500,
        'cat-rwandan',
        'Steamed green bananas with red beans and avocado.',
        20,
        orders: 96,
      ),
      _dish(
        'm4',
        'Grilled Tilapia',
        9000,
        'cat-grill',
        'Whole Lake Kivu tilapia with chips and kachumbari.',
        30,
        popular: true,
        orders: 121,
      ),
      _dish(
        'm5',
        'Ibihaza Soup',
        2500,
        'cat-rwandan',
        'Creamy pumpkin soup with fresh bread.',
        15,
        orders: 54,
      ),
      _dish(
        'm6',
        'Passion Juice',
        1500,
        'cat-drinks',
        'Fresh passion fruit juice, no added sugar.',
        5,
        orders: 203,
      ),
      _dish(
        'm7',
        'Sunday Pilau',
        6500,
        'cat-rwandan',
        'Spiced rice with slow-cooked beef. Order before 10:00.',
        45,
        preorder: true,
        cutoff: '10:00',
        orders: 33,
      ),
      _dish(
        'm8',
        'Green Smoothie Bowl',
        4000,
        'cat-healthy',
        'Avocado, banana, spinach and granola.',
        10,
        available: false,
        orders: 12,
      ),
    ];

    // name, price, quantity
    (String, int, int) a(String name, int price, int qty) => (name, price, qty);

    _orders = [
      _order(
        'ord-1001',
        'KL-24100',
        'new',
        3,
        'delivery',
        [a('Isombe with Rice', 4500, 2), a('Passion Juice', 1500, 2)],
        customer: 'Diane Uwimana',
        phone: '0788123450',
        address: 'KG 11 Ave, Kacyiru',
        hood: 'Kacyiru',
        note: 'Gate is blue, call on arrival.',
        payment: 'mobile_money',
        fee: 1500,
        km: 2.4,
        today: true,
      ),
      _order(
        'ord-1002',
        'KL-24101',
        'preparing',
        14,
        'delivery',
        [a('Beef Brochettes (3)', 5000, 1), a('Grilled Tilapia', 9000, 1)],
        customer: 'David Mugisha',
        phone: '0788123457',
        address: 'KN 3 Rd, Nyarugenge',
        hood: 'Nyarugenge',
        payment: 'card',
        fee: 2000,
        km: 4.1,
        today: true,
      ),
      _order(
        'ord-1003',
        'KL-24102',
        'ready',
        26,
        'pickup',
        [a('Matoke & Beans', 3500, 1), a('Ibihaza Soup', 2500, 1)],
        customer: 'Grace Ingabire',
        phone: '0788123464',
        payment: 'mobile_money',
        today: true,
      ),
      _order(
        'ord-1004',
        'KL-24103',
        'ready',
        22,
        'delivery',
        [a('Grilled Tilapia', 9000, 1)],
        customer: 'Kevin Habineza',
        phone: '0788123471',
        address: 'KK 15 Rd, Kicukiro',
        hood: 'Kicukiro',
        payment: 'mobile_money',
        fee: 2500,
        km: 6.0,
        today: true,
      ),
      _order(
        'ord-1005',
        'KL-24104',
        'new',
        9,
        'delivery',
        [a('Sunday Pilau', 6500, 3)],
        customer: 'Sandrine Umutoni',
        phone: '0788123478',
        address: 'KG 9 Ave, Remera',
        hood: 'Remera',
        payment: 'mobile_money',
        fee: 1500,
        km: 3.2,
        scheduled: _in(60 * 20),
        special: 'Please pack the rice and the stew separately.',
        today: true,
      ),
      _order(
        'ord-1006',
        'KL-24105',
        'accepted',
        40,
        'delivery',
        [a('Wedding Feast (80 guests)', 12000, 80)],
        customer: 'Olivier Nkurunziza',
        phone: '0788123485',
        address: 'Kigali Convention Centre, Kimihurura',
        hood: 'Kimihurura',
        payment: 'mobile_money',
        fee: 25000,
        km: 9.5,
        scheduled: _in(60 * 24 * 6),
        event: true,
      ),
      _order(
        'ord-1007',
        'KL-24106',
        'completed',
        60 * 5,
        'delivery',
        [a('Beef Brochettes (3)', 5000, 2)],
        customer: 'Ange Mutesi',
        phone: '0788123492',
        address: 'KG 2 Ave, Gisozi',
        hood: 'Gisozi',
        payment: 'mobile_money',
        fee: 1500,
        km: 2.8,
        today: true,
      ),
      _order(
        'ord-1008',
        'KL-24107',
        'completed',
        60 * 26,
        'pickup',
        [a('Isombe with Rice', 4500, 1), a('Beef Brochettes (3)', 5000, 1)],
        customer: 'Yves Ndayisaba',
        phone: '0788123499',
        payment: 'mobile_money',
      ),
      _order(
        'ord-1009',
        'KL-24108',
        'completed',
        60 * 50,
        'delivery',
        [a('Grilled Tilapia', 9000, 1), a('Passion Juice', 1500, 1)],
        customer: 'Josiane Akimana',
        phone: '0788123506',
        address: 'KN 5 Rd, Remera',
        hood: 'Remera',
        payment: 'card',
        fee: 1500,
        km: 3.0,
      ),
      _order(
        'ord-1010',
        'KL-24109',
        'cancelled',
        60 * 30,
        'delivery',
        [a('Matoke & Beans', 3500, 1)],
        customer: 'Thierry Gasana',
        phone: '0788123513',
        address: 'KK 3 Ave, Kicukiro',
        hood: 'Kicukiro',
        payment: 'mobile_money',
        fee: 2000,
        km: 5.2,
        cancelReason: 'Customer changed their mind',
      ),
    ];

    // Dashboard and wallet figures follow from the sample orders above.
    int count(Set<String> statuses) =>
        _orders.where((o) => statuses.contains(o['status'])).length;
    final today = _orders.where((o) => o['_today'] == true).toList();
    final todaySales = today
        .where((o) => o['status'] != 'cancelled')
        .fold<int>(0, (s, o) => s + (o['subtotal_rwf'] as int));
    final deliveredSales = _orders
        .where((o) => o['status'] == 'completed')
        .fold<int>(0, (s, o) => s + (o['subtotal_rwf'] as int));
    final totalSales = 1845000 + deliveredSales;
    final net = (totalSales * (100 - _commission) / 100).round();
    final pending = _orders
        .where(
          (o) => const {
            'new',
            'accepted',
            'preparing',
            'ready',
          }.contains(o['status']),
        )
        .fold<int>(0, (s, o) => s + (o['vendor_payout_rwf'] as int));

    _withdrawals = [
      _withdrawal(
        'wd-1',
        600000,
        'completed',
        'MTN Mobile Money',
        '0788100001',
        'WD-1001',
        60 * 24 * 21,
      ),
      _withdrawal(
        'wd-2',
        400000,
        'completed',
        'Bank of Kigali',
        '00040-0123456-78',
        'WD-1002',
        60 * 24 * 9,
        bank: 'Bank of Kigali',
      ),
      _withdrawal(
        'wd-3',
        150000,
        'processing',
        'MTN Mobile Money',
        '0788100001',
        'WD-1003',
        60 * 3,
      ),
      _withdrawal(
        'wd-4',
        50000,
        'failed',
        'Airtel Money',
        '0733100001',
        'WD-1004',
        60 * 24 * 14,
        failure: 'The mobile money number could not be reached.',
      ),
    ];
    final withdrawn =
        600000 + 400000 + 150000; // failed withdrawals do not count
    final available = net - withdrawn;

    _dashboard = {
      'today_orders': today.length,
      'new_orders': count({'new'}),
      'preparing_orders': count({'accepted', 'preparing'}),
      'ready_orders': count({'ready'}),
      'completed_orders_total': count({'completed'}),
      'completed_orders': today.where((o) => o['status'] == 'completed').length,
      'cancelled_orders': count({'cancelled'}),
      'today_sales_rwf': todaySales,
      'total_sales_rwf': totalSales,
      'commission_percent': _commission,
      'net_earned_rwf': net,
      'available_balance_rwf': available,
      'pending_balance_rwf': pending,
      'withdrawn_rwf': withdrawn,
    };
    _wallet = {
      'total_sales_rwf': totalSales,
      'net_earned_rwf': net,
      'withdrawn_rwf': withdrawn,
      'available_balance_rwf': available,
      'pending_balance_rwf': pending,
      'commission_percent': _commission,
      'payout_phone': '0788100001',
      'payout_name': 'Aline Uwase',
      'withdrawals': _withdrawals,
    };

    _vendor = {
      'id': 'preview-vendor',
      'name': 'Inzu Heritage Kitchen',
      'vendor_type': 'restaurant',
      'vendor_type_label': 'Restaurant',
      'vendor_type_request': null,
      'verification_status': 'approved',
      'is_active': true,
      'is_open': true,
      'owner_name': 'Aline Uwase',
      'phone': '0788100001',
      'email': 'hello@inzukitchen.demo',
      'description': 'Home-style Rwandan classics: isombe, matoke, brochettes and fresh juices.',
      'rating': 4.8,
      'banner_image_url': null,
      'profile_image_url': null,
      'food_category_ids': ['cat-rwandan', 'cat-grill', 'cat-drinks'],
      'food_categories': ['Rwandan', 'Grills', 'Drinks'],
      'operating_hours': [
        for (final day in [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ])
          {
            'day': day,
            'open_time': '08:00',
            'close_time': day == 'sunday' ? '18:00' : '22:00',
            'is_closed': false,
          },
      ],
      'payment_information': {
        'payout_method': 'mobile_money',
        'account_name': 'Aline Uwase',
        'account_number': '',
        'bank_name': '',
        'mobile_money_number': '0788100001',
      },
      'verification_documents': [
        {
          'label': 'Business registration',
          'file_type': 'pdf',
          'uploaded_at': _ago(60 * 24 * 200),
        },
        {
          'label': 'Health certificate',
          'file_type': 'image',
          'uploaded_at': _ago(60 * 24 * 200),
        },
      ],
      'available_balance_rwf': available,
      'total_sales_rwf': totalSales,
      'commission_percent': _commission,
      'location': {
        'address': 'KG 7 Ave, Kimihurura',
        'neighborhood': 'Kimihurura',
        'latitude': -1.9506,
        'longitude': 30.0921,
        'updated_at': _ago(60 * 24 * 30),
      },
      'ordering': _ordering,
      'nationwide': _nationwide,
      'created_at': _ago(60 * 24 * 340),
    };

    _notifications = [
      _note(
        'n1',
        'order_placed',
        'New order KL-24100',
        'Diane Uwimana ordered 2 dishes · 12,000 RWF',
        3,
        orderId: 'ord-1001',
        link: '/vendor-dashboard/orders?order=ord-1001',
      ),
      _note(
        'n2',
        'order_placed',
        'New order KL-24104',
        'Sandrine Umutoni scheduled an order for tomorrow.',
        9,
        orderId: 'ord-1005',
        link: '/vendor-dashboard/orders?order=ord-1005',
      ),
      _note(
        'n3',
        'chat_message',
        'New message from Grace Ingabire',
        'Is my order ready for pickup yet?',
        18,
        link: '/vendor-dashboard/messages?chat=chat-1',
      ),
      _note(
        'n4',
        'payout_update',
        'Withdrawal on its way',
        'Your withdrawal of 150,000 RWF is being processed.',
        60 * 3,
        read: true,
        link: '/vendor-dashboard/wallet',
      ),
      _note(
        'n5',
        'support_message',
        'Support replied',
        'KitchenLink Support answered your request.',
        60 * 20,
        read: true,
        link: '/vendor-dashboard/support?ticket=tkt-1',
      ),
      _note(
        'n6',
        'account_update',
        'Your kitchen is live',
        'Your documents were approved. Customers can now order from you.',
        60 * 24 * 200,
        read: true,
        link: '/vendor-dashboard/profile',
      ),
    ];

    _chats = [
      {
        'id': 'chat-1',
        'customer_id': 'cus-1',
        'customer_name': 'Grace Ingabire',
        'unread_count': 1,
        'messages': [
          _msg('cm1', 'Hello! Is the matoke fresh today?', false, 70),
          _msg('cm2', 'Hello Grace, yes, cooked this morning.', true, 66),
          _msg(
            'cm3',
            'Great, I will pick up my order in 20 minutes.',
            false,
            40,
          ),
          _msg('cm4', 'Is my order ready for pickup yet?', false, 18),
        ],
      },
      {
        'id': 'chat-2',
        'customer_id': 'cus-2',
        'customer_name': 'David Mugisha',
        'unread_count': 0,
        'messages': [
          _msg(
            'cm5',
            'Can I add extra chips to the brochettes?',
            false,
            60 * 2,
          ),
          _msg(
            'cm6',
            'Of course, it is 1,000 RWF extra. I added it to your order.',
            true,
            60 * 2 - 3,
          ),
          _msg('cm7', 'Perfect, thank you!', false, 60 * 2 - 5),
        ],
      },
      {
        'id': 'chat-3',
        'customer_id': 'cus-3',
        'customer_name': 'Olivier Nkurunziza',
        'unread_count': 0,
        'messages': [
          _msg(
            'cm8',
            'We would like to book the wedding package for 80 guests.',
            false,
            60 * 24 * 2,
          ),
          _msg(
            'cm9',
            'Wonderful! Your event order is accepted. The deposit is received.',
            true,
            60 * 24 * 2 - 30,
          ),
        ],
      },
    ];

    _tickets = [
      {
        'id': 'tkt-1',
        'reference': 'SUP-1042',
        'subject': 'Withdrawal still processing',
        'status': 'in_review',
        'status_label': 'Support is on it',
        'category': 'payment',
        'order_id': null,
        'unread': true,
        'message_count': 2,
        'last_message_at': _ago(60 * 20),
        'last_message': {
          'from': 'support',
          'body': 'We are checking with the mobile money provider and will update you today.',
        },
        'messages': [
          {
            'id': 'sm1',
            'body': 'My withdrawal of 150,000 RWF has been processing since this morning.',
            'from': 'you',
            'author_name': 'Aline Uwase',
            'at': _ago(60 * 22),
          },
          {
            'id': 'sm2',
            'body': 'We are checking with the mobile money provider and will update you today.',
            'from': 'support',
            'author_name': 'KitchenLink Support',
            'at': _ago(60 * 20),
          },
        ],
      },
      {
        'id': 'tkt-2',
        'reference': 'SUP-0987',
        'subject': 'How do I add Offer Days?',
        'status': 'resolved',
        'status_label': 'Resolved',
        'category': 'other',
        'order_id': null,
        'unread': false,
        'message_count': 2,
        'last_message_at': _ago(60 * 24 * 12),
        'last_message': {
          'body': 'Open More → Offer days and pick a date up to 60 days ahead.',
        },
        'messages': [
          {
            'id': 'sm3',
            'body': 'How do I add Offer Days?',
            'from': 'you',
            'author_name': 'Aline Uwase',
            'at': _ago(60 * 24 * 12 + 30),
          },
          {
            'id': 'sm4',
            'body':
                'Open More → Offer days and pick a date up to 60 days ahead.',
            'from': 'support',
            'author_name': 'KitchenLink Support',
            'at': _ago(60 * 24 * 12),
          },
        ],
      },
    ];

    _special = {
      'text': 'Sunday pilau with grilled goat, 6,500 RWF. Order before 10:00.',
      'cutoff_at': _in(60 * 14),
      'delivery_at': _in(60 * 20),
      'is_active': true,
      'is_orderable': true,
      'updated_at': _ago(60 * 6),
    };

    _offers = [
      {
        'id': 'off-1',
        'title': 'Brochette Friday',
        'details': 'Buy two brochette plates, get a passion juice free.',
        'offer_date': _day(4),
        'status': 'upcoming',
        'created_at': _ago(60 * 24 * 2),
      },
      {
        'id': 'off-2',
        'title': 'Family lunch Sunday',
        'details': 'Sharing platter for 4 at 20,000 RWF.',
        'offer_date': _day(11),
        'status': 'upcoming',
        'created_at': _ago(60 * 24),
      },
    ];
  }

  // -------------------------------------------------------------- builders

  _Json _dish(
    String id,
    String name,
    int price,
    String categoryId,
    String description,
    int prep, {
    bool popular = false,
    bool available = true,
    bool preorder = false,
    String cutoff = '',
    int orders = 0,
    List<_Json> options = const [],
  }) => {
    'id': id,
    'name': name,
    'category': {
      'id': categoryId,
      'name': _categories.firstWhere((c) => c['id'] == categoryId)['name'],
    },
    'price_rwf': price,
    'preparation_time_minutes': prep,
    'description': description,
    'image_url': null,
    'is_available': available,
    'is_preorder': preorder,
    'preorder_cutoff': cutoff,
    'is_popular': popular,
    'orders_count': orders,
    'options': options,
  };

  _Json _option(String group, String name, int extra) => {
    'id':
        'opt-${group.toLowerCase()}-${name.toLowerCase().replaceAll(' ', '-')}',
    'group_name': group,
    'name': name,
    'additional_price_rwf': extra,
    'is_available': true,
  };

  _Json _order(
    String id,
    String number,
    String status,
    int minutesAgo,
    String fulfillment,
    List<(String, int, int)> lines, {
    required String customer,
    required String phone,
    String address = '',
    String hood = '',
    String note = '',
    String payment = 'mobile_money',
    int fee = 0,
    double? km,
    String? scheduled,
    String special = '',
    bool event = false,
    bool today = false,
    String? cancelReason,
  }) {
    final subtotal = lines.fold<int>(0, (sum, l) => sum + l.$2 * l.$3);
    final commission = (subtotal * _commission / 100).round();
    final isOpen = const {
      'new',
      'accepted',
      'preparing',
      'ready',
    }.contains(status);
    const next = {
      'new': ['accepted', 'cancelled'],
      'accepted': ['preparing', 'cancelled'],
      'preparing': ['ready'],
    };
    final isPickup = fulfillment == 'pickup';
    final deposit = event ? (subtotal * 0.3).round() : 0;
    return {
      '_today':
          today, // helper for the sample dashboard only; the models ignore it
      'id': id,
      'order_number': number,
      'status': status,
      'status_label': const {
        'new': 'New',
        'accepted': 'Accepted',
        'preparing': 'Preparing',
        'ready': 'Ready',
        'completed': 'Completed',
        'cancelled': 'Cancelled',
      }[status],
      'allowed_next_statuses': next[status] ?? <String>[],
      'created_at': _ago(minutesAgo),
      'completed_at': status == 'completed'
          ? _ago(math.max(minutesAgo - 40, 1))
          : null,
      'cancelled_at': status == 'cancelled'
          ? _ago(math.max(minutesAgo - 10, 1))
          : null,
      'cancel_reason': cancelReason,
      'fulfillment': fulfillment,
      'fulfillment_label': isPickup ? 'Pick-up' : 'Delivery',
      'can_confirm_pickup': isPickup && status == 'ready',
      'pickup_attempts_left': 5,
      'collected_at': isPickup && status == 'completed'
          ? _ago(math.max(minutesAgo - 40, 1))
          : null,
      'customer': {'name': customer, 'phone_number': phone},
      'delivery_location': isPickup
          ? <String, dynamic>{}
          : {'address': address, 'neighborhood': hood, 'note': note},
      'delivery_distance_km': km,
      'items': [
        for (final l in lines)
          {
            'name': l.$1,
            'price_rwf': l.$2,
            'quantity': l.$3,
            'subtotal_rwf': l.$2 * l.$3,
            'image_url': null,
            'options': <_Json>[],
          },
      ],
      'subtotal_rwf': subtotal,
      'delivery_fee_rwf': fee,
      'total_amount_rwf': subtotal + fee,
      'commission_percent': _commission,
      'commission_rwf': commission,
      'vendor_payout_rwf': subtotal - commission,
      'settlement_status': status == 'completed' ? 'settled' : 'unpaid',
      'order_type': scheduled == null ? 'immediate' : 'scheduled',
      'order_type_label': scheduled == null ? 'Immediate' : 'Scheduled',
      'scheduled_for': scheduled,
      'special_text': special,
      'payment_status': status == 'cancelled' ? 'refunded' : 'paid',
      'payment_method': payment,
      'eta_minutes': isOpen ? 25 : null,
      'status_history': [
        {'status': 'placed', 'label': 'Order placed', 'at': _ago(minutesAgo)},
        if (status != 'new')
          {
            'status': 'accepted',
            'label': 'Accepted',
            'at': _ago(math.max(minutesAgo - 2, 1)),
          },
        if (status == 'completed')
          {
            'status': 'completed',
            'label': 'Completed',
            'at': _ago(math.max(minutesAgo - 40, 1)),
          },
        if (status == 'cancelled')
          {
            'status': 'cancelled',
            'label': 'Cancelled',
            'at': _ago(math.max(minutesAgo - 10, 1)),
            'note': cancelReason ?? '',
          },
      ],
      if (event)
        'event': {
          'package_name': 'Wedding Feast',
          'guests': lines.first.$3,
          'price_per_plate_rwf': lines.first.$2,
          'menu': [
            'Isombe',
            'Rice',
            'Beef brochettes',
            'Matoke',
            'Fresh juice',
          ],
          'portion': 'Generous plate',
          'service_style_label': 'Buffet',
          'service_details': 'Two servers and chafing dishes included.',
          'delivery_details': 'Arrive by 11:00 to set up.',
        },
      if (event)
        'deposit': {
          'deposit_rwf': deposit,
          'balance_rwf': subtotal + fee - deposit,
          'balance_due_at': _in(60 * 24 * 5),
          'balance_paid_at': null,
          'balance_unpaid': true,
        },
    };
  }

  _Json _withdrawal(
    String id,
    int amount,
    String status,
    String methodLabel,
    String number,
    String reference,
    int minutesAgo, {
    String bank = '',
    String? failure,
  }) => {
    'id': id,
    'amount_rwf': amount,
    'status': status,
    'method': bank.isEmpty ? 'mobile_money' : 'bank',
    'method_label': methodLabel,
    'account_number': number,
    'account_name': 'Aline Uwase',
    'bank_name': bank,
    'reference': reference,
    'failure_reason': failure,
    'processed_at': status == 'completed' ? _ago(minutesAgo - 30) : null,
    'created_at': _ago(minutesAgo),
  };

  _Json _note(
    String id,
    String type,
    String title,
    String body,
    int minutesAgo, {
    bool read = false,
    String? orderId,
    String? link,
  }) => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'order_id': orderId,
    'data': {'link': ?link},
    'read': read,
    'created_at': _ago(minutesAgo),
  };

  _Json _msg(String id, String body, bool mine, int minutesAgo) => {
    'id': id,
    'body': body,
    'mine': mine,
    'author_role': mine ? 'vendor' : 'customer',
    'created_at': _ago(minutesAgo),
  };

  // ------------------------------------------------------- static fixtures

  static const _Json _ordering = {
    'vendor_type': 'restaurant',
    'vendor_type_label': 'Restaurant',
    'order_now': true,
    'min_lead_minutes': 0,
    'max_days_ahead': 7,
    'daily_order_limit': null,
    'min_order_rwf': 0,
    'max_items_per_order': null,
    'limit_range': [5, 500],
    'min_order_range': [0, 50000],
    'orders_today': 6,
    'fully_booked_today': false,
  };

  static const _Json _nationwide = {
    'enabled': true,
    'source': 'type',
    'by_type': false,
    'travel_base_fee_rwf': 5000,
    'travel_per_km_rwf': 400,
    'platform_delivery_max_km': 15,
    'ranges': {
      'base_fee_rwf': [0, 100000],
      'per_km_rwf': [0, 5000],
    },
  };

  static const _Json _eventPackage = {
    'event_package': {
      'enabled': true,
      'delivery_details':
          'We deliver, set up and serve at your venue anywhere in Kigali.',
      'delivery_fee_ranges': [
        {'from_km': 0, 'to_km': 10, 'fee_rwf': 15000},
        {'from_km': 10, 'to_km': 30, 'fee_rwf': 35000},
        {'from_km': 30, 'to_km': null, 'fee_rwf': 60000},
      ],
      'packages': [
        {
          'id': 'pkg-1',
          'name': 'Wedding Feast',
          'description': 'A full Rwandan buffet for your guests.',
          'enabled': true,
          'tiers': [
            {'min_guests': 30, 'max_guests': 79, 'price_per_plate_rwf': 13500},
            {'min_guests': 80, 'max_guests': 200, 'price_per_plate_rwf': 12000},
          ],
          'menu': [
            'Isombe',
            'Rice',
            'Beef brochettes',
            'Matoke',
            'Fresh juice',
          ],
          'portion': 'Generous plate',
          'service_style': 'buffet',
          'service_details': 'Two servers and chafing dishes included.',
        },
        {
          'id': 'pkg-2',
          'name': 'Office Lunch',
          'description': 'Boxed lunches for meetings and trainings.',
          'enabled': true,
          'tiers': [
            {'min_guests': 10, 'max_guests': 100, 'price_per_plate_rwf': 5500},
          ],
          'menu': ['Rice', 'Beans', 'Chicken stew', 'Salad'],
          'portion': 'Standard',
          'service_style': 'boxed',
          'service_details': '',
        },
      ],
    },
    'options': {
      'service_styles': [
        {'code': 'buffet', 'label': 'Buffet'},
        {'code': 'plated', 'label': 'Plated'},
        {'code': 'boxed', 'label': 'Boxed meals'},
      ],
      'limits': {
        'guests': [1, 100000],
        'plate_rwf': [100, 1000000],
        'delivery_fee_rwf': [0, 1000000],
        'delivery_km': 500,
        'packages': 10,
        'tiers': 10,
        'menu_items': 30,
      },
    },
  };

  static const List<_Json> _vendorTypes = [
    {
      'code': 'home_cook',
      'label': 'Home Cook',
      'description': 'Home-made meals cooked in a family kitchen.',
      'strengths': ['Order ahead', 'Daily limit'],
      'note': '',
    },
    {
      'code': 'restaurant',
      'label': 'Restaurant',
      'description': 'A sit-down or takeaway restaurant with a full menu.',
      'strengths': ['Order now', 'Full menu'],
      'note': '',
    },
    {
      'code': 'cafe',
      'label': 'Café',
      'description': 'Coffee, tea, light meals and snacks.',
      'strengths': [],
      'note': '',
    },
    {
      'code': 'bakery',
      'label': 'Bakery',
      'description': 'Bread, cakes, pastries and baked goods.',
      'strengths': [],
      'note': '',
    },
    {
      'code': 'caterer',
      'label': 'Caterer',
      'description': 'Food for events, offices and large groups.',
      'strengths': ['Big events', 'Nationwide'],
      'note': '',
    },
    {
      'code': 'food_truck',
      'label': 'Food Truck',
      'description': 'Street food from a mobile kitchen.',
      'strengths': [],
      'note': '',
    },
    {
      'code': 'chef',
      'label': 'Chef',
      'description': 'A professional chef cooking signature dishes.',
      'strengths': [],
      'note': '',
    },
    {
      'code': 'meal_prep',
      'label': 'Meal Prep',
      'description': 'Ready-made meals prepared in advance for the week.',
      'strengths': [],
      'note': '',
    },
    {
      'code': 'juice_drinks',
      'label': 'Juice & Drinks',
      'description': 'Fresh juices, smoothies and other drinks.',
      'strengths': [],
      'note': '',
    },
  ];

  static const _Json _banks = {
    'banks': [
      {'name': 'Bank of Kigali', 'min': 14, 'max': 14, 'exact': true},
      {'name': 'I&M Bank', 'min': 11, 'max': 11, 'exact': true},
      {'name': 'Equity Bank', 'min': 10, 'max': 13, 'exact': false},
    ],
    'general': {'min': 6, 'max': 30},
  };

  static const List<_Json> _places = [
    {
      'id': 'place-1',
      'name': 'Kimihurura',
      'secondary': 'Gasabo, Kigali',
      'kind': 'area',
      'lat': -1.9506,
      'lng': 30.0921,
    },
    {
      'id': 'place-2',
      'name': 'Kigali Convention Centre',
      'secondary': 'KG 2 Roundabout, Kimihurura',
      'kind': 'landmark',
      'lat': -1.9537,
      'lng': 30.0927,
    },
    {
      'id': 'place-3',
      'name': 'Remera',
      'secondary': 'Gasabo, Kigali',
      'kind': 'area',
      'lat': -1.9573,
      'lng': 30.1127,
    },
  ];

  List<_Json> _suggestions(String q) {
    final text = q.trim().toLowerCase();
    return [
      for (final place in _places)
        if (text.isEmpty ||
            (place['name'] as String).toLowerCase().contains(text))
          place,
    ];
  }
}
