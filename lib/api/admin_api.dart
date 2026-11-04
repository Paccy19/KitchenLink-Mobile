import 'api_client.dart';

/// Every `/admin/*` call the website's `src/api/adminApi.js` makes, with the
/// same paths, bodies and query parameters.
class AdminApi {
  AdminApi(this.client);

  final ApiClient client;

  Future<dynamic> _get(String path, [Map<String, Object?>? params]) => client.request('$path${ApiClient.qs(params)}');
  Future<dynamic> _post(String path, [Object? body]) => client.request(path, method: 'POST', body: body);
  Future<dynamic> _put(String path, Object? body) => client.request(path, method: 'PUT', body: body);
  Future<dynamic> _patch(String path, Object? body) => client.request(path, method: 'PATCH', body: body);
  Future<dynamic> _delete(String path) => client.request(path, method: 'DELETE');

  String _id(String value) => ApiClient.id(value);

  // ---- Sign-in and account security --------------------------------------
  Future<dynamic> login(String email, String password) =>
      _post('/admin/auth/login', {'email': email, 'password': password});
  Future<dynamic> me() => _get('/admin/auth/me');
  Future<dynamic> changePassword(Json payload) => _post('/admin/auth/change-password', payload);
  // SMS codes: second sign-in step, setup, and codes confirming money actions.
  Future<dynamic> verifyTwoFactor(String challengeToken, String code) =>
      _post('/admin/auth/verify-2fa', {'challenge_token': challengeToken, 'code': code});
  Future<dynamic> startTwoFactor(String phone) => _post('/admin/auth/2fa/start', {'phone': phone});
  Future<dynamic> enableTwoFactor(String phone, String code) =>
      _post('/admin/auth/2fa/enable', {'phone': phone, 'code': code});
  Future<dynamic> disableTwoFactor(String code) => _post('/admin/auth/2fa/disable', {'code': code});
  Future<dynamic> sendActionCode(String purpose) => _post('/admin/auth/action-code', {'purpose': purpose});

  // ---- The owner's platform money (super admin only) ----------------------
  Future<dynamic> ownerOverview() => _get('/admin/platform/owner');
  Future<dynamic> ownerWithdraw(Json body) => _post('/admin/platform/owner/withdrawals', body);
  Future<dynamic> ownerCompleteWithdrawal(String id, Json body) =>
      _post('/admin/platform/owner/withdrawals/${_id(id)}/complete', body);
  Future<dynamic> ownerCancelWithdrawal(String id, Json body) =>
      _post('/admin/platform/owner/withdrawals/${_id(id)}/cancel', body);
  Future<dynamic> ownerAddDestination(Json body) => _post('/admin/platform/owner/destinations', body);
  Future<dynamic> ownerRemoveDestination(String id, Json body) =>
      _post('/admin/platform/owner/destinations/${_id(id)}/remove', body);
  Future<dynamic> ownerAdjustment(Json body) => _post('/admin/platform/owner/adjustments', body);
  Future<dynamic> ownerReconciliation(Json body) => _post('/admin/platform/owner/reconciliations', body);
  Future<dynamic> ownerSavePayoutSettings(Json body) => _put('/admin/platform/owner/payout-settings', body);

  Future<dynamic> dashboard() => _get('/admin/dashboard/overview');

  // ---- The platform's money books (finance role) --------------------------
  Future<dynamic> platformWallet([Map<String, Object?>? params]) => _get('/admin/platform/wallet', params);
  Future<dynamic> platformTransactions([Map<String, Object?>? params]) => _get('/admin/platform/transactions', params);

  Future<dynamic> listNotifications([Map<String, Object?>? params]) => _get('/admin/notifications', params);
  Future<dynamic> markNotificationRead(String id) => _post('/admin/notifications/${_id(id)}/read');
  Future<dynamic> markAllNotificationsRead() => _post('/admin/notifications/read-all');

