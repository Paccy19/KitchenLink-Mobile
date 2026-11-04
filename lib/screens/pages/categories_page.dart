import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Organise how dishes and vendors are grouped across the marketplace.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late final session = context.read<AdminSession>();
  late final query = Query<Json>(() async => jmap(await session.api.listCategories()), client: session.client);
  Object? error;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  List<Json> get categories => jlist(query.data?['items']);

  Future<void> edit([Json? category]) async {
    final saved = await showAppSheet<bool>(context, _CategorySheet(category: category, nextOrder: categories.length));
    if (saved == true && mounted) showToast(context, 'Category saved.');
  }

  Future<void> move(int index, int direction) async {
    final next = [...categories];
    final target = index + direction;
    if (target < 0 || target >= next.length) return;
    final item = next.removeAt(index);
    next.insert(target, item);
    try {
      await session.api.reorderCategories([
        for (var i = 0; i < next.length; i++) {'id': jstr(next[i]['id']), 'sort_order': i},
      ]);
    } catch (err) {
      setState(() => error = err);
    }
  }

  Future<void> remove(Json category) async {
    if (!await confirmDialog(context, 'Delete category “${jstr(category['name'])}”?', confirm: 'Delete', danger: true)) return;
    setState(() => error = null);
    try {
      await session.api.deleteCategory(jstr(category['id']));
      if (mounted) showToast(context, 'Category deleted.');
    } catch (_) {
      if (!mounted) return;
      final force = await confirmDialog(
        context,
        'This category is used by vendors. Force delete anyway? Vendors will lose this label.',
        confirm: 'Force delete',
        danger: true,
      );
      if (!force) return;
      try {
        await session.api.deleteCategory(jstr(category['id']), force: true);
        if (mounted) showToast(context, 'Category deleted.');
      } catch (err) {
        setState(() => error = err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = session.can('categories:write');
    return PageBody(onRefresh: query.load, children: [
      PageHeader(
        title: 'Categories',
        description: 'Organise how dishes and vendors are grouped across the marketplace.',
        action: canWrite ? FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add, size: 18), label: const Text('New')) : null,
      ),
      if (error != null) ErrorNote(error: error),
      QueryView<Json>(
        query: query,
        builder: (context, data) {
          final items = categories;
          if (items.isEmpty) {
            return Card(
              child: EmptyState(
                icon: Icons.sell_outlined,
                title: 'No categories yet',
                description: 'Create your first category to organise the marketplace.',
                action: canWrite ? FilledButton(onPressed: () => edit(), child: const Text('New category')) : null,
              ),
            );
          }
          return RecordList(children: [
            for (var i = 0; i < items.length; i++)
              RecordTile(
                leading: _icon(jstr(items[i]['icon_url'])),
                title: jstr(items[i]['name']),
                subtitle: jstr(items[i]['description']),
                badges: [
                  ToneBadge(items[i]['is_active'] == true ? 'Active' : 'Hidden', tone: items[i]['is_active'] == true ? Tone.green : Tone.slate),
                  ToneBadge('Order ${jstr(items[i]['sort_order'], '0')}'),
                  if (items[i]['created_by_vendor'] is Map)
                    ToneBadge('Added by ${jstr(jmap(items[i]['created_by_vendor'])['name'])}', tone: Tone.amber),
                ],
                actions: canWrite
                    ? [
                        IconButton.outlined(onPressed: i == 0 ? null : () => move(i, -1), icon: const Icon(Icons.arrow_upward, size: 16)),
                        IconButton.outlined(onPressed: i == items.length - 1 ? null : () => move(i, 1), icon: const Icon(Icons.arrow_downward, size: 16)),
                        OutlinedButton(onPressed: () => edit(items[i]), child: const Text('Edit')),
                        IconButton(onPressed: () => remove(items[i]), icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444))),
                      ]
                    : const [],
              ),
          ]);
        },
      ),
    ]);
  }

  Widget _icon(String url) {
    final fallback = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)),
      child: const Icon(Icons.sell_outlined, size: 16),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(url, width: 34, height: 34, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({this.category, required this.nextOrder});

  final Json? category;
  final int nextOrder;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> with BusyState {
  late final name = TextEditingController(text: jstr(widget.category?['name']));
  late final description = TextEditingController(text: jstr(widget.category?['description']));
  late final iconUrl = TextEditingController(text: jstr(widget.category?['icon_url']));
  late final sortOrder = TextEditingController(text: jstr(widget.category?['sort_order'], '${widget.nextOrder}'));
  late bool isActive = widget.category == null ? true : widget.category!['is_active'] == true;
  String formError = '';

  @override
  void dispose() {
    for (final c in [name, description, iconUrl, sortOrder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().length < 2) {
      setState(() => formError = 'Name must be at least 2 characters.');
      return;
    }
    setState(() => formError = '');
    final api = context.read<AdminSession>().api;
    final payload = {
      'name': name.text.trim(),
      'description': description.text.trim(),
      'icon_url': iconUrl.text.trim(),
      'sort_order': int.tryParse(sortOrder.text) ?? 0,
      'is_active': isActive,
    };
    final id = jstr(widget.category?['id']);
    final ok = await run(() => id.isNotEmpty ? api.updateCategory(id, payload) : api.createCategory(payload));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.category == null ? 'New category' : 'Edit category',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(label: 'Save', busy: busy, onPressed: submit),
      ],
      children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Breakfast')),
        TextField(controller: description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Description (optional)')),
        TextField(
          controller: sortOrder,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Sort order'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show in marketplace'),
          value: isActive,
          onChanged: (value) => setState(() => isActive = value),
        ),
        TextField(controller: iconUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Icon URL (optional)', hintText: 'https://…')),
        if (formError.isNotEmpty) Note(formError),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
