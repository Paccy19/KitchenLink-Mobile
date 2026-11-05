import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import '../models/dashboard_stats.dart';

class DashboardRepository {
  const DashboardRepository(this._api);
  final ApiClient _api;

  Future<DashboardStats> stats() async =>
      DashboardStats.fromJson(asJson(await _api.get('/vendor/dashboard')));
}
