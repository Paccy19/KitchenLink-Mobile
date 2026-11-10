import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/components.dart';
import '../../features/wallet/application/wallet_providers.dart';
import '../../features/wallet/models/wallet.dart';
import '../application/deliveries.dart';
import '../models/delivery.dart';
import 'widgets/motion.dart';
import 'widgets/trip_widgets.dart';

/// Earnings & wallet: the balance and how to withdraw it first, then what
/// each delivery paid.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wallet = ref.watch(walletProvider);
    final earnings = ref.watch(earningsProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> refresh() async {
      await Future.wait([
        ref.read(walletProvider.notifier).reload(silent: false),
        ref.read(earningsProvider.notifier).reload(silent: false),
      ]).catchError((_) => const <void>[]);
    }

    if (wallet.hasError && !wallet.hasValue) {
      return Scaffold(
        body: SafeArea(child: ErrorState(error: wallet.error!, onRetry: refresh)),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, bottom + 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Earnings',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
            ),
            const SizedBox(height: 14),
            _Balance(wallet: wallet.value, earnings: earnings.value),
            const SizedBox(height: 12),
            _Summary(earnings: earnings.value),
            if (wallet.value?.withdrawals.isNotEmpty ?? false) ...[
              const GroupLabel('Withdrawals'),
              _Withdrawals(items: wallet.value!.withdrawals),
            ],
            GroupLabel(
              'Recent deliveries',
              trailing: TextButton(onPressed: () => context.push('/history'), child: const Text('All deliveries')),
            ),
            _Breakdown(earnings: earnings),
          ],
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.wallet, required this.earnings});

  final Wallet? wallet;
  final DriverEarnings? earnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = wallet;
    final available = w?.availableBalanceRwf ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DriverColors.brand, DriverColors.moss950],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'AVAILABLE TO WITHDRAW',
          style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 0.8),
        ),
        const SizedBox(height: 6),
        if (w == null)
          const SizedBox(height: 40, child: SkeletonBox(width: 160, height: 34))
        else
          MoneyFigure(available, size: 40, color: Colors.white),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _Pill(label: 'Processing', value: formatRwf(w?.processingRwf ?? 0)),
          _Pill(label: 'Withdrawn', value: formatRwf(w?.withdrawnRwf ?? 0)),
        ]),
        const SizedBox(height: 18),
        PressScale(
          enabled: available > 0,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: DriverColors.moss900,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.18),
                disabledForegroundColor: Colors.white60,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: available > 0 ? () => context.push('/earnings/withdraw') : null,
              icon: const Icon(Icons.arrow_outward_rounded),
              label: Text(available > 0 ? 'Withdraw' : 'Nothing to withdraw yet'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'To mobile money or a bank. Usually sent within 24 hours; a failed payout returns to your balance.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70, height: 1.35),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: Colors.white70)),
          TextSpan(text: value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.earnings});

  final DriverEarnings? earnings;

  @override
  Widget build(BuildContext context) {
    final e = earnings;
    return Row(children: [
      Expanded(
        child: StatCard(
          icon: Icons.today_rounded,
          label: 'Today',
          value: e == null ? '—' : formatRwf(e.todayRwf),
          caption: e == null ? null : '${e.todayDeliveries} deliver${e.todayDeliveries == 1 ? 'y' : 'ies'}',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: StatCard(
          icon: Icons.trending_up_rounded,
          tone: Tone.success,
          label: 'All time',
          value: e == null ? '—' : formatRwf(e.totalRwf),
          caption: e == null ? null : 'You keep ${e.sharePercent.round()}% of each fee',
        ),
      ),
    ]);
  }
}

class _Withdrawals extends StatelessWidget {
  const _Withdrawals({required this.items});

  final List<Withdrawal> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(indent: 16, endIndent: 16, color: theme.colorScheme.outlineVariant),
          _WithdrawalRow(item: items[i]),
        ],
      ]),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.item});

  final Withdrawal item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, label) = switch (item.status) {
      'completed' => (Tone.success, 'Paid'),
      'failed' => (Tone.danger, 'Failed · refunded'),
      _ => (Tone.warning, 'Processing'),
    };
    final detail = [
      formatDateTime(item.createdAt),
      if (item.isCompleted && item.reference.isNotEmpty) 'ref ${item.reference}',
      if (item.isFailed && (item.failureReason ?? '').isNotEmpty) item.failureReason!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${item.methodLabel} · ${item.destination}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '−${formatRwf(item.amountRwf)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          StatusChip(label: label, tone: tone, dense: true),
        ]),
      ]),
    );
  }
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown({required this.earnings});

  final AsyncValue<DriverEarnings> earnings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (earnings.hasError && !earnings.hasValue) {
      return ErrorState(error: earnings.error!, onRetry: () => ref.read(earningsProvider.notifier).reload(silent: false));
    }
    final list = earnings.value?.deliveries;
    if (list == null) return const SkeletonList(count: 3, height: 64);
    if (list.isEmpty) {
      return AppCard(
        child: Text(
          'Completed deliveries and what each one paid will appear here.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) Divider(indent: 16, endIndent: 16, color: theme.colorScheme.outlineVariant),
          DeliveryRow(delivery: list[i]),
        ],
      ]),
    );
  }
}

/// One past delivery: kitchen → drop-off, when, and what it paid.
class DeliveryRow extends StatelessWidget {
  const DeliveryRow({super.key, required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = delivery;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              d.vendor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${formatDateTime(d.completedAt ?? d.cancelledAt ?? d.createdAt)} · ${d.dropoff.address.isEmpty ? 'customer' : d.dropoff.address}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        if (d.wasCancelled)
          StatusChip(label: d.statusLabel, tone: Tone.neutral, dense: true)
        else
          Text(
            '+${formatRwf(d.earningsRwf)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ]),
    );
  }
}
