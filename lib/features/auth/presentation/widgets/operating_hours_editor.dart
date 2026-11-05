import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../models/vendor_account.dart';

/// Seven rows, Monday to Sunday: open or closed, with opening and closing time.
class OperatingHoursEditor extends StatelessWidget {
  const OperatingHoursEditor({super.key, required this.hours, required this.onChanged, this.enabled = true});

  final List<OperatingHour> hours;
  final ValueChanged<List<OperatingHour>> onChanged;
  final bool enabled;

  void _update(int index, OperatingHour hour) {
    final next = [...hours];
    next[index] = hour;
    onChanged(next);
  }

  Future<void> _pick(BuildContext context, int index, {required bool opening}) async {
    final hour = hours[index];
    final current = _parse(opening ? hour.openTime : hour.closeTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    _update(index, opening ? hour.copyWith(openTime: text) : hour.copyWith(closeTime: text));
  }

  static TimeOfDay _parse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      for (var i = 0; i < hours.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 96,
              child: Text(humanize(hours[i].day), style: theme.textTheme.titleSmall),
            ),
            Switch(
              value: !hours[i].isClosed,
              onChanged: enabled ? (open) => _update(i, hours[i].copyWith(isClosed: !open)) : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: hours[i].isClosed
                  ? Text('Closed', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                  : Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                          onPressed: enabled ? () => _pick(context, i, opening: true) : null,
                          child: Text(hours[i].openTime),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                          onPressed: enabled ? () => _pick(context, i, opening: false) : null,
                          child: Text(hours[i].closeTime),
                        ),
                      ),
                    ]),
            ),
          ]),
        ),
    ]);
  }
}
