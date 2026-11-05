import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/app/app.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_client.dart';
import 'package:kitchenlink_mobile/core/network/api_exception.dart';
import 'package:kitchenlink_mobile/core/providers.dart';
import 'package:kitchenlink_mobile/core/storage/token_store.dart';
import 'package:kitchenlink_mobile/features/auth/application/session.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.route);
  final ResponseBody Function(RequestOptions) route;
  final List<RequestOptions> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    log.add(options);
    return route(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});

Map<String, dynamic> _vendor({String status = 'approved'}) => {
      'id': 'v1', 'name': 'Keza Kitchen', 'vendor_type': 'home_cook', 'vendor_type_label': 'Home Cook',
      'verification_status': status, 'is_open': true, 'phone': '+250788111222',
    };

({ProviderContainer container, _Adapter adapter, MemoryTokenStore store}) _setup(
  ResponseBody Function(RequestOptions) route, {
  String? token,
}) {
  final adapter = _Adapter(route);
  final store = MemoryTokenStore(token);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  final container = ProviderContainer(overrides: [
    tokenStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWith((ref) => ApiClient(config: const AppConfig(apiBaseUrl: 'http://test/api/v1'), dio: dio)),
  ]);
  addTearDown(container.dispose);
  return (container: container, adapter: adapter, store: store);
}

/// Waits until the session has left the "restoring" state (or 3 seconds pass).
Future<void> _settle(ProviderContainer container) async {
  for (var i = 0; i < 120; i++) {
    if (container.read(sessionProvider).status != SessionStatus.restoring) break;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  test('with no stored token the vendor is signed out', () async {
    final s = _setup((_) => _json(200, {}));
    s.container.read(sessionProvider);
    await _settle(s.container);
    expect(s.container.read(sessionProvider).status, SessionStatus.unauthenticated);
    expect(s.adapter.log, isEmpty);
  });

  test('a stored token restores the session through /vendor/auth/me', () async {
    final s = _setup((o) => _json(200, {'vendor': _vendor()}), token: 'abc');
    s.container.read(sessionProvider);
    await _settle(s.container);
    final state = s.container.read(sessionProvider);
    expect(state.status, SessionStatus.authenticated);
    expect(state.vendor!.name, 'Keza Kitchen');
    expect(s.adapter.log.single.path, '/vendor/auth/me');
    expect(s.adapter.log.single.headers['Authorization'], 'Bearer abc');
  });

  test('an expired stored token signs the vendor out and clears it', () async {
    final s = _setup((_) => _json(401, {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}}), token: 'old');
    s.container.read(sessionProvider);
    await _settle(s.container);
    expect(s.container.read(sessionProvider).status, SessionStatus.unauthenticated);
    expect(await s.store.read(), isNull);
  });

  test('no network at launch keeps the token and shows the connection screen', () async {
    final s = _setup((o) => throw DioException.connectionError(requestOptions: o, reason: 'down'), token: 'keep');
    s.container.read(sessionProvider);
    await _settle(s.container);
    expect(s.container.read(sessionProvider).status, SessionStatus.unreachable);
    expect(await s.store.read(), 'keep');
  });

  test('verifying the OTP stores the vendor token securely and opens the session', () async {
    final s = _setup((o) => o.path.endsWith('verify-otp') ? _json(200, {'token': 'new-token', 'vendor': _vendor()}) : _json(200, {}));
    final notifier = s.container.read(sessionProvider.notifier);
    await _settle(s.container);
    await notifier.verifyOtp('0788111222', '123456');
    expect(s.container.read(sessionProvider).isAuthenticated, isTrue);
    expect(await s.store.read(), 'new-token');
    final sent = s.adapter.log.firstWhere((o) => o.path.endsWith('verify-otp'));
    expect(sent.data, {'phone': '0788111222', 'code': '123456'});
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('a wrong code leaves the vendor signed out and shows the backend message', () async {
    final s = _setup((_) => _json(400, {'error': {'code': 'OTP_INVALID', 'message': 'Incorrect code. 4 tries left.'}}));
    final notifier = s.container.read(sessionProvider.notifier);
    await _settle(s.container);
    await expectLater(
      notifier.verifyOtp('0788111222', '000000'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Incorrect code. 4 tries left.')),
    );
    expect(s.container.read(sessionProvider).status, SessionStatus.unauthenticated);
    expect(await s.store.read(), isNull);
  });

  test('a suspended vendor sees the backend reason and support contacts', () async {
    final s = _setup((_) => _json(403, {
          'error': {
            'code': 'VENDOR_SUSPENDED', 'message': 'Your vendor account has been suspended.',
            'details': {'status': 'suspended', 'reason': 'Hygiene complaint', 'support_phone': '+250788000000', 'support_email': 'help@kitchenlink.rw'},
          },
        }));
    final notifier = s.container.read(sessionProvider.notifier);
    await _settle(s.container);
    await expectLater(notifier.verifyOtp('0788111222', '123456'), throwsA(isA<ApiException>()));
    final state = s.container.read(sessionProvider);
    expect(state.status, SessionStatus.blocked);
    expect(state.block!.reason, 'Hygiene complaint');
    expect(state.block!.supportPhone, '+250788000000');
  });

  test('a rejected token mid-session signs out, but a 500 does not', () async {
    var fail = 500;
    final s = _setup((o) => o.path.endsWith('/me') && fail == 0
        ? _json(200, {'vendor': _vendor()})
        : _json(fail == 0 ? 200 : fail, {'error': {'code': fail == 401 ? 'SESSION_REVOKED' : 'INTERNAL_ERROR', 'message': 'x'}}),
        token: 't');
    s.container.read(sessionProvider);
    await _settle(s.container);
    fail = 0;
    await s.container.read(sessionProvider.notifier).restore();
    expect(s.container.read(sessionProvider).isAuthenticated, isTrue);

    fail = 500;
    await s.container.read(sessionProvider.notifier).refreshVendor();
    expect(s.container.read(sessionProvider).isAuthenticated, isTrue, reason: 'an ordinary failure must not log out');

    fail = 401;
    await s.container.read(sessionProvider.notifier).refreshVendor();
    await _settle(s.container);
    expect(s.container.read(sessionProvider).status, SessionStatus.unauthenticated);
    expect(await s.store.read(), isNull);
  });

  test('logging out clears the token even if the server cannot be reached', () async {
    var down = false;
    final s = _setup((o) {
      if (down) throw DioException.connectionError(requestOptions: o, reason: 'down');
      return _json(200, {'vendor': _vendor()});
    }, token: 't');
    s.container.read(sessionProvider);
    await _settle(s.container);
    down = true;
    await s.container.read(sessionProvider.notifier).logout();
    expect(s.container.read(sessionProvider).status, SessionStatus.unauthenticated);
    expect(await s.store.read(), isNull);
  });

  test('pending vendors are not approved (restricted actions stay locked)', () async {
    final s = _setup((_) => _json(200, {'vendor': _vendor(status: 'pending')}), token: 't');
    s.container.read(sessionProvider);
    await _settle(s.container);
    expect(s.container.read(canActProvider), isFalse);
  });

  testWidgets('the app opens on the sign-in screen when signed out', (tester) async {
    final s = _setup((_) => _json(200, {}));
    await tester.pumpWidget(UncontrolledProviderScope(container: s.container, child: const KitchenLinkApp()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    // An invalid number is refused before any request is made.
    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.textContaining('valid Rwandan number'), findsOneWidget);
    expect(s.adapter.log, isEmpty);
  });
}
