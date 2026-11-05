import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/server_address.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'forms.dart';

/// Opens the "Server address" sheet. Returns true when the address changed.
Future<bool> showServerAddressSheet(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ServerAddressSheet(),
  );
  return changed ?? false;
}

/// A small "server" button for the sign-in and registration screens.
class ServerAddressButton extends ConsumerWidget {
  const ServerAddressButton({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: 'Server address',
        icon: const Icon(Icons.dns_rounded),
        onPressed: () async {
          final changed = await showServerAddressSheet(context);
          if (changed) onChanged?.call();
        },
      );
}

class _ServerAddressSheet extends ConsumerStatefulWidget {
  const _ServerAddressSheet();

  @override
  ConsumerState<_ServerAddressSheet> createState() => _ServerAddressSheetState();
}

class _ServerAddressSheetState extends ConsumerState<_ServerAddressSheet> {
  late final _controller = TextEditingController(text: ref.read(serverAddressProvider));
  bool _busy = false;
  bool _changed = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Saves the address, then asks the server for its health check.
  Future<void> _saveAndTest() async {
    final url = normalizeApiBaseUrl(_controller.text);
    if (url == null) {
      setState(() {
        _ok = false;
        _result = 'Enter a web address, for example 192.168.1.20:4000';
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    await ref.read(serverAddressProvider.notifier).apply(url);
    _changed = true;
    _controller.text = url;
    try {
      await ref.read(apiClientProvider).get('/health', auth: false);
      if (mounted) {
        setState(() {
          _ok = true;
          _result = 'Connected to $url';
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _ok = false;
          _result = error.isNetwork
              ? "Can't reach $url. Check the address, that the server is running, and that this phone is on the same Wi-Fi as the computer."
              : 'The server answered with an error: ${error.message}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    await ref.read(serverAddressProvider.notifier).apply(null);
    _changed = true;
    if (!mounted) return;
    setState(() {
      _controller.text = AppConfig.defaultApiBaseUrl;
      _ok = false;
      _result = 'Back to the built-in address.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = toneColors(context, _ok ? Tone.success : Tone.danger);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Server address', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Where is the KitchenLink backend? On a phone, use your computer\'s Wi-Fi address, for example '
              '192.168.1.20:4000. The Android emulator uses 10.0.2.2:4000. "localhost" never works from a phone.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Server address',
              controller: _controller,
              keyboardType: TextInputType.url,
              prefix: const Icon(Icons.dns_rounded),
              onSubmitted: (_) => _saveAndTest(),
            ),
            if (_result != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: colors.foreground, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_result!, style: TextStyle(color: colors.foreground))),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _saveAndTest,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.wifi_find_rounded),
              label: Text(_busy ? 'Testing…' : 'Save and test'),
            ),
            TextButton(onPressed: _busy ? null : _reset, child: const Text('Use the built-in address')),
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context, _changed), child: const Text('Close')),
          ]),
        ),
      ),
    );
  }
}
