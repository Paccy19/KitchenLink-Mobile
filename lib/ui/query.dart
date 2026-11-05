import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'widgets.dart';

/// A server read for one screen (the website uses React Query): loads on
/// start, re-polls every [poll], and refetches quietly whenever any write
/// succeeds so every open screen stays current.
class Query<T> extends ChangeNotifier {
  Query(this._fetch, {ApiClient? client, this.poll, bool enabled = true}) : _enabled = enabled {
    _changes = client?.changes.listen((_) {
      if (_enabled) load(silent: true);
    });
    if (enabled) load();
    _restartTimer();
  }

  final Future<T> Function() _fetch;
  final Duration? poll;
  StreamSubscription<void>? _changes;
  Timer? _timer;
  bool _enabled;
  bool _disposed = false;
  int _generation = 0;

  T? data;
  Object? error;
  bool loading = false;

  bool get enabled => _enabled;
  bool get isLoading => loading && data == null;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _restartTimer();
    if (value) load();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (poll != null && _enabled) _timer = Timer.periodic(poll!, (_) => load(silent: true));
  }

  /// Reloads; [silent] keeps showing the current data while it loads.
  Future<void> load({bool silent = false}) async {
    if (!_enabled || _disposed) return;
    final generation = ++_generation;
    loading = true;
    if (!silent) {
      data = null;
      error = null;
    }
    _notify();
    try {
      final result = await _fetch();
      if (_disposed || generation != _generation) return;
      data = result;
      error = null;
    } catch (err) {
      if (_disposed || generation != _generation) return;
      // A failed background refresh keeps the last good data on screen.
      if (!silent || data == null) error = err;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}

/// Shows a [Query]'s loading, error or data state.
class QueryView<T> extends StatelessWidget {
  const QueryView({super.key, required this.query, required this.builder, this.loadingLabel = 'Loading…'});

  final Query<T> query;
  final Widget Function(BuildContext context, T data) builder;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        if (query.error != null && query.data == null) {
          return Padding(padding: const EdgeInsets.all(4), child: ErrorNote(error: query.error, onRetry: query.load));
        }
        final data = query.data;
        if (data == null) return LoadingBlock(label: loadingLabel);
        return builder(context, data);
      },
    );
  }
}
