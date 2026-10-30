import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// Previous / month name / next, with a tap on the name to jump to any month
/// and a quick way back to the current one.
class MonthBar extends StatelessWidget {
  const MonthBar({super.key, required this.month, required this.onChanged, this.latest});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  /// The last month that can be shown; null means no limit.
  final DateTime? latest;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final next = DateTime(month.year, month.month + 1);
    final canNext = latest == null || !next.isAfter(latest!);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: p.ink),
              onPressed: () async {
                final picked = await pickMonth(context, month, latest: latest);
                if (picked != null) onChanged(picked);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(DateFormat('MMMM y').format(month), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded, color: p.muted),
              ]),
            ),
          ),
        ),
        if (month != current)
          TextButton(onPressed: () => onChanged(current), child: const Text('Now')),
        IconButton(
          tooltip: 'Next month',
          onPressed: canNext ? () => onChanged(next) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// A compact year-and-months picker.
Future<DateTime?> pickMonth(BuildContext context, DateTime initial, {DateTime? latest}) {
  var year = initial.year;
  return showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final p = Palette.of(context);
      final now = DateTime.now();
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        title: Row(children: [
          IconButton(onPressed: () => setState(() => year--), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(child: Text('$year', textAlign: TextAlign.center)),
          IconButton(
            onPressed: latest != null && year >= latest.year ? null : () => setState(() => year++),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        content: SizedBox(
          width: 300,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            childAspectRatio: 2.1,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var m = 1; m <= 12; m++)
                Builder(builder: (context) {
                  final d = DateTime(year, m);
                  final selected = d.year == initial.year && d.month == initial.month;
                  final isNow = d.year == now.year && d.month == now.month;
                  final disabled = latest != null && d.isAfter(latest);
                  return Material(
                    color: selected ? TileColors.finance : (isNow ? p.raised : Colors.transparent),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: disabled ? null : () => Navigator.of(context).pop(d),
                      child: Center(
                        child: Text(
                          DateFormat.MMM().format(d),
                          style: TextStyle(
                            color: selected ? Colors.white : (disabled ? p.muted.withValues(alpha: 0.5) : p.ink),
                            fontWeight: selected || isNow ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ],
      );
    }),
  );
}
