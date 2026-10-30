import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../calendar/calendar_model.dart' show monthGridStart;
import '../wallet/month_bar.dart';
import 'space_model.dart';
import 'work_hours.dart';

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

const _holidayKey = 'job.holidayAllowance';

/// A month of the work log: tap a day to mark it worked, off, holiday or sick; hold it for hours.
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
    final allowance = int.tryParse(settings.raw(_holidayKey) ?? '') ?? 25;
    final schedule = WorkSchedule.parse(settings.raw(WorkSchedule.key));
    final today = dateOnly(DateTime.now());
    final weekStart = addDays(today, 1 - today.weekday);
    final weekEnd = addDays(weekStart, 7);
    final start = monthGridStart(_month);
    final yearStart = DateTime(_month.year);
    final yearEnd = DateTime(_month.year + 1);
    // The year, plus the grid's spill-over days and this week (which may cross New Year).
    final from = [yearStart, start, weekStart].reduce((a, b) => a.isBefore(b) ? a : b);
    final to = [yearEnd, addDays(start, 42), weekEnd].reduce((a, b) => a.isAfter(b) ? a : b);
    return StreamBuilder<List<WorkDay>>(
      stream: db.watchWorkDays(from, to),
      builder: (context, snap) {
        final all = snap.data ?? const <WorkDay>[];
        final byDay = {for (final d in all) d.day: d};
        final monthKey = AppDatabase.dayKey(_month).substring(0, 7);
        final month = WorkTotals(all.where((d) => d.day.startsWith(monthKey)));
        final yearDays = all.where((d) => d.day.startsWith('${_month.year}-'));
        final year = WorkTotals(yearDays);
        HoursSummary sum(DateTime a, DateTime b) =>
            HoursSummary.of(from: a, to: b, days: byDay, schedule: schedule, today: today);
        final monthHours = sum(_month, DateTime(_month.year, _month.month + 1));
        final yearHours = sum(yearStart, yearEnd);
        // This week only next to the month it falls in.
        final showWeek = weekStart.isBefore(DateTime(_month.year, _month.month + 1)) && weekEnd.isAfter(_month);
        final weekHours = showWeek ? sum(weekStart, weekEnd) : null;
        return GroupSection(
          title: 'Work days',
          trailing: IconButton(
            tooltip: 'Hours and holidays',
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () => _editSettings(context, schedule, allowance),
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
                  if (w < 5 || addDays(start, w * 7).month == _month.month)
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final day = addDays(start, w * 7 + i);
                                final entry = byDay[AppDatabase.dayKey(day)];
                                return _DayCell(
                                  day: day,
                                  entry: entry,
                                  inMonth: day.month == _month.month,
                                  today: day == today,
                                  workday: schedule.forDay(day) > 0,
                                  onTap: () => _cycle(day, entry),
                                  onLongPress: () => _editDay(context, day, entry, schedule.forDay(day)),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                const SizedBox(height: 10),
                Text(
                  'Tap a day to switch between worked, from home, off, holiday and sick. '
                  'Hold it to add hours, times or a public holiday.',
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _HoursPanel(
                  monthName: DateFormat('MMMM').format(_month),
                  month: monthHours,
                  week: weekHours,
                  color: widget.color,
                  schedule: schedule,
                  onSettings: () => _editSettings(context, schedule, allowance),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Count('Worked', '${month.worked}', workStatusColors['work']!, null),
                    _Count('Off', '${month.of('off')}', workStatusColors['off']!, null),
                    _Count(
                      'Holiday',
                      '${month.of('holiday')}',
                      workStatusColors['holiday']!,
                      month.of('public') > 0 ? '+${month.of('public')} public' : null,
                    ),
                    _Count('Sick', '${month.of('sick')}', workStatusColors['sick']!, null),
                  ].expand((w) => [const SizedBox(width: 8), Expanded(child: w)]).skip(1).toList(),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    'In ${_month.year}: ${year.worked} ${year.worked == 1 ? 'day' : 'days'} worked'
                    '${yearHours.worked > 0 ? ' (${formatHours(yearHours.worked)} hours)' : ''}, '
                    '${year.of('holiday')} of $allowance holidays used, ${allowance - year.of('holiday')} left. '
                    '${year.of('sick')} sick ${year.of('sick') == 1 ? 'day' : 'days'}'
                    '${year.of('public') > 0 ? ', ${year.of('public')} public ${year.of('public') == 1 ? 'holiday' : 'holidays'}' : ''}.'
                    '${yearHours.expectedToDate > 0 || yearHours.worked > 0 ? ' Balance so far: ${_balanceWords(yearHours.balance)}.' : ''}',
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

  void _cycle(DateTime day, WorkDay? entry) {
    final i = entry == null ? -1 : workStatuses.indexOf(entry.status);
    final next = i + 1 >= workStatuses.length ? null : workStatuses[i + 1];
    context.db.setWorkDay(
      day,
      next,
      hours: isWorkStatus(next) ? entry?.hours : null,
      note: next == null ? '' : entry?.note ?? '',
    );
  }

  Future<void> _editDay(BuildContext context, DateTime day, WorkDay? entry, double base) async {
    final db = context.db;
    final result = await showModalBottomSheet<_DayResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DaySheet(day: day, entry: entry, base: base),
    );
    if (result == null) return;
    await db.setWorkDay(day, result.status, hours: result.hours, note: result.note);
  }

  Future<void> _editSettings(BuildContext context, WorkSchedule schedule, int allowance) async {
    final settings = context.settings;
    final result = await showModalBottomSheet<(WorkSchedule, int)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JobSettingsSheet(schedule: schedule, allowance: allowance),
    );
    if (result == null) return;
    await settings.setRaw(WorkSchedule.key, result.$1.encode());
    await settings.setRaw(_holidayKey, '${result.$2}');
  }
}

String _balanceWords(double h) => h.abs() < 0.005
    ? 'even'
    : h > 0
    ? '${signedHours(h)} overtime'
    : '${formatHours(-h)} h owed';

/// One square of the month: the date, its status colour and, quietly, its hours.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.entry,
    required this.inMonth,
    required this.today,
    required this.workday,
    required this.onTap,
    required this.onLongPress,
  });
  final DateTime day;
  final WorkDay? entry;
  final bool inMonth;
  final bool today;
  final bool workday;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final status = entry?.status;
    final color = workStatusColors[status];
    final hours = isWorkStatus(status) ? entry!.hours : null;
    final ink = color != null ? Colors.white : (inMonth ? p.ink : p.muted.withValues(alpha: 0.5));
    // Days the contract has no hours on sit back a little, so the working week stands out.
    final fill =
        color?.withValues(alpha: inMonth ? 0.9 : 0.35) ??
        (inMonth ? (workday ? p.raised : p.raised.withValues(alpha: 0.45)) : Colors.transparent);
    return Semantics(
      button: true,
      label: [
        DateFormat('d MMMM').format(day),
        if (status != null) workStatusLabels[status] ?? status,
        if (hours != null) '${formatHours(hours)} hours',
      ].join(', '),
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                decoration: today
                    ? BoxDecoration(
                        border: Border.all(color: p.ink, width: 1.5),
                        borderRadius: BorderRadius.circular(9),
                      )
                    : null,
                padding: const EdgeInsets.all(2),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.1,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                          color: ink,
                        ),
                      ),
                      if (hours != null)
                        Text(
                          '${formatHours(hours)}h',
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: ink.withValues(alpha: 0.78),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The month's hours against the contract, this week's, and what it takes to get there.
class _HoursPanel extends StatelessWidget {
  const _HoursPanel({
    required this.monthName,
    required this.month,
    required this.week,
    required this.color,
    required this.schedule,
    required this.onSettings,
  });
  final String monthName;
  final HoursSummary month;
  final HoursSummary? week;
  final Color color;
  final WorkSchedule schedule;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = month;
    final balanceColor = m.balance > 0.005 ? p.positive : (m.balance < -0.005 ? p.danger : p.ink);
    final logged = m.expectedToDate > 0 || m.worked > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hours in $monthName',
            style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(logged ? signedHours(m.balance) : '–', style: numeralStyle(30, color: balanceColor)),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  !logged
                      ? 'nothing logged yet'
                      : m.balance > 0.005
                      ? 'overtime so far'
                      : (m.balance < -0.005 ? 'owed so far' : 'right on target so far'),
                  style: TextStyle(color: p.muted, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HoursBar(worked: m.worked, planned: m.planned, expected: m.expected, color: color),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Legend(color: color, text: '${formatHours(m.worked)} h worked'),
              if (m.planned > 0)
                _Legend(color: color.withValues(alpha: 0.4), text: '${formatHours(m.planned)} h planned'),
              _Legend(outline: p.muted, text: '${formatHours(m.expected)} h expected'),
            ],
          ),
          const SizedBox(height: 10),
          _Advice(summary: m, period: 'the month'),
          if (m.unloggedPast > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${m.unloggedPast} earlier ${m.unloggedPast == 1 ? 'workday is' : 'workdays are'} not logged '
              'and left out. Tap ${m.unloggedPast == 1 ? 'it' : 'them'} to count ${m.unloggedPast == 1 ? 'it' : 'them'}.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
            ),
          ],
          if (week != null) ...[const SizedBox(height: 12), _WeekRow(week: week!, color: color)],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: p.muted,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onSettings,
              icon: const Icon(Icons.schedule_rounded, size: 15),
              label: Text(
                'Contract: ${schedule.describe()}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One plain sentence on what is left to do, or how far over it is.
class _Advice extends StatelessWidget {
  const _Advice({required this.summary, required this.period});
  final HoursSummary summary;
  final String period;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = summary;
    final r = s.remaining;
    final (IconData icon, Color tint, String text) = switch (r) {
      _ when s.expected == 0 && s.worked + s.planned == 0 => (
        Icons.event_available_rounded,
        p.muted,
        'No contract hours in $period.',
      ),
      _ when r > 0.01 && s.perOpenDay != null => (
        Icons.trending_up_rounded,
        p.ink,
        '${formatHours(r)} h to go: ${formatHours(roundQuarter(s.perOpenDay!))} h a day on the '
            '${s.openDays == 1 ? 'workday' : '${s.openDays} workdays'} left'
            '${(s.perOpenDay! - s.openHours / s.openDays).abs() < 0.13 ? ', a normal day.' : '.'}',
      ),
      _ when r > 0.01 => (
        Icons.error_outline_rounded,
        p.danger,
        '${formatHours(r)} h short of $period\'s ${formatHours(s.expected)} h, with no workdays left.',
      ),
      _ when r < -0.01 => (
        Icons.check_circle_outline_rounded,
        p.positive,
        s.openDays > 0
            ? 'Target already met: ${formatHours(-r)} h over, with ${s.openDays == 1 ? 'a workday' : '${s.openDays} workdays'} still to come.'
            : 'Target met, ${formatHours(-r)} h over.',
      ),
      _ => (Icons.check_circle_outline_rounded, p.positive, 'Worked and planned hours meet the target exactly.'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: tint),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35))),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.week, required this.color});
  final HoursSummary week;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final w = week;
    final r = w.remaining;
    final String detail;
    if (r > 0.01 && w.perOpenDay != null) {
      detail = w.openDays == 1
          ? '${formatHours(r)} h to go on the last workday'
          : '${formatHours(r)} h to go, ${formatHours(roundQuarter(w.perOpenDay!))} h a day on the ${w.openDays} days left';
    } else if (r > 0.01) {
      detail = '${formatHours(r)} h short';
    } else if (r < -0.01) {
      detail = '${formatHours(-r)} h over target';
    } else {
      detail = 'On target';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'This week',
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              Text(
                '${formatHours(w.worked + w.planned)} / ${formatHours(w.expected)} h',
                style: numeralStyle(16, color: p.ink).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HoursBar(worked: w.worked, planned: w.planned, expected: w.expected, color: color, height: 6),
          const SizedBox(height: 6),
          Text(detail, style: TextStyle(color: p.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Worked, then planned, against what is expected; a tick marks the target once it is passed.
class _HoursBar extends StatelessWidget {
  const _HoursBar({
    required this.worked,
    required this.planned,
    required this.expected,
    required this.color,
    this.height = 10,
  });
  final double worked;
  final double planned;
  final double expected;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final total = [expected, worked + planned, 0.0001].reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Row(
                  children: [
                    Container(width: w * worked / total, color: color),
                    Container(width: w * planned / total, color: color.withValues(alpha: 0.4)),
                  ],
                ),
              ),
              if (worked + planned > expected && expected > 0)
                Positioned(
                  left: (w * expected / total - 1).clamp(0, w - 2),
                  top: -3,
                  bottom: -3,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.text, this.color, this.outline});
  final String text;
  final Color? color;
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: outline == null ? null : Border.all(color: outline!, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12.5, color: p.muted)),
      ],
    );
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
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A short colour bar above the label leaves the narrow tile's width to the word.
          Container(
            width: 14,
            height: 4,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: TextStyle(fontSize: 13, color: p.muted)),
          ),
          const SizedBox(height: 4),
          Text(value, style: numeralStyle(24)),
          if (extra != null)
            Text(
              extra!,
              style: TextStyle(fontSize: 12, color: p.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// A big number with minus and plus on either side.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.unit,
    required this.onChanged,
    this.step = 1,
    this.max = 24,
    this.size = 30,
    this.caption,
  });
  final double value;
  final String unit;
  final ValueChanged<double> onChanged;
  final double step;
  final double max;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = IconButton.styleFrom(
      backgroundColor: p.raised,
      foregroundColor: p.ink,
      disabledBackgroundColor: p.raised.withValues(alpha: 0.5),
      disabledForegroundColor: p.muted.withValues(alpha: 0.5),
      minimumSize: const Size(48, 48),
    );
    return Row(
      children: [
        IconButton(
          style: style,
          tooltip: 'Less',
          onPressed: value <= 0 ? null : () => onChanged((value - step).clamp(0, max)),
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatHours(value),
                        style: numeralStyle(size, color: p.ink),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(fontSize: size * 0.5, color: p.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
            ],
          ),
        ),
        IconButton(
          style: style,
          tooltip: 'More',
          onPressed: value >= max ? null : () => onChanged((value + step).clamp(0, max)),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _DayResult {
  const _DayResult(this.status, this.hours, this.note);
  final String? status;
  final double? hours;
  final String note;
}

/// Everything about one day: what it was, how long, from when to when, and a note.
class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.day, required this.entry, required this.base});
  final DateTime day;
  final WorkDay? entry;
  final double base;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late String _status = widget.entry?.status ?? 'work';
  late double? _hours = widget.entry?.hours;
  late final DayTimes? _saved = DayTimes.parse(widget.entry?.note ?? '');
  late int? _start = _saved?.start;
  late int? _end = _saved?.end;
  late int _break = _saved?.breakMinutes ?? 0;
  late final _note = TextEditingController(text: DayTimes.strip(widget.entry?.note ?? ''));

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DayTimes? get _times => _start != null && _end != null ? DayTimes(_start!, _end!, breakMinutes: _break) : null;

  void _setHours(double h) => setState(() {
    _hours = h;
    _start = null;
    _end = null;
  });

  void _setTimes({int? start, int? end, int? brk}) => setState(() {
    _start = start ?? _start;
    _end = end ?? _end;
    _break = brk ?? _break;
    if (_times != null) _hours = _times!.hours;
  });

  Future<void> _pickTime(bool start) async {
    final current = start
        ? (_start ?? 9 * 60)
        : (_end ?? (_start ?? 9 * 60) + ((widget.base > 0 ? widget.base : 8) * 60).round() + _break);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    _setTimes(start: start ? m : null, end: start ? null : m);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final base = widget.base;
    final future = widget.day.isAfter(dateOnly(DateTime.now()));
    final working = isWorkStatus(_status);
    final shown = _hours ?? base;
    final quick = {4.0, 6.0, 8.0, 9.0, if (base > 0) base}.toList()..sort();
    final String caption;
    if (_hours == null) {
      caption = base > 0 ? 'A normal day' : 'Not a workday. Add hours to count them as overtime.';
    } else if (base > 0 && (_hours! - base).abs() > 0.01) {
      final d = _hours! - base;
      caption = '${formatHours(d.abs())} h ${d > 0 ? 'more' : 'less'} than a normal day';
    } else {
      caption = base > 0 ? 'A normal day' : 'All overtime: not a workday';
    }
    final String statusNote = switch (_status) {
      'holiday' || 'sick' || 'public' =>
        base > 0
            ? 'Counts as a normal ${formatHours(base)} h day, so nothing is owed.'
            : 'Not a workday anyway, so it changes nothing.',
      'off' =>
        base > 0
            ? 'A day off on a workday comes out of your overtime (−${formatHours(base)} h).'
            : 'Not a workday anyway, so it changes nothing.',
      _ => '',
    };
    return _SheetFrame(
      content: [
        Text(DateFormat('EEEE d MMMM').format(widget.day), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          [
            if (future) 'Planning ahead',
            base > 0 ? 'Contract: ${formatHours(base)} h' : 'No contract hours this day',
          ].join(' · '),
          style: TextStyle(color: p.muted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in allWorkStatuses)
              ChoiceChip(
                showCheckmark: false,
                avatar: CircleAvatar(radius: 5, backgroundColor: workStatusColors[s]),
                label: Text(workStatusLabels[s]!),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (working) ...[
          Text(
            future ? 'Hours planned' : 'Hours worked',
            style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _Stepper(value: shown, unit: 'h', step: 0.5, size: 36, caption: caption, onChanged: _setHours),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final h in quick)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text('${formatHours(h)} h'),
                  selected: _hours != null && (_hours! - h).abs() < 0.01,
                  onSelected: (_) => _setHours(h),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'Start',
                  value: _start == null ? null : DayTimes.clock(_start!),
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeButton(
                  label: 'End',
                  value: _end == null ? null : DayTimes.clock(_end!),
                  onTap: () => _pickTime(false),
                ),
              ),
              if (_start != null || _end != null)
                IconButton(
                  tooltip: 'Clear times',
                  onPressed: () => setState(() {
                    _start = null;
                    _end = null;
                  }),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
          if (_start != null && _end != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Break', style: TextStyle(color: p.muted, fontSize: 13)),
                for (final (m, label) in const [(0, 'None'), (30, '30 min'), (45, '45 min'), (60, '1 h')])
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(label),
                    selected: _break == m,
                    onSelected: (_) => _setTimes(brk: m),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Start and end are optional; set both and the hours fill in.',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ],
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(14)),
            child: Text(statusNote, style: const TextStyle(height: 1.35)),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
      ],
      actions: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: widget.entry == null
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, const _DayResult(null, null, '')),
                        child: const Text('Clear day'),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _DayResult(
                _status,
                working ? _hours : null,
                working ? DayTimes.join(_times, _note.text.trim()) : _note.text.trim(),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.raised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: p.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value == null ? label : '$label $value',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value == null ? p.muted : p.ink,
                    fontWeight: value == null ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contract hours (a week spread over chosen days, or set per day) and the holiday allowance.
class _JobSettingsSheet extends StatefulWidget {
  const _JobSettingsSheet({required this.schedule, required this.allowance});
  final WorkSchedule schedule;
  final int allowance;

  @override
  State<_JobSettingsSheet> createState() => _JobSettingsSheetState();
}

class _JobSettingsSheetState extends State<_JobSettingsSheet> {
  late bool _perDay = !widget.schedule.even;
  late double _weekly = widget.schedule.weekly;
  late Set<int> _days = widget.schedule.workdays.isEmpty ? {1, 2, 3, 4, 5} : widget.schedule.workdays;
  late List<double> _hours = [...widget.schedule.hours];
  late int _allowance = widget.allowance;

  static const _names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  WorkSchedule get _schedule => _perDay ? WorkSchedule(_hours) : WorkSchedule.spread(_weekly, _days);

  void _mode(bool perDay) => setState(() {
    if (perDay) {
      _hours = [..._schedule.hours];
    } else {
      _weekly = _hours.fold(0, (a, h) => a + h);
      _days = {
        for (var d = 1; d <= 7; d++)
          if (_hours[d - 1] > 0) d,
      };
      if (_days.isEmpty) _days = {1, 2, 3, 4, 5};
    }
    _perDay = perDay;
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = _schedule;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600),
      ),
    );
    return _SheetFrame(
      content: [
        Text('Hours and holidays', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'What your contract expects, so the work log can tell overtime from hours still to do.',
          style: TextStyle(color: p.muted),
        ),
        const SizedBox(height: 16),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: PillToggle<bool>(
              dense: true,
              options: const [(false, 'Same each day'), (true, 'Per day')],
              value: _perDay,
              onChanged: _mode,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_perDay) ...[
          label('Hours a week'),
          _Stepper(
            value: _weekly,
            unit: 'h',
            max: 80,
            step: 1,
            caption: _days.isEmpty
                ? 'Pick the days you work'
                : '${formatHours(s.hours[_days.first - 1])} h a day over ${_days.length} '
                      '${_days.length == 1 ? 'day' : 'days'}',
            onChanged: (v) => setState(() => _weekly = v),
          ),
          const SizedBox(height: 14),
          label('Days you work'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            children: [
              for (var d = 1; d <= 7; d++)
                _DayToggle(
                  text: _names[d - 1].substring(0, 1),
                  tooltip: _names[d - 1],
                  on: _days.contains(d),
                  onTap: () => setState(() => _days = _days.contains(d) ? (_days.difference({d})) : {..._days, d}),
                ),
            ],
          ),
        ] else ...[
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 96, child: Text(_names[d - 1], overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: _Stepper(
                      value: _hours[d - 1],
                      unit: 'h',
                      step: 0.5,
                      size: 20,
                      onChanged: (v) => setState(() => _hours[d - 1] = v),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            '${formatHours(s.weekly)} h a week in total',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        label('Holidays a year'),
        _Stepper(
          value: _allowance.toDouble(),
          unit: _allowance == 1 ? 'day' : 'days',
          max: 100,
          onChanged: (v) => setState(() => _allowance = v.round()),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How hours add up', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final t in const [
                'A worked day without hours counts as a normal day.',
                'Holidays, sick days and public holidays count as a normal day, so nothing is owed for them.',
                'A day off on a workday comes out of your overtime.',
                'Hours on days after today are planned: they count toward the target, not the balance.',
                'Earlier days you did not log are left out.',
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: TextStyle(color: p.muted)),
                      Expanded(
                        child: Text(t, style: TextStyle(color: p.muted, fontSize: 13, height: 1.35)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      actions: Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => Navigator.pop(context, (_schedule, _allowance)),
          child: const Text('Save'),
        ),
      ),
    );
  }
}

/// A sheet whose content scrolls while its buttons stay in reach at the bottom.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.content, required this.actions});
  final List<Widget> content;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...content, const SizedBox(height: 8)],
            ),
          ),
        ),
        const SizedBox(height: 6),
        actions,
      ],
    ),
  );
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.text, required this.tooltip, required this.on, required this.onTap});
  final String text;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: on,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: on ? p.ink : p.raised,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(fontWeight: FontWeight.w700, color: on ? p.background : p.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
