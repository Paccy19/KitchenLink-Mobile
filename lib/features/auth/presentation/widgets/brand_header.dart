import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The KitchenLink mark with the "Kitchen" app name.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 44.0 : 60.0;
    return Row(children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brown900, AppColors.brown800],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brown900.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(Icons.soup_kitchen_rounded, color: AppColors.creamDeep, size: size * 0.52),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('KitchenLink', style: theme.textTheme.titleLarge?.copyWith(height: 1.1)),
        Text(
          'Kitchen app',
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.secondary),
        ),
      ]),
    ]);
  }
}
