import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// An async value that loads once, then refreshes itself in the background.
///
/// A failed background refresh keeps the last good data on screen (the offline
/// banner tells the vendor it may be stale) instead of replacing it with an
/// error. The first load, and a manual [reload] with `silent: false`, do
/// surface errors.
abstract class PolledNotifier<T> extends AsyncNotifier<T> {
  /// Loads the data from the API.
  Future<T> fetch();

  /// How often to refresh while the app is in the foreground; null = never.
  Duration? get pollInterval => null;

  @override
  Future<T> build() {
    final interval = pollInterval;
    if (interval != null) keepFresh(ref, interval, reload);
    return fetch();
  }

  /// Fetches again. Background calls ([silent]) never replace data with an error.
  Future<void> reload({bool silent = true}) async {
    final previous = state;
    try {
      final data = await fetch();
      if (ref.mounted) state = AsyncData(data);
    } catch (error, stackTrace) {
      if (!ref.mounted) return;
      if (silent && previous.hasValue) return;
      state = AsyncError<T>(error, stackTrace);
      if (!silent) rethrow;
    }
  }

  /// Replaces the data with something the app already holds (e.g. an API
  /// response to a write).
  void put(T data) {
    if (ref.mounted) state = AsyncData(data);
  }
}
