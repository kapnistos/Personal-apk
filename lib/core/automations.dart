import '../apps/calendar/calendar_model.dart' show expand;
import '../apps/wallet/accounts_page.dart' show AccountState;
import '../apps/wallet/wallet_model.dart';
import 'db/database.dart';
import 'format.dart';
import 'settings.dart';

/// A notification an automation wants to show at a set time.
class PlannedNote {
  const PlannedNote(this.id, this.at, this.title, this.body, this.payload);
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;

  @override
  String toString() => '$at $title: $body';
}

/// The automations and their settings (raw keys "auto.*").
class AutomationSettings {
  AutomationSettings(Map<String, String> raw)
    : briefing = _time(raw['auto.briefing'] ?? '07:30'),
      bills = (raw['auto.bills'] ?? 'on') == 'on',
      lowBalanceCents = raw['auto.lowBalance'] == 'off' ? null : int.tryParse(raw['auto.lowBalance'] ?? '') ?? 10000,
      weekly = (raw['auto.weekly'] ?? 'on') == 'on',
      overdue = (raw['auto.overdue'] ?? 'on') == 'on',
      habits = (raw['auto.habits'] ?? 'on') == 'on',
      backup = (raw['auto.backup'] ?? 'on') == 'on';

  /// Morning briefing time (hour, minute), or null when off.
  final (int, int)? briefing;
  final bool bills;
  final int? lowBalanceCents;
  final bool weekly;
  final bool overdue;
  final bool habits;
  final bool backup;

  static (int, int)? _time(String v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
    return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
  }
}

/// The automation settings as one string, to tell when any of them changed.
String automationSignature(AppSettings s) =>
    const ['briefing', 'bills', 'lowBalance', 'weekly', 'overdue', 'habits'].map((k) => s.raw('auto.$k')).join('|');

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _euro(int cents) {
  final v = cents.abs() / 100;
  return '€${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
}

