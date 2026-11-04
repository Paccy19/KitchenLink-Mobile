import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../application/session.dart';
import '../models/vendor_account.dart';
import 'widgets/brand_header.dart';

/// Shown while the stored session is checked at launch.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BrandHeader(),
            SizedBox(height: 28),
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
          ]),
        ),
      );
}

/// A token is stored but the server could not be reached to check it.
/// The vendor stays signed in; they can retry or sign out.
class ConnectionProblemScreen extends ConsumerWidget {
  const ConnectionProblemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Can't reach KitchenLink",
            message: 'Check your internet connection. You are still signed in; we will pick up where you left off.',
            action: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 220,
                child: AsyncButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: () => ref.read(sessionProvider.notifier).restore(),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
                child: const Text('Sign out'),
              ),
            ]),
          ),
        ),
      );
}

/// The account is suspended or rejected: the backend's reason and how to
/// reach support. Nothing here is invented.
class BlockedAccountScreen extends ConsumerWidget {
  const BlockedAccountScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      showError(context, 'Could not open ${uri.scheme == 'tel' ? 'the phone app' : 'your email app'}.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final block = ref.watch(sessionProvider).block;
    if (block == null) return const SplashScreen();
    final suspended = block.isSuspended;
    final danger = toneColors(context, Tone.danger);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const BrandHeader(compact: true),
              const SizedBox(height: 32),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: danger.background, shape: BoxShape.circle),
                  child: Icon(Icons.block_rounded, size: 38, color: danger.foreground),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                suspended ? 'Your account is suspended' : 'Your application was rejected',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                block.message.isNotEmpty
                    ? block.message
                    : "You can't use the kitchen app until this is resolved.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (suspended && block.suspendedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Suspended on ${formatDate(block.suspendedAt)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 22),
              AppCard(
                color: danger.background,
                borderColor: Colors.transparent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('REASON',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: danger.foreground, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(
                    block.reason.isNotEmpty
                        ? block.reason
                        : 'No reason was given. Contact the support team for details.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: danger.foreground),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Text(
                'To solve this, contact our support team. They will review your account with you.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (block.supportPhone.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _open(context, Uri(scheme: 'tel', path: block.supportPhone.replaceAll(' ', ''))),
                  icon: const Icon(Icons.call_rounded),
                  label: Text('Call support: ${block.supportPhone}'),
                ),
              if (block.supportEmail.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _open(context, Uri(scheme: 'mailto', path: block.supportEmail)),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: Text(block.supportEmail),
                ),
              ],
              if (block.supportPhone.isEmpty && block.supportEmail.isEmpty)
                const NoteBox(
                  message: 'Support contact details were not provided. Please contact KitchenLink directly.',
                  tone: Tone.warning,
                ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () {
                  ref.read(sessionProvider.notifier).backToLogin();
                  context.go('/login');
                },
                child: const Text('Back to sign in'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Explains the pending verification state; opened from the banner.
Future<void> showPendingExplanation(BuildContext context, VendorAccount vendor) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(Icons.hourglass_top_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Your documents are under review', style: theme.textTheme.titleLarge)),
              ]),
              const SizedBox(height: 12),
              Text(
                'An admin is checking the verification documents you uploaded for ${vendor.name}. '
                'You will be able to open your store, manage orders, withdraw money and change your settings '
                'as soon as your account is approved.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text('What you can do now', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              const _Bullet('Build your menu: add dishes, photos and prices.'),
              const _Bullet('Browse your dashboard and account details.'),
              const _Bullet('Contact support if the review takes long.'),
              if (vendor.documents.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Submitted documents (${vendor.documents.length})', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final document in vendor.documents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(document.fileType == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded),
                    title: Text(document.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Uploaded ${formatDate(document.uploadedAt)}'),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ]),
          ),
        );
      },
    );

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 6)),
          Expanded(child: Text(text)),
        ]),
      );
}
