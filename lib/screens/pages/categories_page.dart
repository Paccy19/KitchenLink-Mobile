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
    final p = Palette.of(context);
    return PageBody(onRefresh: query.load, children: [
      PageHeader(
        title: 'Categories',
        description: 'Organise how dishes and vendors are grouped across the marketplace.',
        action: canWrite ? WebButton(label: 'New category', icon: Icons.add, onPressed: () => edit()) : null,
      ),
      if (error != null) ErrorNote(error: error),
      SectionCard(
        child: QueryView<Json>(
          query: query,
          builder: (context, data) {
            final items = categories;
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.sell_outlined,
                title: 'No categories yet',
                description: 'Create your first category to organise the marketplace.',
                action: canWrite ? WebButton(label: 'New category', onPressed: () => edit()) : null,
              );
            }
            return WebTable(
              columns: const [
                WebColumn('Category'),
                WebColumn('Order', nowrap: true),
                WebColumn('Status', nowrap: true),
                WebColumn('', alignEnd: true, nowrap: true),
              ],
              rows: [
                for (var i = 0; i < items.length; i++)
                  [
                    Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _icon(jstr(items[i]['icon_url'])),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(jstr(items[i]['name']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                            if (items[i]['created_by_vendor'] is Map)
                              ToneBadge('Added by ${jstr(jmap(items[i]['created_by_vendor'])['name'])}', tone: Tone.amber),
                          ]),
                          if (jstr(items[i]['description']).isNotEmpty)
                            Text(jstr(items[i]['description']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.faint)),
                        ]),
                      ),
                    ]),
                    // Moving rows changes the marketplace order (`sort_order`).
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (canWrite) _arrow(Icons.arrow_upward, i == 0 ? null : () => move(i, -1)),
                      SizedBox(
                        width: 24,
                        child: Text(jstr(items[i]['sort_order'], '0'),
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                      ),
                      if (canWrite) _arrow(Icons.arrow_downward, i == items.length - 1 ? null : () => move(i, 1)),
                    ]),
                    ToneBadge(items[i]['is_active'] == true ? 'Active' : 'Hidden', tone: items[i]['is_active'] == true ? Tone.green : Tone.slate),
                    canWrite
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            SmallButton('Edit', ghost: true, onPressed: () => edit(items[i])),
                            const SizedBox(width: 6),
                            _arrow(Icons.delete_outline, () => remove(items[i]), color: AppColors.red500),
                          ])
                        : const SizedBox.shrink(),
                  ],
              ],
            );
          },
        ),
      ),
    ]);
  }

  /// A `ghost sm` icon button (`px-2.5 py-1.5`), faded when it can't be used.
  Widget _arrow(IconData icon, VoidCallback? onTap, {Color? color}) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Icon(icon, size: 14, color: color ?? p.textSecondary)),
      ),
    );
  }

  /// The category picture, or `w-8 h-8 rounded-lg bg-stone-100` with a tag icon.
  Widget _icon(String url) {
    final p = Palette.of(context);
    final fallback = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: p.stone100, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.sell_outlined, size: 16, color: p.faint),
    );
    if (url.isEmpty || !url.startsWith('http')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
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