/// Every automation notification for the next week, worked out from what is in
/// the database right now. Reminders reschedules them whenever data changes.
Future<List<PlannedNote>> planAutomations(AppDatabase db, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final today = dateOnly(n);
  final s = AutomationSettings(await db.readSettings());
  final out = <PlannedNote>[];

  final subs = (await db.watchSubscriptions().first).where((x) => x.active).toList();
  final todos = await db.watchTodos().first;
  final cals = {for (final c in await db.watchCalendars().first) c.id: c};
  final events = await db.watchEventsBetween(today, addDays(today, 9)).first;
  final occ = expand(events, cals, today, addDays(today, 9));
  final apps = await db.watchApplications().first;
  final habits = await db.watchHabits().first;
  final checks = await db.habitChecksSince(today);
  final done = {for (final c in checks) '${c.habitId}:${c.day}'};

  bool habitDue(Habit h, DateTime d) => h.days.length == 7 && h.days[d.weekday - 1] == '1';

  // Morning briefing: what the day holds, at the chosen time, for the next 7 days.
  final b = s.briefing;
  if (b != null) {
    for (var i = 0; i < 7; i++) {
      final day = addDays(today, i);
      final at = DateTime(day.year, day.month, day.day, b.$1, b.$2);
      if (!at.isAfter(n)) continue;
      final next = addDays(day, 1);
      final dayEvents = occ.where((o) => o.touches(day)).toList()..sort((a, b) => a.start.compareTo(b.start));
      final dayTasks = todos
          .where(
            (t) =>
                !t.done &&
                ((t.due != null && dateOnly(t.due!) == day) || (t.remindAt != null && dateOnly(t.remindAt!) == day)),
          )
          .length;
      final overdue = i == 0 ? todos.where((t) => !t.done && t.due != null && t.due!.isBefore(day)).length : 0;
      final bills = subs.where((x) => x.kind.sign < 0 && daysBetween(day, x.nextDate) == 0).toList();
      final income = subs.where((x) => x.kind.sign > 0 && daysBetween(day, x.nextDate) == 0).toList();
      final deadlines = apps
          .where((a) => (a.status == 'wishlist' || a.status == 'preparing') && a.deadline != null)
          .where((a) => daysBetween(day, a.deadline!) >= 0 && daysBetween(day, a.deadline!) <= 2)
          .toList();
      final habitCount = habits.where((h) => habitDue(h, day)).length;
      final timed = dayEvents.where((o) => !o.allDay && o.start.isBefore(next)).toList();
      final parts = <String>[
        if (dayEvents.isEmpty) 'No events',
        if (dayEvents.isNotEmpty)
          '${dayEvents.length} ${dayEvents.length == 1 ? 'event' : 'events'}'
              '${timed.isEmpty ? '' : ', first ${_hm(timed.first.start)} ${timed.first.event.title}'}',
        if (dayTasks > 0) '$dayTasks ${dayTasks == 1 ? 'task' : 'tasks'}',
        if (overdue > 0) '$overdue overdue',
        for (final x in bills) '${x.name} ${_euro(x.amountCents)} due',
        for (final x in income) '${x.name} +${_euro(x.amountCents)}',
        for (final a in deadlines) 'apply to ${a.company} by ${friendlyDay(a.deadline!, now: day).toLowerCase()}',
        if (habitCount > 0) '$habitCount ${habitCount == 1 ? 'habit' : 'habits'}',
      ];
      out.add(PlannedNote(500000 + i, at, 'Your ${i == 0 ? 'day' : _weekday(day)}', parts.join(' · '), 'today'));
    }
  }

  // The evening before a payment leaves.
  if (s.bills) {
    var i = 0;
    for (final x in subs.where((x) => x.kind.sign < 0)) {
      final eve = addDays(dateOnly(x.nextDate), -1);
      final at = DateTime(eve.year, eve.month, eve.day, 18);
      if (!at.isAfter(n) || at.isAfter(addDays(n, 8))) continue;
      out.add(
        PlannedNote(
          510000 + i++,
          at,
          'Tomorrow: ${x.name} ${_euro(x.amountCents)}',
          x.account.isEmpty ? 'Recurring payment' : 'From ${x.account}',
          'wallet',
        ),
      );
    }
  }

  // A warning two days before a card would drop below the threshold.
  final low = s.lowBalanceCents;
  if (low != null) {
    final accounts = (await db.watchAccounts().first).where((a) => a.balanceAt != null).toList();
    var i = 0;
    for (final a in accounts) {
      final entries = await db.watchAccountEntries(a.name).first;
      final state = AccountState(a, entries, subs, now: n);
      var balance = state.balance;
      // Walk this card's recurring money over the next five weeks.
      final moves = <(DateTime, int, String)>[];
      for (final x in state.recurring) {
        var d = x.nextDate;
        while (d.isBefore(addDays(today, 35))) {
          if (!d.isBefore(today)) moves.add((d, x.kind.sign * x.amountCents, x.name));
          d = addMonths(d, x.periodMonths);
        }
      }
      moves.sort((p, q) => p.$1.compareTo(q.$1));
      for (final (d, cents, name) in moves) {
        balance += cents;
        if (balance < low) {
          var at = DateTime(d.year, d.month, d.day - 2, 9);
          if (!at.isAfter(n)) {
            at = n.hour < 9 ? DateTime(n.year, n.month, n.day, 9) : DateTime(n.year, n.month, n.day + 1, 9);
            if (!at.isBefore(d)) break; // Already past; nothing useful to say.
          }
          out.add(
            PlannedNote(
              520000 + i++,
              at,
              '${a.name} may run low',
              'After $name on ${friendlyDay(d, now: dateOnly(at)).toLowerCase()} it would be at ${balance < 0 ? '-' : ''}${_euro(balance)}',
              'wallet',
            ),
          );
          break;
        }
      }
    }
  }

  // Sunday evening: the week ahead, and what this week cost.
  if (s.weekly) {
    var sunday = addDays(today, (7 - today.weekday) % 7);
    var at = DateTime(sunday.year, sunday.month, sunday.day, 19);
    if (!at.isAfter(n)) {
      sunday = addDays(sunday, 7);
      at = DateTime(sunday.year, sunday.month, sunday.day, 19);
    }
    final weekStart = addDays(sunday, -6);
    final spentEntries = await db.watchEntries(weekStart, addDays(sunday, 1)).first;
    final spent = MonthSummary(spentEntries.where((e) => !e.date.isAfter(n)).toList()).out;
    final mon = addDays(sunday, 1);
    final nextWeekEvents = await db.watchEventsBetween(mon, addDays(mon, 7)).first;
    final eventsAhead = expand(nextWeekEvents, cals, mon, addDays(mon, 7)).length;
    final tasksAhead = todos
        .where((t) => !t.done && t.due != null && !t.due!.isBefore(mon) && t.due!.isBefore(addDays(mon, 7)))
        .length;
    final billsAhead = subs
        .where((x) => x.kind.sign < 0 && !x.nextDate.isBefore(mon) && x.nextDate.isBefore(addDays(mon, 7)))
        .fold<int>(0, (t, x) => t + x.amountCents);
    out.add(
      PlannedNote(
        530000,
        at,
        'Your week ahead',
        [
          '$eventsAhead ${eventsAhead == 1 ? 'event' : 'events'}',
          '$tasksAhead ${tasksAhead == 1 ? 'task' : 'tasks'} due',
          if (billsAhead > 0) '${_euro(billsAhead)} in bills',
          if (spent > 0) 'spent ${_euro(spent)} so far this week',
        ].join(' · '),
        'today',
      ),
    );
  }

  // 20:00 nudge while tasks are overdue.
  if (s.overdue) {
    final late = todos.where((t) => !t.done && t.due != null && t.due!.isBefore(today)).toList();
    final at = DateTime(today.year, today.month, today.day, 20);
    if (late.isNotEmpty && at.isAfter(n)) {
      out.add(
        PlannedNote(
          540000,
          at,
          '${late.length} overdue ${late.length == 1 ? 'task' : 'tasks'}',
          late.take(3).map((t) => t.title).join(', '),
          'todo',
        ),
      );
    }
  }

  // Habit reminders on the days they apply, unless already done.
  if (s.habits) {
    var i = 0;
    for (final h in habits) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(h.remindAt);
      if (m == null) continue;
      for (var d = 0; d < 7; d++) {
        final day = addDays(today, d);
        final at = DateTime(day.year, day.month, day.day, int.parse(m[1]!), int.parse(m[2]!));
        if (!at.isAfter(n) || !habitDue(h, day) || done.contains('${h.id}:${AppDatabase.dayKey(day)}')) continue;
        out.add(PlannedNote(550000 + i++, at, h.name, 'Keep your streak going', 'habit'));
      }
    }
  }
  return out;
}

String _weekday(DateTime d) =>
    const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];
