import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/admin_session.dart';
import '../../ui/format.dart';
import '../../ui/query.dart';
import '../../ui/theme.dart';
import '../../ui/vendor_types.dart';
import '../../ui/widgets.dart';

const _paymentStatuses = ['pending', 'processing', 'successful', 'failed', 'refunded'];

/// Track transactions and set commission rules.
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late final session = context.read<AdminSession>();
  late final canSeeCommissions = session.can('commissions:read');
  late final canEditCommissions = session.can('commissions:write');
  String status = '';
  String method = '';
  int page = 1;

  late final paymentsQuery = Query<Json>(
    () async => jmap(await session.api.listPayments({'status': status, 'method': method, 'page': page, 'limit': 20})),
    client: session.client,
  );
  late final summaryQuery = Query<Json>(() async => jmap(await session.api.paymentSummary()), client: session.client);
  late final commissionsQuery = Query<Json>(
    () async => jmap(await session.api.listCommissions({'limit': 100})),
    client: session.client,
    enabled: canSeeCommissions,
  );

  @override
  void dispose() {
    paymentsQuery.dispose();
    summaryQuery.dispose();
    commissionsQuery.dispose();
    super.dispose();
  }

  void apply(VoidCallback change) {
    setState(() {
      change();
      page = 1;
    });
    paymentsQuery.load();
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      onRefresh: () async {
        await Future.wait([paymentsQuery.load(), summaryQuery.load(silent: true), commissionsQuery.load(silent: true)]);
      },
      children: [
        const PageHeader(title: 'Payments & Commissions', description: 'Track transactions and set commission rules.'),
        ListenableBuilder(
          listenable: summaryQuery,
          builder: (context, _) {
            final summary = summaryQuery.data;
            if (summary == null) return const SizedBox.shrink();
            return ResponsiveGrid(children: [
              StatCard(label: 'Successful Total', value: formatRwf(summary['successful_total_rwf']), tone: Tone.green),
              StatCard(label: 'Successful Count', value: formatNumber(summary['successful_count']), tone: Tone.green),
              for (final row in jlist(summary['by_status']).take(2))
                StatCard(label: toTitle(row['status']), value: formatRwf(row['total_rwf']), hint: '${jint(row['count'])} payments', tone: Tone.blue),
            ]);
          },
        ),
        SectionCard(
          title: 'Transactions',
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([
            Row(children: [
              Expanded(
                child: Dropdown<String>(
                  value: status,
                  options: {'': 'All statuses', for (final s in _paymentStatuses) s: toTitle(s)},
                  onChanged: (value) => apply(() => status = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Dropdown<String>(
                  value: method,
                  options: const {'': 'All methods', 'mobile_money': 'Mobile Money', 'card': 'Card', 'ekash': 'eKash', 'cash': 'Cash'},
                  onChanged: (value) => apply(() => method = value),
                ),
              ),
            ]),
            QueryView<Json>(
              query: paymentsQuery,
              builder: (context, data) {
                final items = jlist(data['items']);
                if (items.isEmpty) return const EmptyState(icon: Icons.credit_card_outlined, title: 'No payments found');
                return RecordList(
                  footer: Pager.of(data, onPage: (next) {
                    setState(() => page = next);
                    paymentsQuery.load();
                  }),
                  children: [
                    for (final payment in items)
                      RecordTile(
                        title: jstr(payment['order_number'], '—'),
                        subtitle: jstr(jmap(payment['customer'])['name'], '—'),
                        trailing: formatRwf(payment['amount_rwf']),
                        badges: [StatusBadge(jstr(payment['status'])), ToneBadge(toTitle(payment['provider'] ?? payment['method']))],
                        lines: [formatDate(payment['created_at'])],
                      ),
                  ],
                );
              },
            ),
          ])),
        ),
        if (canSeeCommissions)
          SectionCard(
            title: 'Commission Rules',
            description: canEditCommissions
                ? 'Most specific active scope wins: vendor › category › vendor type › global.'
                : 'Only the owner can change the commission rate.',
            action: canEditCommissions
                ? FilledButton.icon(
                    onPressed: () => showAppSheet(context, const _CommissionSheet()),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New rule'),
                  )
                : null,
            padding: const EdgeInsets.all(10),
            child: QueryView<Json>(
              query: commissionsQuery,
              builder: (context, data) {
                final items = jlist(data['items']);
                if (items.isEmpty) {
                  return const EmptyState(icon: Icons.percent, title: 'No commission rules', description: 'Create a global rule to get started.');
                }
                return RecordList(children: [
                  for (final rule in items)
                    RecordTile(
                      title: jstr(rule['name']),
                      subtitle: jstr(rule['vendor_name'], jstr(rule['category_name'], jstr(rule['vendor_type_label'], jstr(rule['vendor_type'], 'All')))),
                      trailing: '${jstr(rule['percentage'], '0')}%${jint(rule['fixed_fee_rwf']) > 0 ? ' + ${formatRwf(rule['fixed_fee_rwf'])}' : ''}',
                      badges: [
                        ToneBadge(toTitle(rule['scope']), tone: Tone.violet),
                        ToneBadge(rule['is_active'] == true ? 'Active' : 'Inactive', tone: rule['is_active'] == true ? Tone.green : Tone.slate),
                      ],
                      actions: canEditCommissions
                          ? [
                              OutlinedButton(onPressed: () => showAppSheet(context, _CommissionSheet(rule: rule)), child: const Text('Edit')),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                                onPressed: () async {
                                  if (!await confirmDialog(context, 'Delete commission rule “${jstr(rule['name'])}”?', confirm: 'Delete', danger: true)) return;
                                  try {
                                    await session.api.deleteCommission(jstr(rule['id']));
                                  } catch (err) {
                                    if (context.mounted) showToast(context, ErrorNote.messageOf(err));
                                  }
                                },
                              ),
                            ]
                          : const [],
                    ),
                ]);
              },
            ),
          ),
      ],
    );
  }
}

