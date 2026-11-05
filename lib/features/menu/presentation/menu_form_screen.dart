import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/uploads.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../../core/widgets/pickers.dart';
import '../application/menu_providers.dart';
import '../models/menu.dart';

/// Create (`/menu/new`) or edit (`/menu/:id/edit`) a dish.
class MenuFormScreen extends ConsumerWidget {
  const MenuFormScreen({super.key, this.itemId});

  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null) return const _MenuForm();
    final menu = ref.watch(menuProvider);
    return menu.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text('Edit dish')), body: const SkeletonList(count: 3)),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit dish')),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(menuProvider)),
      ),
      data: (items) {
        final match = items.where((item) => item.id == itemId);
        if (match.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit dish')),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Dish not found', message: 'It may have been deleted.'),
          );
        }
        return _MenuForm(item: match.first);
      },
    );
  }
}

class _OptionRow {
  _OptionRow({String group = '', String name = '', String price = ''})
      : group = TextEditingController(text: group),
        name = TextEditingController(text: name),
        price = TextEditingController(text: price);

  final TextEditingController group;
  final TextEditingController name;
  final TextEditingController price;

  void dispose() {
    group.dispose();
    name.dispose();
    price.dispose();
  }
}

class _MenuForm extends ConsumerStatefulWidget {
  const _MenuForm({this.item});

  final MenuItem? item;

  @override
  ConsumerState<_MenuForm> createState() => _MenuFormState();
}

