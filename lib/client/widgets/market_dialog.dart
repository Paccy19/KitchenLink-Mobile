import 'package:flutter/material.dart';

import '../client_theme.dart';

Future<T?> showMarketDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => builder(context),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

class MarketDialogCard extends StatelessWidget {
  const MarketDialogCard({
    super.key,
    required this.children,
    this.onClose,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Material(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              elevation: 24,
              shadowColor: const Color(0x40000000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: K.stone100),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.all(wide ? 32 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: crossAxisAlignment,
                      children: children,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: K.stone400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
