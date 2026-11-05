import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/registration.dart';
import '../models/vendor_account.dart';
import '../models/vendor_type.dart';
import '../../menu/models/menu.dart';

/// A sent sign-in code. `devOtp` is only present on a development server.
class OtpChallenge {
  const OtpChallenge({required this.phone, required this.expiresInSeconds, this.devOtp});

  factory OtpChallenge.fromJson(Json json) => OtpChallenge(
        phone: str(json['phone_number']),
        expiresInSeconds: intOf(json['expires_in_seconds'], 300),
        devOtp: strOrNull(json['dev_otp']),
      );

  final String phone;
  final int expiresInSeconds;
  final String? devOtp;
}

class AuthResult {
  const AuthResult({required this.token, required this.vendor});

  final String token;
  final VendorAccount vendor;
}

class AuthRepository {
  const AuthRepository(this._api);
  final ApiClient _api;

  Future<OtpChallenge> sendOtp(String phone) async => OtpChallenge.fromJson(
        asJson(await _api.post('/vendor/auth/send-otp', data: {'phone': phone}, auth: false)),
      );

  Future<AuthResult> verifyOtp(String phone, String code) async {
    final json = asJson(
      await _api.post('/vendor/auth/verify-otp', data: {'phone': phone, 'code': code}, auth: false),
    );
    return AuthResult(
      token: str(json['token']),
      vendor: VendorAccount.fromJson(asJson(json['vendor'])),
    );
  }

  Future<VendorAccount> me() async =>
      VendorAccount.fromJson(asJson(asJson(await _api.get('/vendor/auth/me'))['vendor']));

  Future<void> logout() => _api.post('/vendor/auth/logout');

  Future<void> logoutAll() => _api.post('/vendor/auth/logout-all');

  /// Registers a kitchen. Returns the (pending) account the backend created.
  Future<VendorAccount> register(
    RegistrationData data, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final json = asJson(
      await _api.multipart(
        'POST',
        '/vendor/auth/register',
        await data.toFormData(),
        auth: false,
        onProgress: onProgress,
      ),
    );
    return VendorAccount.fromJson(asJson(json['vendor']));
  }

  /// Kitchen types with their descriptions (public).
  Future<List<VendorType>> vendorTypes() async =>
      VendorType.listFromPayload(await _api.get('/vendors/types', auth: false));

  /// Food categories (public), used at registration and in the menu.
  Future<List<MenuCategory>> foodCategories() async => [
        for (final item in unwrapList(await _api.get('/home/categories', auth: false), ['categories']))
          MenuCategory.fromJson(item),
      ];
}