class _MenuFormState extends ConsumerState<_MenuForm> {
  static const int _maxOptions = 30;
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _description = TextEditingController(text: widget.item?.description);
  late final _price = TextEditingController(text: widget.item?.priceRwf.toString());
  late final _prep = TextEditingController(text: widget.item == null ? '' : widget.item!.preparationMinutes.toString());
  late final _cutoff = TextEditingController(text: widget.item?.preorderCutoff);
  late String? _categoryId = widget.item?.category?.id;
  late bool _available = widget.item?.isAvailable ?? true;
  late bool _popular = widget.item?.isPopular ?? false;
  late bool _preorder = widget.item?.isPreorder ?? false;
  late final List<_OptionRow> _options = [
    for (final option in widget.item?.options ?? const <MenuOption>[])
      _OptionRow(
        group: option.groupName,
        name: option.name,
        price: option.additionalPriceRwf > 0 ? option.additionalPriceRwf.toString() : '',
      ),
  ];
  PickedUpload? _image;
  bool _removeImage = false;
  bool _saving = false;
  double? _progress;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _prep, _cutoff]) {
      c.dispose();
    }
    for (final row in _options) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await chooseImage(context, ref.read(mediaPickerProvider));
    if (file != null) {
      setState(() {
        _image = file;
        _removeImage = false;
      });
    }
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name', hintText: 'e.g. Seafood'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2 || !mounted) return;
    final category = await runAction(context, () => ref.read(menuActionsProvider).createCategory(name));
    if (category != null && mounted) setState(() => _categoryId = category.id);
  }

  String? _optionsProblem() {
    for (var i = 0; i < _options.length; i++) {
      final row = _options[i];
      if (row.name.text.trim().isEmpty) return 'Option ${i + 1} needs a name.';
      final price = row.price.text.trim();
      if (price.isNotEmpty && int.tryParse(price) == null) return 'Option ${i + 1}: extra price must be a whole number.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final problem = _optionsProblem();
    if (problem != null) {
      showError(context, problem);
      return;
    }
    final draft = MenuItemDraft(
      name: _name.text,
      priceRwf: int.parse(_price.text.trim()),
      description: _description.text,
      preparationMinutes: int.tryParse(_prep.text.trim()) ?? 0,
      categoryId: _categoryId,
      isAvailable: _available,
      isPreorder: _preorder,
      preorderCutoff: _cutoff.text,
      isPopular: _popular,
      options: [
        for (final row in _options)
          MenuOption(
            groupName: row.group.text.trim().isEmpty ? 'Options' : row.group.text.trim(),
            name: row.name.text.trim(),
            additionalPriceRwf: int.tryParse(row.price.text.trim()) ?? 0,
          ),
      ],
      clearImage: _removeImage && _image == null,
    );
    setState(() {
      _saving = true;
      _progress = null;
    });
    void onProgress(int sent, int total) {
      if (mounted && total > 0) setState(() => _progress = sent / total);
    }

    final actions = ref.read(menuActionsProvider);
    final saved = await runAction(
      context,
      () => _editing
          ? actions.update(widget.item!.id, draft, image: _image, onProgress: onProgress)
          : actions.create(draft, image: _image, onProgress: onProgress),
      success: _editing ? 'Dish updated.' : 'Dish added to your menu.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(foodCategoriesProvider);
    final existingImage = _removeImage ? null : widget.item?.imageUrl;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit dish' : 'Add a dish')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: FormPage(children: [
                ImagePickerBox(
                  picked: _image,
                  height: 180,
                  label: 'Add a photo of the dish',
                  existingWidget: existingImage == null ? null : AppImage(url: existingImage, radius: 0),
                  onTap: _pickImage,
                  onRemove: () => setState(() => _image = null),
                ),
                if (_image == null && existingImage != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _removeImage = true),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove photo'),
                    ),
                  ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Dish name',
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  validator: (value) => Validators.length(value, 'Name', min: 2, max: 80),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  label: 'Description (optional)',
                  controller: _description,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Price (RWF)',
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) => Validators.wholeNumber(value, 'Price', max: 100000000),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      label: 'Prep time (min)',
                      controller: _prep,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) => Validators.wholeNumber(value, 'Prep time', max: 600, optional: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                categories.when(
                  loading: () => const SkeletonBox(height: 56, radius: 14),
                  error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(foodCategoriesProvider)),
                  data: (list) => Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: list.any((c) => c.id == _categoryId) ? _categoryId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [for (final c in list) DropdownMenuItem(value: c.id, child: Text(c.name))],
                        onChanged: (value) => setState(() => _categoryId = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(onPressed: _addCategory, tooltip: 'New category', icon: const Icon(Icons.add_rounded)),
                  ]),
                ),
                const SizedBox(height: 8),
                SwitchRow(title: 'Available now', subtitle: 'Customers can order this dish.', value: _available, onChanged: (v) => setState(() => _available = v)),
                SwitchRow(title: 'Popular dish', subtitle: 'Highlight it on your storefront.', value: _popular, onChanged: (v) => setState(() => _popular = v)),
                SwitchRow(title: 'Pre-order only', subtitle: 'Customers order ahead of time.', value: _preorder, onChanged: (v) => setState(() => _preorder = v)),
                if (_preorder)
                  AppTextField(
                    label: 'Pre-order cutoff',
                    hint: 'e.g. Order before 6pm the day before',
                    controller: _cutoff,
                    maxLength: 120,
                  ),
                const SectionHeader('Options & extras'),
                Text('Sizes, spice levels, add-ons. Each option can add to the price.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: Text('Option ${i + 1}', style: theme.textTheme.titleSmall)),
                          IconButton(
                            tooltip: 'Remove option',
                            onPressed: () => setState(() => _options.removeAt(i).dispose()),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(children: [
                            TextFormField(
                              controller: _options[i].group,
                              maxLength: 40,
                              decoration: const InputDecoration(labelText: 'Group (e.g. Size)', counterText: ''),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _options[i].name,
                                  maxLength: 60,
                                  decoration: const InputDecoration(labelText: 'Name (e.g. Large)', counterText: ''),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _options[i].price,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(labelText: '+ RWF'),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _options.length >= _maxOptions ? null : () => setState(() => _options.add(_OptionRow())),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(_options.length >= _maxOptions ? 'Maximum $_maxOptions options' : 'Add an option'),
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                      const SizedBox(width: 10),
                      Text(_progress == null ? 'Saving…' : 'Uploading ${(_progress! * 100).round()}%'),
                    ])
                  : Text(_editing ? 'Save changes' : 'Add to menu'),
            ),
          ),
        ]),
      ),
    );
  }
}
