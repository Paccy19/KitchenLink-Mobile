import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../../../core/utils/uploads.dart';
import '../models/menu.dart';

class MenuPage {
  const MenuPage({required this.items, required this.meta});

  factory MenuPage.fromJson(Object? payload) => MenuPage(
        items: [for (final item in unwrapList(payload, ['items', 'menu'])) MenuItem.fromJson(item)],
        meta: PageMeta.fromJson(asJson(payload)['meta']),
      );

  final List<MenuItem> items;
  final PageMeta meta;
}

class MenuRepository {
  const MenuRepository(this._api);
  final ApiClient _api;

  Future<MenuPage> list({int page = 1, int limit = 100}) async =>
      MenuPage.fromJson(await _api.get('/vendor/menu', query: {'page': page, 'limit': limit}));

  /// Public food categories.
  Future<List<MenuCategory>> categories() async => [
        for (final item in unwrapList(await _api.get('/home/categories', auth: false), ['categories']))
          MenuCategory.fromJson(item),
      ];

  /// Adds a category; an existing one with that name is reused by the backend.
  Future<MenuCategory> createCategory(String name) async {
    final json = asJson(await _api.post('/vendor/menu/categories', data: {'name': name}));
    return MenuCategory.fromJson(asJson(json['category']));
  }

  Future<MenuItem> create(
    MenuItemDraft draft, {
    PickedUpload? image,
    void Function(int sent, int total)? onProgress,
  }) async =>
      MenuItem.fromJson(
        asJson(await _api.multipart('POST', '/vendor/menu', await _form(draft, image), onProgress: onProgress)),
      );

  Future<MenuItem> update(
    String id,
    MenuItemDraft draft, {
    PickedUpload? image,
    void Function(int sent, int total)? onProgress,
  }) async =>
      MenuItem.fromJson(
        asJson(await _api.multipart('PUT', '/vendor/menu/$id', await _form(draft, image), onProgress: onProgress)),
      );

  /// Permanently deletes the item (the website does the same: `hard=true`).
  Future<void> delete(String id) => _api.delete('/vendor/menu/$id', query: {'hard': true});

  Future<MenuItem> setAvailability(String id, bool isAvailable) async => MenuItem.fromJson(
        asJson(await _api.patch('/vendor/menu/$id/availability', data: {'is_available': isAvailable})),
      );

  Future<FormData> _form(MenuItemDraft draft, PickedUpload? image) async {
    final form = FormData();
    draft.toFields().forEach((key, value) => form.fields.add(MapEntry(key, value)));
    if (image != null) form.files.add(MapEntry('image', await image.toMultipart()));
    return form;
  }
}
