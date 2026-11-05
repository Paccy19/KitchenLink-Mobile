import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../models/promotions.dart';

class SpecialNotifier extends PolledNotifier<Special?> {
  @override
  Future<Special?> fetch() => ref.read(promotionsRepositoryProvider).special();
}

final specialProvider = AsyncNotifierProvider.autoDispose<SpecialNotifier, Special?>(SpecialNotifier.new);

class OffersNotifier extends PolledNotifier<List<Offer>> {
  @override
  Future<List<Offer>> fetch() => ref.read(promotionsRepositoryProvider).offers();
}

final offersProvider = AsyncNotifierProvider.autoDispose<OffersNotifier, List<Offer>>(OffersNotifier.new);

class PromotionsActions {
  PromotionsActions(this._ref);
  final Ref _ref;

  Future<void> saveSpecial({
    required String text,
    required DateTime cutoffAt,
    required DateTime deliveryAt,
  }) async {
    final saved = await _ref
        .read(promotionsRepositoryProvider)
        .saveSpecial(text: text, cutoffAt: cutoffAt, deliveryAt: deliveryAt);
    if (_ref.exists(specialProvider)) _ref.read(specialProvider.notifier).put(saved);
  }

  Future<void> clearSpecial() async {
    await _ref.read(promotionsRepositoryProvider).clearSpecial();
    if (_ref.exists(specialProvider)) _ref.read(specialProvider.notifier).put(null);
  }

  Future<void> createOffer({required String title, String details = '', required String offerDate}) async {
    await _ref
        .read(promotionsRepositoryProvider)
        .createOffer(title: title, details: details, offerDate: offerDate);
    if (_ref.exists(offersProvider)) await _ref.read(offersProvider.notifier).reload();
  }

  Future<void> cancelOffer(String id) async {
    await _ref.read(promotionsRepositoryProvider).cancelOffer(id);
    if (_ref.exists(offersProvider)) await _ref.read(offersProvider.notifier).reload();
  }
}

final promotionsActionsProvider = Provider<PromotionsActions>(PromotionsActions.new);
