import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/polled_notifier.dart';
import '../../../core/providers.dart';
import '../models/dashboard_stats.dart';

/// Today's figures. The website refreshes them every 10 seconds; so do we,
/// while the app is open.
class DashboardNotifier extends PolledNotifier<DashboardStats> {
  @override
  Duration? get pollInterval => const Duration(seconds: 10);

  @override
  Future<DashboardStats> fetch() => ref.read(dashboardRepositoryProvider).stats();
}

final dashboardProvider =
    AsyncNotifierProvider.autoDispose<DashboardNotifier, DashboardStats>(DashboardNotifier.new);
