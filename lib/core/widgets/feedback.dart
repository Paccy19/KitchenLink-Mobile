import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// Floating messages and the one place that turns a failure into text.

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF7FD4A0), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ]),
      ),
    );
}

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: theme.colorScheme.error,
        duration: const Duration(seconds: 5),
        content: Row(children: [
          Icon(
            error is ApiException && error.isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
            color: theme.colorScheme.onError,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(errorMessage(error), style: TextStyle(color: theme.colorScheme.onError))),
        ]),
      ),
    );
}

/// Shows why an action failed. A write refused because the documents are
/// still under review gets its own explanation instead of an error bar.
Future<void> reportFailure(BuildContext context, Object error) async {
  if (!context.mounted) return;
  if (error is ApiException && error.isPendingReview) {
    await showPendingReviewDialog(context);
  } else {
    showError(context, error);
  }
}

/// Runs a write and reports the outcome: returns its result, or null after
/// showing the failure. Used for every button that talks to the backend.
/// Nothing is ever reported as saved unless the call succeeded.
Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) showSuccess(context, success);
    return result;
  } catch (error) {
    if (context.mounted) await reportFailure(context, error);
    return null;
  }
}

Future<void> showPendingReviewDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_rounded, size: 32),
        title: const Text('Documents under review'),
        content: const Text(
          'Your verification documents are still being reviewed. You can use this part of the app '
          'once your account is approved. You can already build your menu while you wait.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );

/// Asks the vendor to confirm. Returns true when they agree.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  minimumSize: const Size(0, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