  Future<dynamic> listUsers([Map<String, Object?>? params]) => _get('/admin/users', params);
  Future<dynamic> getUser(String id, [Map<String, Object?>? params]) => _get('/admin/users/${_id(id)}', params);
  // Erases a customer's personal data on request (cannot be undone).
  Future<dynamic> eraseCustomer(String id) => _post('/admin/users/${_id(id)}/erase', {'confirm': 'ERASE'});
  Future<dynamic> setUserStatus(String id, Json body) => _patch('/admin/users/${_id(id)}/status', body);

  // Customer–kitchen chats, read only.
  Future<dynamic> listChats([Map<String, Object?>? params]) => _get('/admin/chats', params);
  Future<dynamic> getChat(String id, [Map<String, Object?>? params]) => _get('/admin/chats/${_id(id)}', params);

  Future<dynamic> listVendors([Map<String, Object?>? params]) => _get('/admin/vendors', params);
  Future<dynamic> vendorCounts() => _get('/admin/vendors/counts');
  Future<dynamic> getVendor(String id) => _get('/admin/vendors/${_id(id)}');
  Future<dynamic> reviewVendorDocuments(String id) => _post('/admin/vendors/${_id(id)}/documents/review');
  Future<dynamic> setVendorStatus(String id, Json body) => _patch('/admin/vendors/${_id(id)}/status', body);
  // { vendor_type } to set it directly, or { decision: 'approve' | 'reject' } for the vendor's request.
  Future<dynamic> setVendorType(String id, Json body) => _patch('/admin/vendors/${_id(id)}/type', body);
  // Nationwide events: true / false, or null for the type default (Caterers on).
  Future<dynamic> setVendorNationwide(String id, bool? enabled) =>
      _patch('/admin/vendors/${_id(id)}/nationwide', {'enabled': enabled});

  Future<dynamic> listDrivers([Map<String, Object?>? params]) => _get('/admin/drivers', params);
  Future<dynamic> driverCounts() => _get('/admin/drivers/counts');
  Future<dynamic> getDriver(String id) => _get('/admin/drivers/${_id(id)}');
  Future<dynamic> setDriverStatus(String id, Json body) => _patch('/admin/drivers/${_id(id)}/status', body);
  Future<dynamic> liveDeliveries([Map<String, Object?>? params]) => _get('/admin/deliveries/live', params);
  // One delivery's rider position, route and ETA.
  Future<dynamic> deliveryLive(String deliveryId) => _get('/admin/deliveries/${_id(deliveryId)}/live');
  // Operations: live map, late pickups, rules in force.
  Future<dynamic> liveMap() => _get('/admin/operations/live-map');
  Future<dynamic> latePickups([Map<String, Object?>? params]) => _get('/admin/operations/late-pickups', params);
  Future<dynamic> operationsRules() => _get('/admin/operations/rules');
  // Dispatch and customer-pickup rules (notification radius, re-offer interval...).
  Future<dynamic> saveOperationsRules(Json body) => _put('/admin/operations/rules', body);
  // Delivery fee by distance ranges.
  Future<dynamic> deliveryFees() => _get('/admin/settings/delivery-fees');
  Future<dynamic> saveDeliveryFees(Json body) => _put('/admin/settings/delivery-fees', body);
  // Banks for withdrawals and each bank's account-number length.
  Future<dynamic> bankFormats() => _get('/admin/settings/banks');
  Future<dynamic> saveBankFormats(Json body) => _put('/admin/settings/banks', body);
  // Delivery timing rules (warning / late / automatic reassign), in minutes.
  Future<dynamic> deliveryTiming() => _get('/admin/operations/delivery-timing');
  Future<dynamic> saveDeliveryTiming(Json body) => _put('/admin/operations/delivery-timing', body);

  Future<dynamic> listOrders([Map<String, Object?>? params]) => _get('/admin/orders', params);
  Future<dynamic> getOrder(String id) => _get('/admin/orders/${_id(id)}');
  // Delivery workers near the kitchen, for support to call before reassigning.
  Future<dynamic> nearbyDrivers(String id, [Map<String, Object?>? params]) =>
      _get('/admin/orders/${_id(id)}/nearby-drivers', params);
  Future<dynamic> updateOrderStatus(String id, Json body) => _patch('/admin/orders/${_id(id)}/status', body);
  Future<dynamic> cancelOrder(String id, Json body) => _post('/admin/orders/${_id(id)}/cancel', body);
  Future<dynamic> reassignDriver(String id, Json body) => _post('/admin/orders/${_id(id)}/reassign-driver', body);

