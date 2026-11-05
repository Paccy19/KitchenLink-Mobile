import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenlink_mobile/core/config/app_config.dart';
import 'package:kitchenlink_mobile/core/network/api_client.dart';
import 'package:kitchenlink_mobile/core/network/api_exception.dart';

/// Answers every request with a prepared response and records what was sent.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );

ApiClient clientWith(FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  return ApiClient(config: const AppConfig(apiBaseUrl: 'http://test/api/v1'), dio: dio);
}

void main() {
  test('sends the vendor bearer token only on authenticated calls', () async {
    final adapter = FakeAdapter((_) => json(200, {'ok': true}));
    final client = clientWith(adapter)..setToken('vendor-token');
    await client.get('/vendor/dashboard');
    await client.post('/vendor/auth/send-otp', data: {'phone': '0788123456'}, auth: false);
    expect(adapter.requests[0].headers['Authorization'], 'Bearer vendor-token');
    expect(adapter.requests[1].headers.containsKey('Authorization'), isFalse);
  });

  test('parses the backend error shape', () async {
    final adapter = FakeAdapter((_) => json(409, {
          'error': {'code': 'PAYMENT_PENDING', 'message': "The customer hasn't paid yet.", 'details': {'x': 'y'}},
        }));
    final client = clientWith(adapter)..setToken('t');
    expect(
      client.patch('/vendor/orders/1/status', data: {'status': 'accepted'}),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'PAYMENT_PENDING')
          .having((e) => e.message, 'message', "The customer hasn't paid yet.")
          .having((e) => e.kind, 'kind', ApiErrorKind.conflict)),
    );
  });

  test('a 401 on a signed-in request reports the session as invalid', () async {
    final adapter = FakeAdapter((_) => json(401, {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}}));
    final client = clientWith(adapter)..setToken('old');
    var invalid = 0;
    client.onSessionInvalid = () => invalid++;
    await expectLater(client.get('/vendor/auth/me'), throwsA(isA<ApiException>()));
    expect(invalid, 1);
  });

  test('an ordinary failure (500) never ends the session', () async {
    final adapter = FakeAdapter((_) => json(500, {'error': {'code': 'INTERNAL_ERROR', 'message': 'Something went wrong.'}}));
    final client = clientWith(adapter)..setToken('t');
    var invalid = 0;
    client.onSessionInvalid = () => invalid++;
    await expectLater(client.get('/vendor/dashboard'), throwsA(isA<ApiException>()));
    expect(invalid, 0);
  });

  test('a 401 on a public call (wrong code) does not end a session', () async {
    final adapter = FakeAdapter((_) => json(401, {'error': {'message': 'No.'}}));
    final client = clientWith(adapter)..setToken('t');
    var invalid = 0;
    client.onSessionInvalid = () => invalid++;
    await expectLater(client.post('/vendor/auth/verify-otp', auth: false), throwsA(isA<ApiException>()));
    expect(invalid, 0);
  });

  test('suspended and pending-review refusals are reported separately', () async {
    var response = 'VENDOR_SUSPENDED';
    final adapter = FakeAdapter((_) => json(403, {'error': {'code': response, 'message': 'no', 'details': {'reason': 'Fraud'}}}));
    final client = clientWith(adapter)..setToken('t');
    ApiException? blocked;
    ApiException? pending;
    client.onAccountBlocked = (e) => blocked = e;
    client.onPendingReview = (e) => pending = e;
    await expectLater(client.get('/vendor/dashboard'), throwsA(isA<ApiException>()));
    response = 'VENDOR_PENDING_REVIEW';
    await expectLater(client.patch('/vendor/availability', data: {}), throwsA(isA<ApiException>()));
    expect(blocked?.details['reason'], 'Fraud');
    expect(pending?.isPendingReview, isTrue);
  });

  test('a connection failure becomes an offline error and is reported', () async {
    final adapter = FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'down'));
    final client = clientWith(adapter);
    bool? online;
    client.onConnectivity = (value) => online = value;
    await expectLater(client.get('/x'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
    expect(online, isFalse);
  });
}
