import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/reminders.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const habitColor = Color(0xFFD9822B);

const habitIcons = <String, IconData>{
  'check': Icons.check_rounded,
  'book': Icons.menu_book_rounded,
  'gym': Icons.fitness_center_rounded,
  'run': Icons.directions_run_rounded,
  'water': Icons.water_drop_rounded,
  'sleep': Icons.bedtime_rounded,
  'study': Icons.school_rounded,
  'meditate': Icons.self_improvement_rounded,
  'food': Icons.restaurant_rounded,
  'walk': Icons.directions_walk_rounded,
  'language': Icons.translate_rounded,
  'code': Icons.code_rounded,
  'money': Icons.savings_rounded,
  'call': Icons.call_rounded,
  'clean': Icons.cleaning_services_rounded,
  'pill': Icons.medication_rounded,
};

const habitColors = [
  0xFFD9822B, 0xFF1F7A5A, 0xFF3A78C9, 0xFF6650AE, 0xFFC0563F, 0xFF2D8C9E, 0xFFB5487A, 0xFFCF9418, //
];

/// Ideas to start from.
const habitSuggestions = [
  ('Read 20 minutes', 'book'),
  ('Gym', 'gym'),
  ('Drink 2 litres of water', 'water'),
  ('Study', 'study'),
  ('In bed by 23:30', 'sleep'),
  ('Walk 8,000 steps', 'walk'),
  ('Practise a language', 'language'),
  ('No takeaway', 'food'),
];

bool habitDueOn(Habit h, DateTime d) => h.days.length != 7 || h.days[d.weekday - 1] == '1';

/// Days in a row the habit was done (counting back from today, or yesterday if
/// today isn't done yet). Days it doesn't apply to don't break the streak.
int habitStreak(Habit h, Set<String> done, {DateTime? now}) {
  var d = dateOnly(now ?? DateTime.now());
  if (!done.contains(AppDatabase.dayKey(d))) d = addDays(d, -1);
  var n = 0;
  for (var i = 0; i < 400; i++) {
    if (habitDueOn(h, d)) {
      if (!done.contains(AppDatabase.dayKey(d))) break;
      n++;
    }
    d = addDays(d, -1);
  }
  return n;
}

/// The longest run of done days the habit ever had, skipping days it doesn't apply to.
int habitBestStreak(Habit h, Set<String> done, {DateTime? now}) {
  if (done.isEmpty) return 0;
  final first = DateTime.parse(done.reduce((a, b) => a.compareTo(b) < 0 ? a : b));
  final today = dateOnly(now ?? DateTime.now());
  var best = 0, run = 0;
  for (var d = first; !d.isAfter(today); d = addDays(d, 1)) {
    if (!habitDueOn(h, d)) continue;
    if (done.contains(AppDatabase.dayKey(d))) {
      run++;
      if (run > best) best = run;
    } else if (d != today) {
      run = 0;
    }
  }
  return best;
}

