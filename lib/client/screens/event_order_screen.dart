import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../core/config/app_config.dart';
import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../location.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';
import 'checkout_screen.dart';

/// Big Event order (the website's `/event-order/:vendorId`): guests, date and
/// time (days to months ahead), the package, delivery to a pinned venue or
/// pick-up, payment and notes. Prices always come from the server
/// (POST /orders/event-quote); half is paid now, the balance a day before.
class EventOrderScreen extends StatefulWidget {
  const EventOrderScreen({
    super.key,
    required this.vendorId,
    this.packageId,
    this.guests,
    this.pickup = false,
    this.agreementId,
  });

  final String vendorId;
  final String? packageId;
  final int? guests;
  final bool pickup;

  /// A special delivery agreed with the kitchen: its venue and fee are locked.
  final String? agreementId;

  @override
  State<EventOrderScreen> createState() => _EventOrderScreenState();
}

class _EventOrderScreenState extends State<EventOrderScreen> {
  late final CustomerApi _api = context.read<CustomerApi>();
  late final _guests = TextEditingController(
    text: widget.guests?.toString() ?? '',
  );
  late String _packageId = widget.packageId ?? '';
  late bool _pickup = widget.pickup;
  DateTime? _eventAt;
  LatLng? _venue;
  final _venueAddress = TextEditingController();
  final _note = TextEditingController();
  String _method = 'mobile_money';
  final _phone = TextEditingController();
  final _card = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();

  Json? _data;
  String? _quoteError;
  String? _loadError;
  bool _quoting = false;
  bool _submitting = false;
  String? _error;
  Timer? _debounce;
  int _request = 0;
  String? _quotedInputKey;

  // Special delivery: an agreement to book with, or a request to send when
  // the venue needs one (outside the kitchen's coverage, above the automatic
  // price limit...). The server decides which; no fee is charged until the
  // customer accepts the kitchen's quotation.
  Json? _agreement;
  String? _agreementError;
  final _specialNote = TextEditingController();
  bool _requesting = false;
  String? _requestError;
  String? _existingRequestId;

  bool get _agreed => _agreement != null && !_pickup;

  int? get _guestCount {
    final n = int.tryParse(_guests.text.trim());
    return n != null && n >= 1 ? n : null;
  }

  String get _quoteInputKey =>
      '${_guestCount ?? ''}|$_packageId|$_pickup|${_venue?.latitude}|${_venue?.longitude}';

  @override
  void initState() {
    super.initState();
    final location = context.read<ClientLocation>();
    if (location.isLocated) _venue = LatLng(location.lat, location.lng);
    _phone.text = localPhone(context.read<CustomerSession>().phone);
    _requote();
    if (widget.agreementId != null) _loadAgreement();
  }

