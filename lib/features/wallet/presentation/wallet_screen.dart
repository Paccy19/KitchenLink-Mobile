import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/forms.dart';
import '../../auth/application/session.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../application/wallet_providers.dart';
import '../models/wallet.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final canAct = ref.watch(canActProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet'), actions: const [NotificationBellButton()]),
      body: AsyncBody<Wallet>(
        value: wallet,
        onRefresh: () => ref.read(walletProvider.notifier).reload(silent: false),
        builder: (context, data) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _BalanceCard(wallet: data, canAct: canAct),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatCard(label: 'Total sales', value: formatRwf(data.totalSalesRwf), icon: Icons.bar_chart_rounded)),
              const SizedBox(width: 12),
              Expanded(child: StatCard(label: 'Withdrawn', value: formatRwf(data.withdrawnRwf), icon: Icons.north_east_rounded, tone: Tone.info)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatCard(label: 'Pending', value: formatRwf(data.pendingBalanceRwf), icon: Icons.hourglass_bottom_rounded, tone: Tone.warning, caption: 'Orders in progress')),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Commission',
                  value: '${data.commissionPercent.toStringAsFixed(data.commissionPercent % 1 == 0 ? 0 : 1)}%',
                  icon: Icons.percent_rounded,
                  tone: Tone.neutral,
                  caption: 'Taken from food sales',
                ),
              ),
            ]),
            const SectionHeader('Withdrawal history'),
            if (data.withdrawals.isEmpty)
              AppCard(
                child: Text('You have not withdrawn any money yet.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              for (final withdrawal in data.withdrawals)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _WithdrawalTile(withdrawal: withdrawal)),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.canAct});

  final Wallet wallet;
  final bool canAct;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brown900, AppColors.brown800],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Available balance', style: TextStyle(color: AppColors.sand, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatRwf(wallet.availableBalanceRwf),
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.creamDeep,
              foregroundColor: AppColors.brown900,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white60,
            ),
            onPressed: canAct ? () => context.push('/wallet/withdraw') : null,
            icon: const Icon(Icons.north_east_rounded),
            label: const Text('Withdraw money'),
          ),
          if (!canAct)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Withdrawals unlock once your account is approved.', style: TextStyle(color: AppColors.sand, fontSize: 12)),
            ),
        ]),
      );
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.withdrawal});

  final Withdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, label) = switch (withdrawal.status) {
      'completed' => (Tone.success, 'Paid'),
      'failed' => (Tone.danger, 'Failed'),
      _ => (Tone.warning, 'Processing'),
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(formatRwf(withdrawal.amountRwf), style: theme.textTheme.titleMedium)),
          StatusChip(label: label, tone: tone, dense: true),
        ]),
        const SizedBox(height: 6),
        Text(
          [withdrawal.methodLabel, withdrawal.destination].where((part) => part.isNotEmpty).join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          [if (withdrawal.reference.isNotEmpty) 'Ref ${withdrawal.reference}', formatDateTime(withdrawal.createdAt)].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (withdrawal.isFailed) ...[
          const SizedBox(height: 8),
          NoteBox(
            tone: Tone.danger,
            icon: Icons.undo_rounded,
            message: withdrawal.failureReason == null || withdrawal.failureReason!.isEmpty
                ? 'This payout failed and the money went back to your balance.'
                : '${withdrawal.failureReason} The money went back to your balance.',
          ),
        ],
      ]),
    );
  }
}
