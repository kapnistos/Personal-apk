import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../calendar/calendar_model.dart' show monthGridStart;
import '../wallet/month_bar.dart';
import 'space_model.dart';

/// Totals for a set of logged days.
class WorkTotals {
  WorkTotals(Iterable<WorkDay> days) {
    for (final d in days) {
      count[d.status] = (count[d.status] ?? 0) + 1;
      if (d.status == 'work' || d.status == 'remote') hours += d.hours ?? 0;
    }
  }

  final count = <String, int>{};
  double hours = 0;

  int get worked => (count['work'] ?? 0) + (count['remote'] ?? 0);
  int of(String status) => count[status] ?? 0;
}

/// A month of the work log: tap a day to mark it worked, off, holiday or sick.
class WorkLogCard extends StatefulWidget {
  const WorkLogCard({super.key, required this.color});
  final Color color;

  @override
  State<WorkLogCard> createState() => _WorkLogCardState();
}

class _WorkLogCardState extends State<WorkLogCard> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final settings = context.settings;
    final allowance = int.tryParse(settings.raw('job.holidayAllowance') ?? '') ?? 25;
    final yearStart = DateTime(_month.year);
    return StreamBuilder<List<WorkDay>>(
      stream: db.watchWorkDays(yearStart, DateTime(_month.year + 1)),
      builder: (context, snap) {
        final all = snap.data ?? const <WorkDay>[];
        final byDay = {for (final d in all) d.day: d};
        final monthKey = AppDatabase.dayKey(_month).substring(0, 7);
        final month = WorkTotals(all.where((d) => d.day.startsWith(monthKey)));
        final year = WorkTotals(all);
        final start = monthGridStart(_month);
        final today = dateOnly(DateTime.now());
        return GroupSection(
          title: 'Work days',
          trailing: IconButton(
            tooltip: 'Holiday allowance',
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () => _editAllowance(context, allowance),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonthBar(month: _month, onChanged: (m) => setState(() => _month = m)),
                Row(
                  children: [
                    for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var w = 0; w < 6; w++)
                  if (w < 5 || DateTime(start.year, start.month, start.day + w * 7).month == _month.month)
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final day = DateTime(start.year, start.month, start.day + w * 7 + i);
                                final entry = byDay[AppDatabase.dayKey(day)];
                                final inMonth = day.month == _month.month;
                                final color = entry == null ? null : workStatusColors[entry.status];
                                return AspectRatio(
                                  aspectRatio: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Material(
                                      color:
                                          color?.withValues(alpha: inMonth ? 0.9 : 0.35) ??
                                          (inMonth ? p.raised : Colors.transparent),
                                      borderRadius: BorderRadius.circular(9),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(9),
                                        onTap: () => _cycle(day, entry),
                                        onLongPress: () => _editDay(context, day, entry),
                                        child: Container(
                                          decoration: day == today
                                              ? BoxDecoration(
                                                  border: Border.all(color: p.ink, width: 1.5),
                                                  borderRadius: BorderRadius.circular(9),
                                                )
                                              : null,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${day.day}',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: day == today ? FontWeight.w700 : FontWeight.w500,
                                              color: color != null
                                                  ? Colors.white
                                                  : (inMonth ? p.ink : p.muted.withValues(alpha: 0.5)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                const SizedBox(height: 10),
                Text(
                  'Tap a day to switch between worked, from home, off, holiday and sick. Hold it to add hours.',
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Count(
                      'Worked',
                      '${month.worked}',
                      workStatusColors['work']!,
                      month.hours > 0 ? '${_h(month.hours)} h' : null,
                    ),
                    _Count('Off', '${month.of('off')}', workStatusColors['off']!, null),
                    _Count('Holiday', '${month.of('holiday')}', workStatusColors['holiday']!, null),
                    _Count('Sick', '${month.of('sick')}', workStatusColors['sick']!, null),
                  ].expand((w) => [const SizedBox(width: 8), Expanded(child: w)]).skip(1).toList(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    'In ${_month.year}: ${year.worked} days worked'
                    '${year.hours > 0 ? ' (${_h(year.hours)} hours)' : ''}, '
                    '${year.of('holiday')} of $allowance holidays used, ${allowance - year.of('holiday')} left. '
                    '${year.of('sick')} sick ${year.of('sick') == 1 ? 'day' : 'days'}.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _h(double h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  void _cycle(DateTime day, WorkDay? entry) {
    final i = entry == null ? -1 : workStatuses.indexOf(entry.status);
    final next = i + 1 >= workStatuses.length ? null : workStatuses[i + 1];
    context.db.setWorkDay(day, next, hours: next == 'work' || next == 'remote' ? entry?.hours : null);
  }

  Future<void> _editDay(BuildContext context, DateTime day, WorkDay? entry) async {
    final db = context.db;
    final hours = TextEditingController(text: entry?.hours == null ? '' : _h(entry!.hours!));
    final note = TextEditingController(text: entry?.note ?? '');
    var status = entry?.status ?? 'work';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(DateFormat('EEEE d MMMM').format(day)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in workStatuses)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(workStatusLabels[s]!),
                      selected: status == s,
                      onSelected: (_) => setState(() => status = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (status == 'work' || status == 'remote')
                TextField(
                  controller: hours,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hours', hintText: '8'),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'clear'), child: const Text('Clear day')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == 'clear') await db.setWorkDay(day, null);
    if (result == 'save') {
      await db.setWorkDay(day, status, hours: double.tryParse(hours.text.replaceAll(',', '.')), note: note.text.trim());
    }
  }

  Future<void> _editAllowance(BuildContext context, int current) async {
    final c = TextEditingController(text: '$current');
    final settings = context.settings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Holidays per year'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final v = int.tryParse(c.text.trim());
    if (ok == true && v != null) await settings.setRaw('job.holidayAllowance', '$v');
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color, this.extra);
  final String label;
  final String value;
  final Color color;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 4, backgroundColor: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: p.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: numeralStyle(24)),
          if (extra != null) Text(extra!, style: TextStyle(fontSize: 12.5, color: p.muted)),
        ],
      ),
    );
  }
}