  /// The agreed special delivery: its venue, event time and fee are used as they are.
  Future<void> _loadAgreement() async {
    try {
      final request = await _api.specialDelivery(widget.agreementId!);
      if (!mounted) return;
      if (request['can_checkout'] != true) {
        setState(() => _agreementError = 'This delivery agreement can no longer be used for booking.');
        return;
      }
      final where = request['delivery_location'] is Map ? (request['delivery_location'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      final event = request['event'] is Map ? (request['event'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      final lat = (where['latitude'] as num?)?.toDouble();
      final lng = (where['longitude'] as num?)?.toDouble();
      setState(() {
        _agreement = request;
        _pickup = false;
        _venueAddress.text = '${where['address'] ?? ''}';
        if (lat != null && lng != null) _venue = LatLng(lat, lng);
        _eventAt = DateTime.tryParse('${event['event_at'] ?? ''}')?.toLocal() ?? _eventAt;
      });
      _requote();
    } catch (e) {
      if (mounted) setState(() => _agreementError = e.toString());
    }
  }

  /// Asks the kitchen for a special delivery (no fee is charged), then opens the request.
  Future<void> _requestSpecialDelivery(Json quote, Json pkg) async {
    setState(() {
      _requestError = null;
      _existingRequestId = null;
    });
    if (!await MarketNav.requireSignIn(context) || !mounted) return;
    if (_eventAt == null) return setState(() => _requestError = 'Choose the date and time of your event first.');
    if (_venueAddress.text.trim().isEmpty || _venue == null) {
      return setState(() => _requestError = 'Enter the venue address and pin it on the map.');
    }
    setState(() => _requesting = true);
    try {
      final request = await _api.createSpecialDelivery({
        'vendor_id': widget.vendorId,
        'package_id': _packageId.isNotEmpty ? _packageId : quote['package_id'] ?? pkg['id'],
        'guests': _guestCount,
        'event_at': _eventAt!.toUtc().toIso8601String(),
        'delivery_location': {'address': _venueAddress.text.trim(), 'latitude': _venue!.latitude, 'longitude': _venue!.longitude},
        'instructions': _specialNote.text.trim(),
      });
      if (!mounted) return;
      await MarketNav.specialDelivery(context, '${request['id']}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _requestError = e.message;
          final existing = e.details['request_id'];
          _existingRequestId = existing == null ? null : '$existing';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _requestError = e.toString());
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }


  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _guests,
      _venueAddress,
      _note,
      _specialNote,
      _phone,
      _card,
      _expiry,
      _cvv,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Re-prices (after a short pause) whenever guests, package, delivery / pick-up or the pin change.
  void _requoteSoon() {
    _debounce?.cancel();
    ++_request;
    final hasGuests = _guestCount != null;
    setState(() {
      _quoting = hasGuests;
      _quoteError = null;
      _loadError = null;
    });
    if (!hasGuests) return;
    _debounce = Timer(const Duration(milliseconds: 400), _requote);
  }

  Future<void> _requote() async {
    final guests = _guestCount;
    if (guests == null) {
      ++_request;
      if (mounted) setState(() => _quoting = false);
      return;
    }
    final request = ++_request;
    final inputKey = _quoteInputKey;
    setState(() => _quoting = true);
    try {
      final data = await _api.eventQuote({
        'vendor_id': widget.vendorId,
        if (_packageId.isNotEmpty) 'package_id': _packageId,
        'guests': guests,
        'fulfillment': _pickup ? 'pickup' : 'delivery',
        if (!_pickup && _venue != null)
          'delivery_location': {
            'latitude': _venue!.latitude,
            'longitude': _venue!.longitude,
          },
      });
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _quotedInputKey = inputKey;
        _quoteError = null;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        if (e.status == 409 || e.status == 400 || _data != null) {
          _quoteError = e.message;
        } else {
          _loadError = e.message;
        }
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(
          () => _data == null
              ? _loadError = e.toString()
              : _quoteError = e.toString(),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _quoting = false);
    }
  }

  void _setPickup(bool pickup) {
    setState(() => _pickup = pickup);
    _requote();
  }

  Future<void> _pickWhen(int leadHours) async {
    final earliest = DateTime.now().add(Duration(hours: leadHours, minutes: 5));
    final day = await showDatePicker(
      context: context,
      initialDate: _eventAt ?? earliest,
      firstDate: earliest,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _eventAt ?? const TimeOfDay(hour: 12, minute: 0).toDateTime(day),
      ),
    );
    if (time == null) return;
    setState(
      () => _eventAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _placeOrder(Json quote, Json pkg) async {
    setState(() => _error = null);
    if (!await MarketNav.requireSignIn(context) || !mounted) return;
    final guests = _guestCount;
    final leadHours = (quote['min_lead_hours'] as num?)?.toInt() ?? 48;
    if (guests == null) {
      return setState(() => _error = 'Enter the number of guests.');
    }
    if (_quoteError != null) return setState(() => _error = _quoteError);
    if (_eventAt == null) {
      return setState(() => _error = 'Choose the date and time of your event.');
    }
    if (_eventAt!.isBefore(DateTime.now().add(Duration(hours: leadHours)))) {
      return setState(
        () => _error =
            'Big events must be booked at least ${(leadHours / 24).round()} days ahead. Pick a later date.',
      );
    }
    if (!_pickup && _venueAddress.text.trim().isEmpty) {
      return setState(() => _error = 'Enter the address of the event venue.');
    }
    if (!_pickup && _venue == null) {
      return setState(() => _error = 'Pin the event venue on the map.');
    }
    final payment = buildPaymentDetails(
      _method,
      phone: _phone.text,
      cardNumber: _card.text,
      cardExpiry: _expiry.text,
      cardCvv: _cvv.text,
    );
    if (payment.error != null) return setState(() => _error = payment.error);
    setState(() => _submitting = true);
    try {
      final order = await _api.eventCheckout({
        'vendor_id': widget.vendorId,
        'package_id': _packageId.isNotEmpty
            ? _packageId
            : quote['package_id'] ?? pkg['id'],
        'guests': guests,
        'fulfillment': _pickup ? 'pickup' : 'delivery',
        'event_at': _eventAt!.toUtc().toIso8601String(),
        'delivery_location': _pickup
            ? {'note': ''}
            : {
                'address': _venueAddress.text.trim(),
                'latitude': _venue!.latitude,
                'longitude': _venue!.longitude,
              },
        'note': _note.text.trim(),
        if (_agreed) 'special_delivery_request_id': _agreement!['id'],
        'payment_method': _method,
        'payment_details': payment.details,
      });
      if (!mounted) return;
      context.read<Orders>().put(order);
      await MarketNav.orderAfterCheckout(context, order.id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return MarketPage(
        title: 'Order for your event',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loadError != null)
              ErrorCard(
                title: 'This event offer could not load',
                message: _loadError,
                onRetry: _requote,
              )
            else if (_guestCount == null)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('Number of guests'),
                    TextField(
                      controller: _guests,
                      keyboardType: TextInputType.number,
                      decoration: marketInput('e.g. 150'),
                      onChanged: (_) => _requoteSoon(),
                    ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      );
    }
    Json m(dynamic v) =>
        v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    num n(dynamic v) => (v as num?) ?? 0;
    final vendor = m(data['vendor']);
    final offer = m(data['offer']);
    final pkg = m(offer['package']);
    final quote = m(data['quote']);
    final packages =
        (offer['packages'] is List ? offer['packages'] as List : const [])
            .whereType<Map>()
            .map((p) => p.cast<String, dynamic>())
            .toList();
    final tiers = (pkg['tiers'] is List ? pkg['tiers'] as List : const [])
        .whereType<Map>();
    final leadHours = n(quote['min_lead_hours'] ?? 48).toInt();
    final quoteMatches =
        _quotedInputKey == _quoteInputKey &&
        _quoteError == null &&
        quote['guests'] == _guestCount;
    final dueAt = _eventAt?.subtract(
      Duration(hours: n(quote['balance_due_hours_before'] ?? 24).toInt()),
    );
    final menu = (pkg['menu'] is List ? pkg['menu'] as List : const []).join(
      ' · ',
    );
    // Big-event delivery for the pinned venue, priced by KitchenLink:
    // 'automatic', 'negotiation_required', 'unavailable' or 'pending_location'.
    final delivery = m(data['delivery']);
    final deliveryStatus = '${delivery['status'] ?? ''}';
    final num? deliveryFee = _pickup
        ? 0
        : _agreed
        ? n(_agreement!['agreed_fee_rwf'])
        : deliveryStatus == 'automatic' && quote['delivery_fee_rwf'] != null
        ? n(quote['delivery_fee_rwf'])
        : null;
    final needsSpecial = !_pickup && !_agreed && deliveryStatus == 'negotiation_required';
    final noDelivery = !_pickup && !_agreed && deliveryStatus == 'unavailable';
    // With an agreed fee the totals add up here (the server checks them again at checkout).
    final totalRwf = n(quote['food_total_rwf']) + (deliveryFee ?? 0);
    final depositRwf = _agreed ? (totalRwf * n(quote['deposit_percent'] ?? 50) / 100).round() : n(quote['deposit_rwf']);
    final balanceRwf = _agreed ? totalRwf - depositRwf : n(quote['balance_rwf']);

    return MarketPage(
      title: 'Order for your event',
      subtitle:
          '${vendor['name'] ?? ''}${'${vendor['neighborhood'] ?? ''}'.isNotEmpty ? ' · ${vendor['neighborhood']}' : ''}',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StepPanel(
            step: 1,
            title: 'Your event',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Number of guests'),
                TextField(
                  controller: _guests,
                  keyboardType: TextInputType.number,
                  decoration: marketInput('e.g. 150'),
                  onChanged: (_) => _requoteSoon(),
                ),
                const SizedBox(height: 10),
                const FieldLabel('Date and time'),
                OutlineAction(
                  label: _eventAt == null
                      ? 'Choose the date and time'
                      : DateFormat('EEE d MMM yyyy, HH:mm').format(_eventAt!),
                  icon: Icons.event,
                  color: K.brown700,
                  onTap: () => _pickWhen(leadHours),
                ),
                if (packages.length > 1) ...[
                  const SizedBox(height: 12),
                  const FieldLabel('Package'),
                  for (final option in packages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ChoiceTile(
                        selected: '${option['id']}' == '${pkg['id']}',
                        onTap: () {
                          setState(() => _packageId = '${option['id']}');
                          _requote();
                        },
                        title: '${option['name'] ?? 'Package'}',
                        subtitle:
                            '${option['min_guests']}–${option['max_guests']} guests · from ${rwf(n(option['from_price_per_plate_rwf']))}/plate',
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${pkg['name'] ?? ''}: ${tiers.map((t) => '${t['min_guests']}–${t['max_guests']} guests (${rwf(n(t['price_per_plate_rwf']))}/plate)').join(', ')}. '
                  'Book at least ${(leadHours / 24).round()} days ahead — even months before your event.',
                  style: kText(11.5, color: K.stone500, height: 1.5),
                ),
                if (_quoteError != null) ...[
                  const SizedBox(height: 8),
                  Notice(_quoteError!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          StepPanel(
            step: 2,
            title: 'How will you get the food?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceTile(
                        selected: !_pickup,
                        onTap: () => _setPickup(false),
                        title: 'Delivery',
                        subtitle: 'The kitchen brings it · delivery fee',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceTile(
                        selected: _pickup,
                        onTap: () => _setPickup(true),
                        title: 'Pick up',
                        subtitle: 'You collect it · no delivery fee',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_pickup)
                  Notice(
                    'Collect from ${vendor['name'] ?? 'the kitchen'}${[vendor['address'], vendor['neighborhood']].where((s) => s != null && '$s'.isNotEmpty).isNotEmpty ? ' · ${[vendor['address'], vendor['neighborhood']].where((s) => s != null && '$s'.isNotEmpty).join(', ')}' : ''}\n'
                    "Once you've paid the balance you'll get a 6-digit code. Give it to the kitchen when you collect the food.",
                    tone: NoticeTone.brand,
                    icon: Icons.storefront_outlined,
                  )
                else ...[
                  const FieldLabel('Event venue address'),
                  TextField(
                    controller: _venueAddress,
                    // Locked to the agreed special delivery's venue.
                    readOnly: _agreed,
                    maxLength: 200,
                    decoration: marketInput(
                      'e.g. Kigali Serena Hotel, KN 3 Ave',
                    ).copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 10),
                  if (_agreed)
                    Notice(
                      'Special delivery ${_agreement!['reference'] ?? ''}: ${rwf(n(_agreement!['agreed_fee_rwf']))} agreed with the kitchen for this venue. The venue and the delivery fee are locked.',
                      tone: NoticeTone.success,
                      icon: Icons.handshake_outlined,
                    )
                  else ...[
                    const FieldLabel('Pin the venue on the map'),
                    VenuePicker(
                      value: _venue,
                      onChanged: (point) {
                        setState(() => _venue = point);
                        _requoteSoon();
                      },
                    ),
                  ],
                  if (_agreementError != null) ...[
                    const SizedBox(height: 8),
                    Notice(_agreementError!),
                  ],
                  if (deliveryStatus == 'automatic' && !_agreed && delivery['starting_fee_rwf'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'KitchenLink big-event delivery: ${rwf(n(delivery['starting_fee_rwf']))} + ${delivery['per_meter_rwf']} RWF per meter of road${delivery['distance_km'] != null ? ' (${delivery['distance_km']} km)' : ''}.',
                        style: kText(11.5, color: K.stone500),
                      ),
                    ),
                  if (noDelivery) ...[
                    const SizedBox(height: 8),
                    Notice('${delivery['message'] ?? "This kitchen doesn't deliver big-event orders."}', tone: NoticeTone.warning),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () => _setPickup(true), child: const Text('Pick up instead')),
                    ),
                  ],
                  if (needsSpecial) ...[
                    const SizedBox(height: 10),
                    Panel(
                      color: K.brown50,
                      border: K.brown200,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Icon(Icons.handshake_outlined, size: 18, color: K.brown700),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Special delivery needed', style: kText(13, weight: w900, color: K.brown850))),
                          ]),
                          const SizedBox(height: 6),
                          Text('${delivery['message'] ?? ''}', style: kText(12, color: K.stone700, height: 1.4)),
                          for (final reason in (delivery['reason_messages'] is List ? delivery['reason_messages'] as List : const []))
                            Text('• $reason', style: kText(11.5, color: K.stone500, height: 1.4)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _specialNote,
                            maxLines: 2,
                            maxLength: 1000,
                            decoration: marketInput('Delivery instructions for the kitchen (access, unloading, contact on site…)'),
                          ),
                          if (_requestError != null) ...[
                            Notice(_requestError!),
                            if (_existingRequestId != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => MarketNav.specialDelivery(context, _existingRequestId!),
                                  child: const Text('Open it'),
                                ),
                              ),
                          ],
                          const SizedBox(height: 6),
                          GradientButton(
                            label: _requesting ? 'Sending…' : 'Request special delivery',
                            onTap: _requesting ? null : () => _requestSpecialDelivery(quote, pkg),
                          ),
                          const SizedBox(height: 6),
                          Text("No delivery fee is charged until you accept the kitchen's quotation.", style: kText(11, color: K.stone500)),
                        ],
                      ),
                    ),
                  ],

                  if ('${offer['delivery_details'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${offer['delivery_details']}',
                        style: kText(11.5, color: K.stone500),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          StepPanel(
            step: 3,
            title: 'Payment',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaymentFields(
                  method: _method,
                  onMethod: (v) => setState(() => _method = v),
                  phone: _phone,
                  card: _card,
                  expiry: _expiry,
                  cvv: _cvv,
                ),
                const SizedBox(height: 12),
                const FieldLabel('Notes for the kitchen'),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: marketInput(
                    'e.g. Wedding reception; 10 vegetarian plates please',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Order summary', style: kText(16, weight: w900)),
                const SizedBox(height: 8),
                Text('${pkg['name'] ?? ''}', style: kText(14, weight: w900)),
                if ('${pkg['description'] ?? ''}'.isNotEmpty)
                  Text(
                    '${pkg['description']}',
                    style: kText(12, color: K.stone500),
                  ),
                if (menu.isNotEmpty)
                  Text(menu, style: kText(12, color: K.stone600)),
                if ('${pkg['portion'] ?? ''}'.isNotEmpty)
                  Text(
                    '${pkg['portion']}',
                    style: kText(11.5, color: K.stone500),
                  ),
                if (!_pickup &&
                    '${pkg['service_style_label'] ?? ''}'.isNotEmpty)
                  Text(
                    '${pkg['service_style_label']}${'${pkg['service_details'] ?? ''}'.isNotEmpty ? ' — ${pkg['service_details']}' : ''}',
                    style: kText(11.5, color: K.stone500),
                  ),
                Divider(height: 20, color: K.stone100),
                if (quoteMatches) ...[
                  MoneyRow(
                    '${quote['guests']} ${quote['guests'] == 1 ? 'plate' : 'plates'} × ${rwf(n(quote['price_per_plate_rwf']))}',
                    rwf(n(quote['food_total_rwf'])),
                  ),
                  _pickup
                      ? const MoneyRow('Pick up', 'No delivery fee')
                      : MoneyRow(
                          _agreed
                              ? 'Delivery (agreed)'
                              : quote['distance_km'] != null
                              ? 'Delivery (${quote['distance_km']} km)'
                              : 'Delivery',
                          deliveryFee != null
                              ? rwf(deliveryFee)
                              : needsSpecial
                              ? 'Special delivery'
                              : noDelivery
                              ? 'Not available'
                              : 'Pin the venue',
                        ),
                  MoneyRow('Total', rwf(totalRwf), strong: true),
                  if (deliveryFee != null) ...[
                    MoneyRow(
                      'Pay now (${quote['deposit_percent']}%)',
                      rwf(depositRwf),
                      color: K.brown750,
                    ),
                    MoneyRow(
                      'Balance, ${dueAt != null ? 'by ${DateFormat('EEE d MMM, HH:mm').format(dueAt)}' : 'a day before the event'}',
                      rwf(balanceRwf),
                    ),
                  ],

                ] else
                  Text(
                    _quoteError ??
                        'Enter your number of guests to see the price.',
                    style: kText(12, color: K.stone500),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Notice(_error!),
                ],
                const SizedBox(height: 12),
                GradientButton(
                  label: _submitting
                      ? 'Placing your order…'
                      : quoteMatches && deliveryFee != null
                      ? 'Place order · pay ${rwf(depositRwf)} now'
                      : 'Place order',
                  onTap:
                      _submitting ||
                          _quoting ||
                          !quoteMatches ||
                          deliveryFee == null
                      ? null
                      : () => _placeOrder(quote, pkg),
                ),
                const SizedBox(height: 8),
                Text(
                  'You pay half now and the rest a day before your event, from your order page. Your money is held safely until the kitchen hands over the food with your code.',
                  style: kText(11, color: K.stone500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on TimeOfDay {
  DateTime toDateTime(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);
}

/// Tap the map to pin a place (or use the phone's position).
class VenuePicker extends StatelessWidget {
  const VenuePicker({super.key, required this.value, required this.onChanged});

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;

  @override
  Widget build(BuildContext context) {
    final location = context.watch<ClientLocation>();
    final start = value ?? LatLng(location.lat, location.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              key: ValueKey(value == null),
              options: MapOptions(
                initialCenter: start,
                initialZoom: value == null ? 12 : 15,
                onTap: (_, point) => onChanged(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.cartoTileUrl,
                  userAgentPackageName: 'com.kitchenlink.kitchenlink_mobile',
                  retinaMode: true,
                ),
                if (value != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: value!,
                        width: 36,
                        height: 36,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.location_on,
                          size: 36,
                          color: K.brown700,
                        ),
                      ),
                    ],
                  ),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      '© OpenStreetMap © CARTO',
                      style: TextStyle(fontSize: 9, color: Colors.black54),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? 'Tap the map where the event is.'
                    : 'Pinned: ${value!.latitude.toStringAsFixed(5)}, ${value!.longitude.toStringAsFixed(5)}',
                style: kText(11.5, color: K.stone500),
              ),
            ),
            OutlineAction(
              label: location.status == LocationStatus.requesting
                  ? 'Locating…'
                  : 'Use my location',
              icon: Icons.my_location,
              dense: true,
              onTap: location.status == LocationStatus.requesting
                  ? null
                  : () async {
                      if (await location.requestGps()) {
                        onChanged(LatLng(location.lat, location.lng));
                      } else if (context.mounted) {
                        showMarketSnack(
                          context,
                          'Could not get your location. Tap the map instead.',
                        );
                      }
                    },
            ),
          ],
        ),
      ],
    );
  }
}
