import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/features/auth/models/registration.dart';
import 'package:kitchenlink_mobile/features/auth/models/vendor_account.dart';
import 'package:kitchenlink_mobile/features/dashboard/models/dashboard_stats.dart';
import 'package:kitchenlink_mobile/features/menu/models/menu.dart';
import 'package:kitchenlink_mobile/features/notifications/models/app_notification.dart';
import 'package:kitchenlink_mobile/features/orders/application/orders_providers.dart';
import 'package:kitchenlink_mobile/features/orders/models/order.dart';
import 'package:kitchenlink_mobile/features/orders/models/order_actions.dart';
import 'package:kitchenlink_mobile/features/settings/models/event_package.dart';
import 'package:kitchenlink_mobile/features/wallet/models/wallet.dart';

Map<String, dynamic> orderJson({
  String status = 'new',
  List<String> allowed = const ['accepted', 'cancelled'],
  String fulfillment = 'delivery',
  String payment = 'paid',
  Map<String, dynamic>? extra,
}) =>
    {
      'id': 'o1',
      'order_number': 'OFK-1001',
      'status': status,
      'status_label': 'New order',
      'allowed_next_statuses': allowed,
      'fulfillment': fulfillment,
      'payment_status': payment,
      'payment_method': 'mobile_money',
      'customer': {'id': 'c1', 'name': 'Alice', 'phone_number': '+250788000111'},
      'items': [
        {'name': 'Isombe', 'price_rwf': 3000, 'quantity': 2, 'subtotal_rwf': 6000, 'options': [
          {'group_name': 'Size', 'name': 'Large', 'additional_price_rwf': 500},
        ]},
      ],
      'subtotal_rwf': 6000,
      'delivery_fee_rwf': 1000,
      'total_amount_rwf': 7000,
      'created_at': '2026-11-04T10:00:00Z',
      ...?extra,
    };

