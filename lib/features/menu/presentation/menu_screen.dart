import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../application/menu_providers.dart';
import '../models/menu.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MenuItem> _filter(List<MenuItem> items) => items.where((item) {
        if (_categoryId != null && item.category?.id != _categoryId) return false;
        final q = _query.trim().toLowerCase();
        return q.isEmpty || item.name.toLowerCase().contains(q) || item.description.toLowerCase().contains(q);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Menu'), actions: const [NotificationBellButton()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/menu/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add dish'),
      ),
      body: AsyncBody<List<MenuItem>>(
        value: menu,
        onRefresh: () => ref.read(menuProvider.notifier).reload(silent: false),
        builder: (context, items) {
          final categories = <String, String>{
            for (final item in items)
              if (item.category != null && item.category!.name.isNotEmpty) item.category!.id: item.category!.name,
          };
          final visible = _filter(items);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search your dishes',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: const Text('All'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null)),
                  ),
                  for (final entry in categories.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _categoryId == entry.key,
                        onSelected: (_) => setState(() => _categoryId = entry.key),
                      ),
                    ),
                ]),
              ),
            Expanded(
              child: visible.isEmpty
                  ? RefreshableEmpty(
                      icon: Icons.restaurant_menu_rounded,
                      title: items.isEmpty ? 'Your menu is empty' : 'No dishes match',
                      message: items.isEmpty ? 'Add your first dish so customers can order from you.' : 'Try another search or category.',
                      action: items.isEmpty
                          ? FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                              onPressed: () => context.push('/menu/new'),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add a dish'),
                            )
                          : null,
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => MenuItemCard(item: visible[index]),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class MenuItemCard extends ConsumerStatefulWidget {
  const MenuItemCard({super.key, required this.item});

  final MenuItem item;

  @override
  ConsumerState<MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<MenuItemCard> {
  bool _busy = false;

  Future<void> _toggle(bool available) async {
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref.read(menuActionsProvider).setAvailability(widget.item.id, available),
      success: available ? '${widget.item.name} is available.' : '${widget.item.name} is hidden from customers.',
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final item = widget.item;
    final yes = await confirm(
      context,
      title: 'Delete ${item.name}?',
      message: 'This permanently removes the dish and its options from your menu. Past orders keep their details.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!yes || !mounted) return;
    await runAction(context, () => ref.read(menuActionsProvider).delete(item.id), success: '${item.name} deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/menu/${item.id}/edit'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Opacity(opacity: item.isAvailable ? 1 : 0.5, child: AppImage(url: item.imageUrl, width: 76, height: 76)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              [formatRwf(item.priceRwf), if (item.preparationMinutes > 0) '${item.preparationMinutes} min'].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (item.category != null)
              Text(item.category!.name, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (!item.isAvailable) const StatusChip(label: 'Unavailable', tone: Tone.danger, dense: true),
              if (item.isPopular) const StatusChip(label: 'Popular', tone: Tone.warning, icon: Icons.star_rounded, dense: true),
              if (item.isPreorder) const StatusChip(label: 'Pre-order', tone: Tone.info, dense: true),
              if (item.options.isNotEmpty) StatusChip(label: '${item.options.length} options', dense: true),
            ]),
          ]),
        ),
        Column(children: [
          if (_busy)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
          else
            Switch(value: item.isAvailable, onChanged: _toggle),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            onPressed: _delete,
            icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
          ),
        ]),
      ]),
    );
  }
}