class _CommissionSheet extends StatefulWidget {
  const _CommissionSheet({this.rule});

  final Json? rule;

  @override
  State<_CommissionSheet> createState() => _CommissionSheetState();
}

class _CommissionSheetState extends State<_CommissionSheet> with BusyState {
  late final session = context.read<AdminSession>();
  late final name = TextEditingController(text: jstr(widget.rule?['name']));
  late final percentage = TextEditingController(text: jstr(widget.rule?['percentage'], '15'));
  late final fixedFee = TextEditingController(text: jstr(widget.rule?['fixed_fee_rwf'], '0'));
  late String scope = jstr(widget.rule?['scope'], 'global');
  late String vendorId = jstr(widget.rule?['vendor_id']);
  late String categoryId = jstr(widget.rule?['category_id']);
  late String vendorType = jstr(widget.rule?['vendor_type']);
  late bool isActive = widget.rule == null || widget.rule!['is_active'] == true;
  String formError = '';

  late final categoriesQuery = Query<Json>(() async => jmap(await session.api.listCategories()));
  late final vendorsQuery = Query<Json>(() async => jmap(await session.api.listVendors({'limit': 100})), enabled: scope == 'vendor');

  @override
  void dispose() {
    for (final c in [name, percentage, fixedFee]) {
      c.dispose();
    }
    categoriesQuery.dispose();
    vendorsQuery.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty) return setState(() => formError = 'Name is required.');
    if (scope == 'vendor' && vendorId.isEmpty) return setState(() => formError = 'Select a vendor for vendor scope.');
    if (scope == 'category' && categoryId.isEmpty) return setState(() => formError = 'Select a category for category scope.');
    if (scope == 'vendor_type' && vendorType.isEmpty) return setState(() => formError = 'Select a vendor type.');
    setState(() => formError = '');
    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'scope': scope,
      'percentage': num.tryParse(percentage.text) ?? 0,
      'fixed_fee_rwf': int.tryParse(fixedFee.text) ?? 0,
      'is_active': isActive,
      if (scope == 'vendor') 'vendor_id': vendorId,
      if (scope == 'category') 'category_id': categoryId,
      if (scope == 'vendor_type') 'vendor_type': vendorType,
    };
    final id = jstr(widget.rule?['id']);
    final ok = await run(() => id.isNotEmpty ? session.api.updateCommission(id, payload) : session.api.createCommission(payload));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.rule == null ? 'New commission rule' : 'Edit commission rule',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        BusyButton(label: 'Save rule', busy: busy, onPressed: submit),
      ],
      children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Global platform fee')),
        Row(children: [
          Expanded(
            child: Dropdown<String>(
              label: 'Scope',
              value: scope,
              options: const {'global': 'Global', 'vendor_type': 'Vendor type', 'category': 'Category', 'vendor': 'Vendor'},
              onChanged: (value) {
                setState(() => scope = value);
                vendorsQuery.enabled = value == 'vendor';
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: percentage,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Percentage (%)'),
            ),
          ),
        ]),
        if (scope == 'vendor')
          ListenableBuilder(
            listenable: vendorsQuery,
            builder: (context, _) => Dropdown<String>(
              label: 'Vendor',
              value: vendorId,
              options: {'': 'Select vendor…', for (final v in jlist(vendorsQuery.data?['items'])) jstr(v['id']): jstr(v['name'])},
              onChanged: (value) => setState(() => vendorId = value),
            ),
          ),
        if (scope == 'category')
          ListenableBuilder(
            listenable: categoriesQuery,
            builder: (context, _) => Dropdown<String>(
              label: 'Category',
              value: categoryId,
              options: {'': 'Select category…', for (final c in jlist(categoriesQuery.data?['items'])) jstr(c['id']): jstr(c['name'])},
              onChanged: (value) => setState(() => categoryId = value),
            ),
          ),
        if (scope == 'vendor_type')
          Dropdown<String>(
            label: 'Vendor type',
            value: vendorType,
            options: {'': 'Select vendor type…', for (final t in vendorTypes) t.code: t.label},
            onChanged: (value) => setState(() => vendorType = value),
          ),
        TextField(
          controller: fixedFee,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Fixed fee (RWF)'),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enabled'), value: isActive, onChanged: (value) => setState(() => isActive = value)),
        if (formError.isNotEmpty) Note(formError),
        if (actionError != null) ErrorNote(error: actionError),
      ],
    );
  }
}