  Future<dynamic> listPayments([Map<String, Object?>? params]) => _get('/admin/payments', params);
  Future<dynamic> paymentSummary([Map<String, Object?>? params]) => _get('/admin/payments/summary', params);

  Future<dynamic> listCommissions([Map<String, Object?>? params]) => _get('/admin/commissions', params);
  Future<dynamic> createCommission(Json body) => _post('/admin/commissions', body);
  Future<dynamic> updateCommission(String id, Json body) => _put('/admin/commissions/${_id(id)}', body);
  Future<dynamic> deleteCommission(String id) => _delete('/admin/commissions/${_id(id)}');

  Future<dynamic> listPayouts([Map<String, Object?>? params]) => _get('/admin/payouts', params);
  Future<dynamic> payoutBalances([Map<String, Object?>? params]) => _get('/admin/payouts/balances', params);
  Future<dynamic> payoutSummary([Map<String, Object?>? params]) => _get('/admin/payouts/summary', params);
  Future<dynamic> updatePayout(String id, Json body) => _patch('/admin/payouts/${_id(id)}', body);

  Future<dynamic> listRefunds([Map<String, Object?>? params]) => _get('/admin/refunds', params);
  Future<dynamic> updateRefund(String id, Json body) => _patch('/admin/refunds/${_id(id)}', body);

  Future<dynamic> listCategories() => _get('/admin/categories');
  Future<dynamic> createCategory(Json body) => _post('/admin/categories', body);
  Future<dynamic> updateCategory(String id, Json body) => _put('/admin/categories/${_id(id)}', body);
  Future<dynamic> deleteCategory(String id, {bool force = false}) =>
      _delete('/admin/categories/${_id(id)}${force ? '?force=true' : ''}');
  Future<dynamic> reorderCategories(List<Json> items) => _patch('/admin/categories/reorder', {'items': items});

  Future<dynamic> listComplaints([Map<String, Object?>? params]) => _get('/admin/complaints', params);
  Future<dynamic> getComplaint(String id) => _get('/admin/complaints/${_id(id)}');
  Future<dynamic> createComplaint(Json body) => _post('/admin/complaints', body);
  Future<dynamic> updateComplaint(String id, Json body) => _patch('/admin/complaints/${_id(id)}', body);

  Future<dynamic> analyticsOverview([Map<String, Object?>? params]) => _get('/admin/analytics/overview', params);
  Future<dynamic> analyticsSales([Map<String, Object?>? params]) => _get('/admin/analytics/sales', params);
  Future<dynamic> analyticsPayouts([Map<String, Object?>? params]) => _get('/admin/analytics/payouts', params);

  Future<dynamic> listActions([Map<String, Object?>? params]) => _get('/admin/actions', params);

  // ---- Team (owner only) --------------------------------------------------
  Future<dynamic> listTeam() => _get('/admin/team');
  Future<dynamic> inviteMember(Json body) => _post('/admin/team/invitations', body);
  Future<dynamic> resendInvitation(String id) => _post('/admin/team/${_id(id)}/resend-invitation');
  Future<dynamic> changeMemberRole(String id, Json body) => _patch('/admin/team/${_id(id)}/role', body);
  Future<dynamic> deactivateMember(String id) => _post('/admin/team/${_id(id)}/deactivate');
  Future<dynamic> reactivateMember(String id, Json body) => _post('/admin/team/${_id(id)}/reactivate', body);
  Future<dynamic> removeMember(String id) => _delete('/admin/team/${_id(id)}');

  // ---- Invitation link (no sign-in) ---------------------------------------
  Future<dynamic> getInvitation(String token) => _get('/admin/auth/invitations/${_id(token)}');
  Future<dynamic> acceptInvitation(String token, Json body) =>
      _post('/admin/auth/invitations/${_id(token)}/accept', body);
}
