import 'dart:math' as math;

import '../../core/db/database.dart';
import '../../core/format.dart';
import 'wallet_logic.dart';
import 'wallet_model.dart';

/// How spending compares with an even pace through the month.
enum SpendPace {
  /// Comfortably below the pace.
  under,

  /// Within a small band either side of the pace.
  onTrack,

  /// Spending faster than the pace, though the budget is not gone yet.
  ahead,

  /// The budget is already used up, bills still to come included.
  over,
}

/// The band around the pace that still counts as "on track": 2% of the budget, at least €10.
int paceTolerance(int target) => math.max(1000, target ~/ 50);

/// How this month is going against a monthly spending target.
///
/// Recurring payments are fixed costs: those already booked ([billsPaid], part of [spent]) and those still
/// to come ([billsAhead]) are taken off the target first, and only the rest, the everyday budget, is
/// spread evenly over the days. So rent due on the 28th does not make the 3rd look "over pace", and a
/// bill still to come is set aside before the daily allowance.
class SpendPlan {
  SpendPlan({
    required this.target,
    required this.spent,
    required this.billsAhead,
    this.billsPaid = 0,
    required DateTime now,
  }) {
    final today = dateOnly(now);
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1);
    daysInMonth = daysBetween(monthStart, monthEnd);
    daysLeft = daysBetween(today, monthEnd); // Today counts as a day still to spend.
    dayOfMonth = daysInMonth - daysLeft + 1;
    left = target - spent - billsAhead;
    perDay = daysLeft == 0 ? 0 : (left / daysLeft).floor();
    everydayBudget = math.max(0, target - billsPaid - billsAhead);
    // Where spending "should" be by the end of today: the bills paid so far plus an even share of the rest.
    expectedByNow = billsPaid + (everydayBudget * dayOfMonth / daysInMonth).round();
    // Everyday spending carries on at this month's rate for the days after today; bills land as planned.
    final everyday = math.max(0, spent - billsPaid);
    projected = spent + billsAhead + (everyday * (daysLeft - 1) / dayOfMonth).round();
  }

  final int target;

  /// Everything gone out this month so far, booked bills included.
  final int spent;

  /// Recurring payments still to leave this month.
  final int billsAhead;

  /// Recurring payments and taxes already booked this month (part of [spent]).
  final int billsPaid;
  late final int daysInMonth;
  late final int daysLeft;

  /// 1 on the first of the month.
  late final int dayOfMonth;
  late final int left;
  late final int perDay;
  late final int expectedByNow;

  /// What is left of the target for everyday spending once all of this month's bills are taken off.
  late final int everydayBudget;

  /// Total going out by the end of the month at the current everyday rate, bills to come included.
  late final int projected;

  /// Positive when spending is under the even pace, negative when over it.
  int get paceDiff => expectedByNow - spent;

  /// Target minus [projected]: positive when the month should end under budget.
  int get projectedLeft => target - projected;

  /// The even everyday allowance per day, for drawing against daily spending.
  int get dailyAllowance => daysInMonth == 0 ? 0 : (everydayBudget / daysInMonth).floor();

  bool get over => left < 0;

  SpendPace get pace {
    if (over) return SpendPace.over;
    final tol = paceTolerance(target);
    if (paceDiff < -tol) return SpendPace.ahead;
    if (paceDiff > tol) return SpendPace.under;
    return SpendPace.onTrack;
  }

  double get usedFraction => target <= 0 ? 0 : ((spent + billsAhead) / target).clamp(0, 1).toDouble();
  double get paceFraction => target <= 0 ? 0 : (expectedByNow / target).clamp(0, 1).toDouble();
}

/// What can go today without eating into later days ([today], negative once today's share is spent), and
/// the even share for each day after it ([after]). [everydayToday] is today's everyday spending, already in
/// [SpendPlan.spent].
({int today, int after}) safeToSpend(SpendPlan plan, int everydayToday) {
  if (plan.daysLeft <= 0) return (today: 0, after: 0);
  final pool = plan.left + everydayToday;
  final share = (pool / plan.daysLeft).floor();
  final after = plan.daysLeft <= 1 ? 0 : ((pool - math.max(share, everydayToday)) / (plan.daysLeft - 1)).floor();
  return (today: share - everydayToday, after: after);
}

/// Days in the month that [day] falls in, worked out on calendar dates so summer time cannot shift it.
int daysInMonthOf(DateTime day) => daysBetween(DateTime(day.year, day.month), DateTime(day.year, day.month + 1));

