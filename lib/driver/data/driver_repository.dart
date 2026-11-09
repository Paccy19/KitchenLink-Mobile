import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../../core/utils/uploads.dart';
import '../models/delivery.dart';
import '../models/driver_account.dart';
import '../models/driver_notification.dart';
import '../models/navigation.dart';

/// Every `/driver/*` endpoint, one for one with the website's
/// `src/api/driverApi.js` (same paths, bodies and query parameters).
class DriverRepository {
  const DriverRepository(this._api);
  final ApiClient _api;

  /* ---------------------------------- auth --------------------------------- */

  Future<DriverOtpChallenge> sendOtp(String phone) async => DriverOtpChallenge.fromJson(
        asJson(await _api.post('/driver/auth/send-otp', data: {'phone': phone}, auth: false)),
      );

  Future<({String token, DriverAccount driver})> verifyOtp(String phone, String code) async {
    final json = asJson(await _api.post(
      '/driver/auth/verify-otp',
      data: {'phone': phone, 'code': code},
      auth: false,
    ));
    return (token: str(json['token']), driver: DriverAccount.fromJson(asJson(json['driver'])));
  }

  Future<DriverAccount> register(DriverRegistration registration) async => DriverAccount.fromJson(
        asJson(asJson(await _api.post('/driver/auth/register', data: registration.toJson(), auth: false))['driver']),
      );

  Future<DriverAccount> me() async =>
      DriverAccount.fromJson(asJson(asJson(await _api.get('/driver/auth/me'))['driver']));

  Future<void> logout() async => _api.post('/driver/auth/logout');

  Future<void> logoutAll() async => _api.post('/driver/auth/logout-all');

  /* -------------------------------- profile -------------------------------- */

  /// Changes the given fields only. `email: ''` removes the email.
  Future<DriverAccount> updateProfile({
    String? name,
    String? email,
    VehicleType? vehicleType,
    String? plateNumber,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (email != null) 'email': email.trim().isEmpty ? null : email.trim(),
      if (vehicleType != null) 'vehicle_type': vehicleType.apiValue,
      if (plateNumber != null) 'plate_number': plateNumber.trim().toUpperCase(),
    };
    return DriverAccount.fromJson(asJson(asJson(await _api.patch('/driver/profile', data: body))['driver']));
  }

  /// A new profile picture, sent as a real file (`profile_image`).
  Future<DriverAccount> uploadProfilePhoto(PickedUpload photo) async {
    final form = FormData.fromMap({'profile_image': await photo.toMultipart()});
    return DriverAccount.fromJson(asJson(asJson(await _api.multipart('PATCH', '/driver/profile', form))['driver']));
  }

  /* ------------------------------ availability ----------------------------- */

  /// Going offline hands any active delivery back to other workers.
  Future<({DriverAccount driver, int reassigned})> setAvailability({required bool online}) async {
    final json = asJson(await _api.patch('/driver/availability', data: {'is_online': online}));
    return (driver: DriverAccount.fromJson(asJson(json['driver'])), reassigned: intOf(json['reassigned_deliveries']));
  }

  /// heading (degrees), speed and accuracy are optional GPS extras.
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    double? heading,
    double? speedMps,
    double? accuracyM,
  }) async =>
      _api.patch('/driver/location', data: {
        'latitude': latitude,
        'longitude': longitude,
        'heading': ?heading,
        'speed_mps': ?speedMps,
        if (accuracyM != null) 'accuracy_m': accuracyM.round(),
      });

  /* ------------------------------- deliveries ------------------------------ */

  Future<DriverStats> stats() async => DriverStats.fromJson(asJson(await _api.get('/driver/stats')));

  /// Offers near [latitude]/[longitude] (the server uses the last shared
  /// position when none is given).
  Future<List<Delivery>> available({double? latitude, double? longitude}) async {
    final payload = await _api.get('/driver/deliveries/available', query: {
      'lat': ?latitude,
      'lng': ?longitude,
    });
    return [for (final item in unwrapList(payload, const ['deliveries'])) Delivery.fromJson(item)];
  }

  /// The delivery in progress, or null.
  Future<Delivery?> active() async {
    final raw = asJson(await _api.get('/driver/deliveries/active'))['delivery'];
    return raw is Map ? Delivery.fromJson(asJson(raw)) : null;
  }

  Future<DeliveryPage> history({int page = 1, int limit = 20}) async =>
      DeliveryPage.fromJson(await _api.get('/driver/deliveries/history', query: {'page': page, 'limit': limit}));

  Future<DriverEarnings> earnings({int limit = 20}) async =>
      DriverEarnings.fromJson(asJson(await _api.get('/driver/deliveries/earnings', query: {'limit': limit})));

  /// First to accept wins; a lost race answers with the reason.
  Future<Delivery> accept(String deliveryId) async =>
      Delivery.fromJson(asJson(asJson(await _api.post('/driver/deliveries/${_id(deliveryId)}/accept'))['delivery']));

  Future<void> decline(String deliveryId) async => _api.post('/driver/deliveries/${_id(deliveryId)}/reject');

  Future<Delivery> updateStatus(String deliveryId, String status) async => Delivery.fromJson(asJson(
        asJson(await _api.patch('/driver/deliveries/${_id(deliveryId)}/status', data: {'status': status}))['delivery'],
      ));

  /// Completes the delivery with the customer's code and an optional photo
  /// (a data URI: this endpoint takes no file parts).
  Future<DeliveryCompletion> confirmDelivery(String deliveryId, {required String code, String? photoDataUri}) async =>
      DeliveryCompletion.fromJson(asJson(await _api.post(
        '/driver/deliveries/${_id(deliveryId)}/confirm-delivery',
        data: {'otp_code': code, 'proof_photo_base64': ?photoDataUri},
      )));

  Future<TripNavigation> navigation(String deliveryId) async =>
      TripNavigation.fromJson(asJson(await _api.get('/driver/deliveries/${_id(deliveryId)}/navigation')));

  /* ----------------------------- notifications ----------------------------- */

  Future<DriverNotificationList> notifications({int limit = 30}) async =>
      DriverNotificationList.fromJson(await _api.get('/driver/notifications', query: {'limit': limit}));

  Future<void> markNotificationRead(String id) async => _api.post('/driver/notifications/${_id(id)}/read');

  Future<void> markAllNotificationsRead() async => _api.post('/driver/notifications/read-all');

  String _id(String id) => Uri.encodeComponent(id);
}

/// Reads a photo the worker took into a `data:image/...;base64,` URI.
Future<String> photoAsDataUri(PickedUpload photo) async {
  final bytes = await File(photo.path).readAsBytes();
  return 'data:${photo.mimeType};base64,${base64Encode(bytes)}';
}