class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final today = dateOnly(DateTime.now());
    final from = addDays(today, -400);
    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editHabit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New habit'),
      ),
      body: StreamBuilder<List<Habit>>(
        stream: db.watchHabits(),
        builder: (context, hSnap) => StreamBuilder<List<HabitCheck>>(
          stream: db.watchHabitChecks(from),
          builder: (context, cSnap) {
            final habits = hSnap.data ?? const <Habit>[];
            final byHabit = <int, Set<String>>{};
            for (final c in cSnap.data ?? const <HabitCheck>[]) {
              (byHabit[c.habitId] ??= {}).add(c.day);
            }
            if (habits.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  const EmptyState(
                    icon: Icons.local_fire_department_outlined,
                    title: 'Build a habit',
                    message: 'Tick it off each day and watch the streak grow. Pick one to start:',
                  ),
                  ContentWidth(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (name, icon) in habitSuggestions)
                          ActionChip(
                            avatar: Icon(habitIcons[icon], size: 18),
                            label: Text(name),
                            onPressed: () => db.saveHabit(
                              HabitsCompanion.insert(
                                name: name,
                                icon: Value(icon),
                                color: habitColors[habitSuggestions.indexOf((name, icon)) % habitColors.length],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }
            final dueToday = habits.where((h) => habitDueOn(h, today)).toList();
            final doneToday = dueToday.where((h) => byHabit[h.id]?.contains(AppDatabase.dayKey(today)) ?? false).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                ContentWidth(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: dueToday.isEmpty ? 1 : doneToday / dueToday.length,
                                  strokeWidth: 6,
                                  color: habitColor,
                                  backgroundColor: p.raised,
                                ),
                                Text(
                                  '$doneToday/${dueToday.length}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doneToday == dueToday.length
                                      ? 'All done today'
                                      : '${dueToday.length - doneToday} to go today',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                                Text(DateFormat('EEEE d MMMM').format(today), style: TextStyle(color: p.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final h in habits)
                  ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HabitCard(habit: h, done: byHabit[h.id] ?? const {}),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Hold a habit to see its history and tick past days.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One habit: its icon, streak and the last seven days; tap a day to tick it.
class HabitCard extends StatelessWidget {
  const HabitCard({super.key, required this.habit, required this.done, this.compact = false});
  final Habit habit;
  final Set<String> done;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    final c = Color(habit.color);
    final today = dateOnly(DateTime.now());
    final streak = habitStreak(habit, done);
    final week = [for (var i = 6; i >= 0; i--) addDays(today, -i)];
    final last30 = [for (var i = 0; i < 30; i++) addDays(today, -i)].where((d) => habitDueOn(habit, d)).toList();
    final rate = last30.isEmpty ? 0 : last30.where((d) => done.contains(AppDatabase.dayKey(d))).length / last30.length;
    final todayDone = done.contains(AppDatabase.dayKey(today));

    Widget dayDot(DateTime d) {
      final key = AppDatabase.dayKey(d);
      final isDone = done.contains(key);
      final due = habitDueOn(habit, d);
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          db.setHabitDone(habit.id, d, !isDone);
        },
        onLongPress: () => showHabitHistory(context, habit),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('E').format(d).substring(0, 1), style: TextStyle(fontSize: 11.5, color: p.muted)),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? c : (due ? c.withValues(alpha: 0.10) : Colors.transparent),
                border: d == today && !isDone ? Border.all(color: c, width: 1.6) : null,
              ),
              child: isDone ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
            ),
          ],
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: () => showHabitHistory(context, habit),
        onTap: () => editHabit(context, habit: habit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      db.setHabitDone(habit.id, today, !todayDone);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: todayDone ? c : c.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        todayDone ? Icons.check_rounded : habitIcons[habit.icon] ?? Icons.check_rounded,
                        color: todayDone ? Colors.white : c,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        Text(
                          [
                            if (habit.days != '1111111') _daysLabel(habit.days),
                            if (habit.remindAt.isNotEmpty) 'reminder ${habit.remindAt}',
                            '${(rate * 100).round()}% this month',
                          ].join(' · '),
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department_rounded, size: 20, color: streak > 0 ? habitColor : p.muted),
                      const SizedBox(width: 2),
                      Text(
                        '$streak',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: streak > 0 ? null : p.muted),
                      ),
                    ],
                  ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final d in week) dayDot(d)]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _daysLabel(String days) {
  if (days == '1111100') return 'Weekdays';
  if (days == '0000011') return 'Weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return [
    for (var i = 0; i < 7; i++)
      if (days[i] == '1') names[i],
  ].join(', ');
}

Future<void> editHabit(BuildContext context, {Habit? habit}) async {
  final db = context.db;
  final name = TextEditingController(text: habit?.name ?? '');
  var icon = habit?.icon ?? 'check';
  var color = habit?.color ?? habitColors.first;
  var days = (habit?.days ?? '1111111').split('');
  var remind = habit?.remindAt ?? '';
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                autofocus: habit == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Habit', hintText: 'Read 20 minutes'),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Icon'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in habitIcons.entries)
                    IconButton.filledTonal(
                      isSelected: icon == e.key,
                      onPressed: () => setSheet(() => icon = e.key),
                      icon: Icon(e.value, color: icon == e.key ? Color(color) : null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in habitColors)
                    GestureDetector(
                      onTap: () => setSheet(() => color = c),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Color(c),
                        child: color == c ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('Days'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      showCheckmark: false,
                      label: Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]),
                      selected: days[i] == '1',
                      onSelected: (v) => setSheet(() => days[i] = v ? '1' : '0'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_none_rounded),
                title: Text(remind.isEmpty ? 'No reminder' : 'Remind me at $remind'),
                subtitle: const Text('Only on days it is not done yet'),
                trailing: remind.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setSheet(() => remind = '')),
                onTap: () async {
                  final parts = remind.split(':');
                  final t = await showTimePicker(
                    context: context,
                    initialTime: remind.isEmpty
                        ? const TimeOfDay(hour: 20, minute: 0)
                        : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                  );
                  if (t != null) {
                    setSheet(
                      () => remind = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (habit != null)
                    TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (result == 'delete' && habit != null) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final checks = await db.habitChecksSince(DateTime(1970));
    final kept = checks.where((c) => c.habitId == habit.id).toList();
    await db.deleteHabit(habit.id);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${habit.name} deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => db.transaction(() async {
              await db.into(db.habits).insert(habit);
              for (final c in kept) {
                await db.into(db.habitChecks).insert(c);
              }
            }),
          ),
        ),
      );
    return;
  }
  if (result != 'save' || name.text.trim().isEmpty) return;
  if (!days.contains('1')) days = '1111111'.split('');
  await db.saveHabit(
    HabitsCompanion(
      id: habit == null ? const Value.absent() : Value(habit.id),
      name: Value(name.text.trim()),
      icon: Value(icon),
      color: Value(color),
      days: Value(days.join()),
      remindAt: Value(remind),
      position: Value(habit?.position ?? 0),
    ),
  );
  if (remind.isNotEmpty) await Reminders.instance.ensurePermission();
}

