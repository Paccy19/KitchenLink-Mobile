import 'dart:convert';

import '../../../core/network/json.dart';

class MenuCategory {
  const MenuCategory({required this.id, required this.name});

  factory MenuCategory.fromJson(Json json) =>
      MenuCategory(id: str(json['id']), name: str(json['name']));

  final String id;
  final String name;
}

class MenuOption {
  const MenuOption({
    this.id,
    required this.groupName,
    required this.name,
    this.additionalPriceRwf = 0,
    this.isAvailable = true,
  });

  factory MenuOption.fromJson(Json json) => MenuOption(
        id: strOrNull(json['id']),
        groupName: str(json['group_name'], 'Options'),
        name: str(json['name']),
        additionalPriceRwf: intOf(json['additional_price_rwf']),
        isAvailable: boolOf(json['is_available'], true),
      );

  final String? id;
  final String groupName;
  final String name;
  final int additionalPriceRwf;
  final bool isAvailable;

  /// The shape `POST/PUT /vendor/menu` expects in its `options` JSON.
  Json toJson() => {
        'group_name': groupName,
        'name': name,
        'additional_price_rwf': additionalPriceRwf,
      };
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.priceRwf,
    this.description = '',
    this.preparationMinutes = 0,
    this.isAvailable = true,
    this.isPreorder = false,
    this.preorderCutoff = '',
    this.isPopular = false,
    this.imageUrl,
    this.category,
    this.options = const [],
    this.ordersCount = 0,
  });

  factory MenuItem.fromJson(Json json) => MenuItem(
        id: str(json['id']),
        name: str(json['name']),
        description: str(json['description']),
        priceRwf: intOf(json['price_rwf']),
        preparationMinutes: intOf(json['preparation_time_minutes']),
        isAvailable: boolOf(json['is_available'], true),
        isPreorder: boolOf(json['is_preorder']),
        preorderCutoff: str(json['preorder_cutoff']),
        isPopular: boolOf(json['is_popular']),
        imageUrl: strOrNull(json['image_url']),
        category: json['category'] is Map && strOrNull(asJson(json['category'])['id']) != null
            ? MenuCategory(
                id: str(asJson(json['category'])['id']),
                name: str(asJson(json['category'])['name']),
              )
            : null,
        options: [for (final option in asJsonList(json['options'])) MenuOption.fromJson(option)],
        ordersCount: intOf(json['orders_count']),
      );

  final String id;
  final String name;
  final String description;
  final int priceRwf;
  final int preparationMinutes;
  final bool isAvailable;
  final bool isPreorder;
  final String preorderCutoff;
  final bool isPopular;
  final String? imageUrl;
  final MenuCategory? category;
  final List<MenuOption> options;
  final int ordersCount;

  /// Options grouped by their group name, in the order they were listed.
  Map<String, List<MenuOption>> get optionGroups {
    final groups = <String, List<MenuOption>>{};
    for (final option in options) {
      groups.putIfAbsent(option.groupName, () => []).add(option);
    }
    return groups;
  }
}

/// What the item form collects (create and edit).
class MenuItemDraft {
  const MenuItemDraft({
    required this.name,
    required this.priceRwf,
    this.description = '',
    this.preparationMinutes = 0,
    this.categoryId,
    this.isAvailable = true,
    this.isPreorder = false,
    this.preorderCutoff = '',
    this.isPopular = false,
    this.options = const [],
    this.clearImage = false,
  });

  final String name;
  final int priceRwf;
  final String description;
  final int preparationMinutes;
  final String? categoryId;
  final bool isAvailable;
  final bool isPreorder;
  final String preorderCutoff;
  final bool isPopular;
  final List<MenuOption> options;

  /// Edit only: remove the item's current photo (no new photo chosen).
  final bool clearImage;

  /// The multipart text fields, exactly as the backend parses them
  /// (`vendorMenuService.#parsePayload`).
  Map<String, String> toFields() => {
        'name': name.trim(),
        'price_rwf': priceRwf.toString(),
        'description': description.trim(),
        'preparation_time_minutes': preparationMinutes.toString(),
        'is_available': isAvailable.toString(),
        'is_preorder': isPreorder.toString(),
        'preorder_cutoff': isPreorder ? preorderCutoff.trim() : '',
        'is_popular': isPopular.toString(),
        // An empty value clears the category on the server.
        'category_id': categoryId ?? '',
        'options': optionsJson(options),
        if (clearImage) 'image_clear': 'true',
      };

  static String optionsJson(List<MenuOption> options) =>
      jsonEncode([for (final option in options) option.toJson()]);
}
