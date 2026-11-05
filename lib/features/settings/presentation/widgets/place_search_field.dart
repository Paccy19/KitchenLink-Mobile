import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/feedback.dart';
import '../../application/settings_providers.dart';
import '../../models/place.dart';

/// Search-as-you-type for a place (area, street or landmark) using the
/// backend's place search. Picking a result returns its details with the
/// position; the field itself never reads the phone's location.
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({super.key, required this.onPicked, this.label = 'Search for your area or street'});

  final ValueChanged<Place> onPicked;
  final String label;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text.trim()));
  }

  Future<void> _search(String text) async {
    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final results = await ref.read(settingsActionsProvider).placeSuggestions(text);
      if (!mounted || id != _requestId) return;
      setState(() => _suggestions = results);
    } catch (error) {
      if (mounted && id == _requestId) showError(context, error);
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _pick(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _suggestions = const [];
      _controller.text = suggestion.name;
    });
    try {
      final place = await ref.read(settingsActionsProvider).placeDetails(suggestion.id);
      if (mounted) widget.onPicked(place);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'street' => Icons.add_road_rounded,
        'area' => Icons.location_city_rounded,
        _ => Icons.place_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)),
                )
              : null,
        ),
      ),
      if (_suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(children: [
            for (final suggestion in _suggestions.take(6))
              ListTile(
                dense: true,
                leading: Icon(_icon(suggestion.kind), color: theme.colorScheme.primary),
                title: Text(suggestion.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: suggestion.secondary.isEmpty
                    ? null
                    : Text(suggestion.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _pick(suggestion),
              ),
          ]),
        ),
    ]);
  }
}
