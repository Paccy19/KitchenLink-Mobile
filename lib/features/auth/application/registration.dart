import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../models/registration.dart';
import '../models/vendor_account.dart';

/// Submits a new kitchen's application.
class RegistrationActions {
  RegistrationActions(this._ref);
  final Ref _ref;

  Future<VendorAccount> submit(
    RegistrationData data, {
    void Function(int sent, int total)? onProgress,
  }) =>
      _ref.read(authRepositoryProvider).register(data, onProgress: onProgress);
}

final registrationActionsProvider = Provider<RegistrationActions>(RegistrationActions.new);