/// A month-by-month view of one habit where any past day can be ticked.
Future<void> showHabitHistory(BuildContext context, Habit habit) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Hub(
      db: context.db,
      settings: context.settings,
      child: HabitHistory(habit: habit),
    ),
  );
}

class HabitHistory extends StatefulWidget {
  const HabitHistory({super.key, required this.habit});
  final Habit habit;

  @override
  State<HabitHistory> createState() => _HabitHistoryState();
}

class _HabitHistoryState extends State<HabitHistory> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late final Stream<List<HabitCheck>> _checks = context.db.watchHabitChecks(DateTime(1970));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = widget.habit;
    final c = Color(h.color);
    final today = dateOnly(DateTime.now());
    final thisMonth = DateTime(today.year, today.month);
    return StreamBuilder<List<HabitCheck>>(
      stream: _checks,
      builder: (context, snap) {
        final done = {
          for (final x in snap.data ?? const <HabitCheck>[])
            if (x.habitId == h.id) x.day,
        };
        final lead = DateTime(_month.year, _month.month, 1).weekday - 1;
        final days = DateTime(_month.year, _month.month + 1, 0).day;
        final inMonth = done.where((k) => k.startsWith(AppDatabase.dayKey(_month).substring(0, 7))).length;
        Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(label, style: TextStyle(color: p.muted, fontSize: 12.5)),
            ],
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: c.withValues(alpha: 0.14),
                      child: Icon(habitIcons[h.icon] ?? Icons.check_rounded, color: c, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        h.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    stat('${habitStreak(h, done)}', 'Streak'),
                    stat('${habitBestStreak(h, done)}', 'Best'),
                    stat('${done.length}', 'Total'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                    ),
                    Expanded(
                      child: Text(
                        '${DateFormat('MMMM y').format(_month)}  ·  $inMonth',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: _month == thisMonth
                          ? null
                          : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Center(
                        child: Text(l, style: TextStyle(color: p.muted, fontSize: 12)),
                      ),
                    for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                    for (var n = 1; n <= days; n++)
                      Builder(
                        builder: (context) {
                          final d = DateTime(_month.year, _month.month, n);
                          final key = AppDatabase.dayKey(d);
                          final isDone = done.contains(key);
                          final future = d.isAfter(today);
                          final due = habitDueOn(h, d);
                          return InkWell(
                            key: ValueKey('habit-day-$key'),
                            customBorder: const CircleBorder(),
                            onTap: future
                                ? null
                                : () {
                                    HapticFeedback.selectionClick();
                                    context.db.setHabitDone(h.id, d, !isDone);
                                  },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDone ? c : (due && !future ? c.withValues(alpha: 0.10) : null),
                                border: d == today && !isDone ? Border.all(color: c, width: 1.6) : null,
                              ),
                              child: Text(
                                '$n',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
                                  color: isDone ? Colors.white : (future || !due ? p.muted : null),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap a day to tick or untick it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