/// Everyday spending laid out day by day for one month.
class MonthDays {
  MonthDays._(this.month, this.everyday, this.daysSoFar);

  /// Builds the strip for [month] from its entries. Only expenses count as everyday spending; recurring
  /// payments and taxes are fixed costs and would hide the pattern. Days after [now] stay empty.
  factory MonthDays.of(Iterable<Entry> entries, DateTime month, DateTime now) {
    final start = DateTime(month.year, month.month);
    final days = daysInMonthOf(start);
    final today = dateOnly(now);
    final soFar = today.isBefore(start) ? 0 : math.min(days, daysBetween(start, today) + 1);
    final everyday = List<int>.filled(days, 0);
    for (final e in entries) {
      if (e.kind != EntryKind.expense) continue;
      final i = daysBetween(start, e.date);
      if (i < 0 || i >= soFar) continue;
      everyday[i] += e.amountCents;
    }
    return MonthDays._(start, List.unmodifiable(everyday), soFar);
  }

  final DateTime month;

  /// Cents spent on each day, index 0 being the 1st.
  final List<int> everyday;

  /// Days of the month that have started: today included for the running month, all for a past one.
  final int daysSoFar;

  int get daysInMonth => everyday.length;
  DateTime get lastDay => DateTime(month.year, month.month, daysInMonth);

  int get spent => everyday.fold(0, (a, b) => a + b);

  /// Days so far without any everyday spending.
  int get noSpend => everyday.take(daysSoFar).where((c) => c == 0).length;

  /// The longest run of no-spend days so far.
  int get longestRun {
    var best = 0, run = 0;
    for (final c in everyday.take(daysSoFar)) {
      run = c == 0 ? run + 1 : 0;
      best = math.max(best, run);
    }
    return best;
  }

  /// No-spend days in a row up to the latest day so far.
  int get currentRun {
    var run = 0;
    for (var i = daysSoFar - 1; i >= 0 && everyday[i] == 0; i--) {
      run++;
    }
    return run;
  }

  int get biggestDay => everyday.fold(0, math.max);
}

/// Recurring payments still to leave between today and the end of the month, repeats included.
({int cents, int count}) billsLeftThisMonth(Iterable<Subscription> subs, DateTime now) {
  final today = dateOnly(now);
  final end = DateTime(today.year, today.month + 1);
  var cents = 0, count = 0;
  for (final b in billCalendar(subs, today, days: daysBetween(today, end))) {
    if (b.sub.kind.sign >= 0) continue;
    cents += b.sub.amountCents;
    count++;
  }
  return (cents: cents, count: count);
}

/// Fixed costs already booked in the month up to [now]: everything going out that is not an everyday
/// expense (recurring payments, taxes).
int fixedCostsBooked(Iterable<Entry> monthEntries, DateTime now) => monthEntries
    .where((e) => e.kind.sign < 0 && e.kind != EntryKind.expense && !e.date.isAfter(now))
    .fold(0, (t, e) => t + e.amountCents);

/// How a savings goal with a deadline is doing.
enum GoalState { reached, onTrack, ahead, behind }

class GoalPace {
  const GoalPace({required this.state, required this.expected, required this.gap});
  final GoalState state;

  /// What an even pace from the day the goal was made would have put aside by today.
  final int expected;

  /// Saved minus expected: positive when ahead of the pace.
  final int gap;
}

/// Compares what is saved with a straight line from nothing on [created] to [target] on [deadline].
/// Null when there is no deadline to measure against.
GoalPace? goalPace({
  required int target,
  required int saved,
  required DateTime created,
  required DateTime? deadline,
  required DateTime now,
}) {
  if (target > 0 && saved >= target) return GoalPace(state: GoalState.reached, expected: target, gap: saved - target);
  if (deadline == null || target <= 0) return null;
  final total = daysBetween(created, deadline);
  final gone = daysBetween(created, now);
  final expected = total <= 0 || gone >= total ? target : (target * math.max(0, gone) / total).round();
  final gap = saved - expected;
  final tol = paceTolerance(target);
  final state = !dateOnly(now).isBefore(dateOnly(deadline)) || gap < -tol
      ? GoalState.behind
      : gap > tol
      ? GoalState.ahead
      : GoalState.onTrack;
  return GoalPace(state: state, expected: expected, gap: gap);
}
