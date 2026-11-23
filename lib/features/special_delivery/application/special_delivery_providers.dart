import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/json.dart';
import '../../../core/providers.dart';
import '../data/special_delivery_repository.dart';

final specialDeliveryRepositoryProvider = Provider((ref) => SpecialDeliveryRepository(ref.watch(apiClientProvider)));

/// The kitchen's big-event delivery coverage, districts and KitchenLink's (read-only) pricing.
final deliveryCoverageProvider = FutureProvider.autoDispose<Json>(
  (ref) => ref.watch(specialDeliveryRepositoryProvider).coverage(),
);

/// Special delivery requests: 'open' (still being arranged) or 'closed'.
final specialDeliveriesProvider = FutureProvider.autoDispose.family<List<Json>, String>(
  (ref, scope) => ref.watch(specialDeliveryRepositoryProvider).requests(scope: scope),
);

final specialDeliveryProvider = FutureProvider.autoDispose.family<Json, String>(
  (ref, id) => ref.watch(specialDeliveryRepositoryProvider).request(id),
);
