import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../../../core/utils/uploads.dart';
import '../models/menu.dart';

/// The kitchen's whole menu (all pages), loaded when the Menu tab opens and
/// again after every change.
class MenuNotifier extends PolledNotifier<List<MenuItem>> {
  @override
  Future<List<MenuItem>> fetch() async {
    final repo = ref.read(menuRepositoryProvider);
    final items = <MenuItem>[];
    for (var page = 1; page <= 20; page++) {
      final result = await repo.list(page: page);
      items.addAll(result.items);
      if (!result.meta.hasMore) break;
    }
    return items;
  }
}

final menuProvider = AsyncNotifierProvider.autoDispose<MenuNotifier, List<MenuItem>>(MenuNotifier.new);

/// Public food categories (menu form, registration).
final foodCategoriesProvider = FutureProvider.autoDispose<List<MenuCategory>>(
  (ref) => ref.watch(menuRepositoryProvider).categories(),
);

class MenuActions {
  MenuActions(this._ref);
  final Ref _ref;

  Future<MenuItem> create(
    MenuItemDraft draft, {
    PickedUpload? image,
    void Function(int sent, int total)? onProgress,
  }) async {
    final item = await _ref.read(menuRepositoryProvider).create(draft, image: image, onProgress: onProgress);
    await _refresh();
    return item;
  }

  Future<MenuItem> update(
    String id,
    MenuItemDraft draft, {
    PickedUpload? image,
    void Function(int sent, int total)? onProgress,
  }) async {
    final item = await _ref.read(menuRepositoryProvider).update(id, draft, image: image, onProgress: onProgress);
    await _refresh();
    return item;
  }

  Future<void> delete(String id) async {
    await _ref.read(menuRepositoryProvider).delete(id);
    await _refresh();
  }

  Future<MenuItem> setAvailability(String id, bool available) async {
    final item = await _ref.read(menuRepositoryProvider).setAvailability(id, available);
    await _refresh();
    return item;
  }

  Future<MenuCategory> createCategory(String name) async {
    final category = await _ref.read(menuRepositoryProvider).createCategory(name);
    _ref.invalidate(foodCategoriesProvider);
    return category;
  }

  Future<void> _refresh() async {
    if (_ref.exists(menuProvider)) await _ref.read(menuProvider.notifier).reload();
  }
}

final menuActionsProvider = Provider<MenuActions>(MenuActions.new);