void main() {
  group('order parsing', () {
    test('reads the kitchen order shape', () {
      final order = VendorOrder.fromJson(orderJson());
      expect(order.orderNumber, 'OFK-1001');
      expect(order.status, OrderStatus.newOrder);
      expect(order.totalRwf, 7000);
      expect(order.items.single.options.single.additionalPriceRwf, 500);
      expect(order.customer.phone, '+250788000111');
      expect(order.allowedNextStatuses, [OrderStatus.accepted, OrderStatus.cancelled]);
    });
    test('unpaid orders are recognised', () {
      expect(VendorOrder.fromJson(orderJson(payment: 'pending')).awaitingPayment, isTrue);
    });
  });

  group('order actions (the backend decides)', () {
    test('a paid new order can be accepted or rejected', () {
      final actions = orderActionsFor(VendorOrder.fromJson(orderJson()));
      expect(actions.map((a) => a.label), ['Accept order', 'Reject order']);
    });
    test('an unpaid new order offers only reject (server allows only cancel)', () {
      final order = VendorOrder.fromJson(orderJson(payment: 'pending', allowed: const ['cancelled']));
      final actions = orderActionsFor(order);
      expect(actions.single.kind, OrderActionKind.cancel);
      expect(orderBlockerNote(order), contains("hasn't paid"));
    });
    test('never offers "complete", even if it were in the list', () {
      final order = VendorOrder.fromJson(orderJson(status: 'preparing', allowed: const ['ready', 'completed', 'cancelled']));
      final statuses = orderActionsFor(order).map((a) => a.status);
      expect(statuses, isNot(contains(OrderStatus.completed)));
      expect(statuses, contains(OrderStatus.ready));
    });
    test('a delivery order that is ready has no hand-over code action', () {
      final order = VendorOrder.fromJson(orderJson(status: 'ready', allowed: const ['cancelled']));
      expect(orderActionsFor(order).any((a) => a.kind == OrderActionKind.handover), isFalse);
    });
    test('a ready pickup order offers the code action only when the server allows it', () {
      final ok = VendorOrder.fromJson(orderJson(status: 'ready', allowed: const ['cancelled'], fulfillment: 'pickup', extra: {'can_confirm_pickup': true, 'pickup_attempts_left': 3}));
      expect(orderActionsFor(ok).firstWhere((a) => a.kind == OrderActionKind.handover).enabled, isTrue);
      final locked = VendorOrder.fromJson(orderJson(status: 'ready', allowed: const ['cancelled'], fulfillment: 'pickup', extra: {'can_confirm_pickup': false, 'pickup_attempts_left': 0}));
      final action = orderActionsFor(locked).firstWhere((a) => a.kind == OrderActionKind.handover);
      expect(action.enabled, isFalse);
      expect(action.disabledReason, contains('Too many wrong codes'));
    });
    test('a scheduled order cannot be marked ready before ready_available_at', () {
      final soon = DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String();
      final order = VendorOrder.fromJson(orderJson(status: 'preparing', allowed: const ['cancelled'], extra: {'ready_available_at': soon, 'order_type': 'scheduled'}));
      final ready = orderActionsFor(order).firstWhere((a) => a.status == OrderStatus.ready);
      expect(ready.enabled, isFalse);
    });
    test('an unpaid event balance blocks hand-over', () {
      final order = VendorOrder.fromJson(orderJson(status: 'ready', allowed: const ['cancelled'], fulfillment: 'pickup', extra: {
        'can_confirm_pickup': false,
        'pickup_attempts_left': 3,
        'deposit': {'deposit_rwf': 1, 'balance_rwf': 1, 'balance_unpaid': true},
      }));
      final action = orderActionsFor(order).firstWhere((a) => a.kind == OrderActionKind.handover);
      expect(action.enabled, isFalse);
      expect(action.disabledReason, contains('balance'));
    });
    test('finished orders have no actions', () {
      expect(orderActionsFor(VendorOrder.fromJson(orderJson(status: 'completed', allowed: const []))), isEmpty);
    });
  });

  test('merging a fresh first page keeps older pages and drops orders that changed status', () {
    VendorOrder at(String id, String created) =>
        VendorOrder.fromJson(orderJson(extra: {'id': id, 'created_at': created}));
    final previous = [
      at('moved', '2026-11-04T12:30:00Z'), // inside the fresh window but gone from it: changed status
      at('new1', '2026-11-04T12:00:00Z'),
      at('mid', '2026-11-04T11:00:00Z'), // older than the first page: a later page, kept
      at('old', '2026-11-04T09:00:00Z'),
    ];
    final fresh = [at('newer', '2026-11-04T13:00:00Z'), at('new1', '2026-11-04T12:00:00Z')];
    final merged = mergeOrders(previous, fresh).map((o) => o.id).toList();
    expect(merged, ['newer', 'new1', 'mid', 'old']);
  });

  test('menu form sends the exact multipart fields the backend parses', () {
    const draft = MenuItemDraft(
      name: ' Brochettes ',
      priceRwf: 5000,
      preparationMinutes: 18,
      categoryId: 'cat1',
      isPreorder: true,
      preorderCutoff: 'Before 6pm',
      options: [MenuOption(groupName: 'Heat', name: 'Hot', additionalPriceRwf: 300)],
    );
    final fields = draft.toFields();
    expect(fields['name'], 'Brochettes');
    expect(fields['price_rwf'], '5000');
    expect(fields['preparation_time_minutes'], '18');
    expect(fields['is_preorder'], 'true');
    expect(fields['category_id'], 'cat1');
    expect(jsonDecode(fields['options']!), [
      {'group_name': 'Heat', 'name': 'Hot', 'additional_price_rwf': 300},
    ]);
    expect(fields.containsKey('image_clear'), isFalse);
    expect(const MenuItemDraft(name: 'x', priceRwf: 1, clearImage: true).toFields()['image_clear'], 'true');
    expect(const MenuItemDraft(name: 'x', priceRwf: 1, preorderCutoff: 'stale').toFields()['preorder_cutoff'], '');
  });

  group('withdrawal payloads', () {
    test('mobile money sends the method label and a local phone', () {
      final json = const WithdrawalRequest(amountRwf: 20000, method: PayoutMethod.mtn, phone: '+250788123456').toJson();
      expect(json, {'amount_rwf': 20000, 'method': 'MTN Mobile Money', 'phone': '0788123456'});
    });
    test('bank transfer sends bank details only', () {
      final json = const WithdrawalRequest(
        amountRwf: 50000,
        method: PayoutMethod.bank,
        bankName: 'Bank of Kigali',
        accountName: 'Keza',
        accountNumber: '00094-0651934-37',
      ).toJson();
      expect(json['method'], 'Bank Transfer');
      expect(json['account_number'], '00094065193437');
      expect(json.containsKey('phone'), isFalse);
    });
    test('bank account length follows the bank rule', () {
      const bank = BankInfo(name: 'Bank of Kigali', min: 14, max: 14, exact: true);
      expect(bank.validateAccountNumber('12345678901234'), isNull);
      expect(bank.validateAccountNumber('123'), contains('14 digits'));
    });
  });

  group('big-event validation mirrors the backend', () {
    const limits = EventLimits();
    test('guest ranges may not overlap', () {
      final error = EventPackageValidator.tiers(const [
        GuestTier(minGuests: 10, maxGuests: 50, pricePerPlateRwf: 5000),
        GuestTier(minGuests: 50, maxGuests: 100, pricePerPlateRwf: 4500),
      ], limits, 'Wedding');
      expect(error, contains('overlap'));
    });
    test('delivery fees start at 0 km, have no gaps and end open', () {
      expect(EventPackageValidator.feeRanges(const [FeeRange(fromKm: 0, toKm: 5, feeRwf: 2000), FeeRange(fromKm: 5, feeRwf: 4000)], limits), isNull);
      expect(EventPackageValidator.feeRanges(const [FeeRange(fromKm: 1, feeRwf: 2000)], limits), contains('0 km'));
      expect(EventPackageValidator.feeRanges(const [FeeRange(fromKm: 0, toKm: 5, feeRwf: 2000), FeeRange(fromKm: 6, feeRwf: 4000)], limits), contains('Gap'));
      expect(EventPackageValidator.feeRanges(const [FeeRange(fromKm: 0, toKm: 5, feeRwf: 2000)], limits), contains('no end'));
    });
    test('big events cannot be switched on without a package and delivery fees', () {
      const settings = EventPackageSettings(enabled: true);
      expect(EventPackageValidator.settings(settings), isNotNull);
    });
  });

  group('notification targets', () {
    AppNotification n(String type, {String? link, String? orderId}) =>
        AppNotification(id: '1', type: type, title: 't', body: 'b', link: link, orderId: orderId);
    test('website links map to app routes', () {
      expect(notificationRoute(n('order_placed', link: '/vendor-dashboard/orders?order=abc')), '/orders/abc');
      expect(notificationRoute(n('chat_message', link: '/vendor-dashboard/messages?chat=c1')), '/messages/c1');
      expect(notificationRoute(n('support_message', link: '/vendor-dashboard/support?ticket=t1')), '/support/t1');
      expect(notificationRoute(n('payout_update', link: '/vendor-dashboard/wallet')), '/wallet');
    });
    test('old notifications fall back to their type', () {
      expect(notificationRoute(n('payout_update')), '/wallet');
      expect(notificationRoute(n('order_update', orderId: 'x')), '/orders/x');
      expect(notificationRoute(n('general')), isNull);
    });
  });

  group('registration payload', () {
    test('JSON parts are strings and payouts use the registered phone', () {
      const data = RegistrationData(
        name: 'Keza Kitchen',
        ownerName: 'Keza M',
        vendorType: 'home_cook',
        phone: '+250 788 111 222',
        description: 'Home-style Rwandan meals.',
        address: 'KG 11 Ave',
        neighborhood: 'Kimironko',
        latitude: -1.9441,
        longitude: 30.0619,
        foodCategoryIds: ['c1'],
        operatingHours: [OperatingHour(day: 'monday')],
        payment: PaymentInformation(payoutMethod: 'mobile_money', accountName: 'Keza'),
        documents: [],
      );
      final fields = data.toFields();
      expect(fields['phone'], '0788111222');
      expect(jsonDecode(fields['location']!)['latitude'], -1.9441);
      expect(jsonDecode(fields['payment_information']!)['mobile_money_number'], '0788111222');
      expect(jsonDecode(fields['food_categories']!), ['c1']);
      expect(fields.containsKey('email'), isFalse);
      expect(data.validateFiles(), contains('verification document'));
    });
  });

  test('vendor account and dashboard parse backend numbers as given', () {
    final vendor = VendorAccount.fromJson({
      'id': 'v1', 'name': 'Keza', 'vendor_type': 'home_cook', 'vendor_type_label': 'Home Cook',
      'verification_status': 'pending', 'is_open': false,
      'ordering': {'vendor_type': 'home_cook', 'daily_order_limit': 20, 'limit_range': [1, 60], 'min_order_range': [0, 20000]},
      'location': {'latitude': -1.9, 'longitude': 30.0, 'address': 'KG 11'},
    });
    expect(vendor.isPending, isTrue);
    expect(vendor.isApproved, isFalse);
    expect(vendor.ordering!.hasDailyLimit, isTrue);
    expect(vendor.location.hasCoordinates, isTrue);

    final stats = DashboardStats.fromJson({'new_orders': 3, 'today_sales_rwf': '145000', 'commission_percent': 15, 'net_earned_rwf': 99});
    expect(stats.newOrders, 3);
    expect(stats.todaySalesRwf, 145000);
    expect(stats.commissionPercent, 15);
  });

  test('a suspended account carries the backend reason and support contacts', () {
    final block = AccountBlock.fromError(
      code: 'VENDOR_SUSPENDED',
      message: 'suspended',
      details: {'reason': 'Hygiene check failed', 'support_phone': '+250788000000', 'support_email': 'help@kitchenlink.rw'},
    );
    expect(block.isSuspended, isTrue);
    expect(block.reason, 'Hygiene check failed');
    expect(block.supportEmail, 'help@kitchenlink.rw');
  });
}
