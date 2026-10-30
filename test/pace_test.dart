import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/insights.dart';
import 'package:hub/core/db/database.dart';

Entry _e(DateTime date, int cents, {EntryKind kind = EntryKind.expense}) =>
    Entry(id: 0, amountCents: cents, kind: kind, category: 'Groceries', note: '', account: 'Card', date: date);

Subscription _s(DateTime next, int cents, {EntryKind kind = EntryKind.subscription, bool active = true}) =>
    Subscription(
      id: 1,
      name: 'Rent',
      amountCents: cents,
      kind: kind,
      category: 'Rent',
      account: '',
      periodMonths: 1,
      nextDate: next,
      active: active,
    );

void main() {
  group('SpendPlan month boundaries', () {
    test('first day of the month', () {
      final plan = SpendPlan(target: 310000, spent: 0, billsAhead: 0, now: DateTime(2026, 10, 1, 0, 5));
      expect(plan.daysInMonth, 31);
      expect(plan.dayOfMonth, 1);
      expect(plan.daysLeft, 31);
      expect(plan.expectedByNow, 10000);
      expect(plan.perDay, 10000);
      expect(plan.projected, 0);
    });

    test('last day of the month and of the year', () {
      final plan = SpendPlan(target: 310000, spent: 300000, billsAhead: 0, now: DateTime(2026, 12, 31, 23, 59));
      expect(plan.daysInMonth, 31);
      expect(plan.dayOfMonth, 31);
      expect(plan.daysLeft, 1);
      expect(plan.perDay, 10000);
      expect(plan.expectedByNow, 310000);
      // Nothing after today to extrapolate.
      expect(plan.projected, 300000);
    });

    test('February in normal and leap years', () {
      final feb = SpendPlan(target: 1, spent: 0, billsAhead: 0, now: DateTime(2026, 2, 28));
      expect(feb.daysInMonth, 28);
      expect(feb.daysLeft, 1);
      final leap = SpendPlan(target: 1, spent: 0, billsAhead: 0, now: DateTime(2028, 2, 28));
      expect(leap.daysInMonth, 29);
      expect(leap.daysLeft, 2);
    });

    test('summer time changes do not shift the day count', () {
      // Clocks go back on 25 Oct 2026 and forward on 29 Mar 2026 in Europe; both ends of each day agree.
      for (final now in [DateTime(2026, 10, 25, 0, 30), DateTime(2026, 10, 25, 23, 30)]) {
        final plan = SpendPlan(target: 310000, spent: 0, billsAhead: 0, now: now);
        expect(plan.daysLeft, 7, reason: '$now');
        expect(plan.dayOfMonth, 25, reason: '$now');
      }
      for (final now in [DateTime(2026, 3, 29, 0, 30), DateTime(2026, 3, 29, 23, 30)]) {
        final plan = SpendPlan(target: 310000, spent: 0, billsAhead: 0, now: now);
        expect(plan.daysLeft, 3, reason: '$now');
        expect(plan.daysInMonth, 31, reason: '$now');
      }
      expect(daysInMonthOf(DateTime(2026, 10, 25, 23)), 31);
      expect(daysInMonthOf(DateTime(2026, 3, 1)), 31);
    });
  });

  group('SpendPlan pace', () {
    test('rent still to come does not make the start of the month look over pace', () {
      // 3 Oct: €1,500 budget, €800 rent due on the 28th, €60 spent so far.
      final plan = SpendPlan(target: 150000, spent: 6000, billsAhead: 80000, now: DateTime(2026, 10, 3, 12));
      expect(plan.everydayBudget, 70000);
      expect(plan.expectedByNow, (70000 * 3 / 31).round());
      expect(plan.pace, SpendPace.onTrack);
    });

    test('booked bills count as already on pace', () {
      // Rent of €800 booked on the 1st: on the 2nd, €20 of everyday spending is on track, not €780 over.
      final plan = SpendPlan(
        target: 150000,
        spent: 82000,
        billsAhead: 0,
        billsPaid: 80000,
        now: DateTime(2026, 10, 2, 9),
      );
      expect(plan.expectedByNow, 80000 + (70000 * 2 / 31).round());
      expect(plan.paceDiff, plan.expectedByNow - 82000);
      expect(plan.pace, SpendPace.onTrack);
    });

    test('under, on track, ahead and over', () {
      SpendPace at(int spent) =>
          SpendPlan(target: 300000, spent: spent, billsAhead: 0, now: DateTime(2026, 11, 15)).pace;
      // Even pace by the 15th of 30 days is €1,500; the band is 2% of €3,000 = €60.
      expect(at(150000), SpendPace.onTrack);
      expect(at(144500), SpendPace.onTrack);
      expect(at(143000), SpendPace.under);
      expect(at(156500), SpendPace.ahead);
      expect(at(300001), SpendPace.over);
      expect(paceTolerance(10000), 1000);
    });

    test('a bill still to come can tip the month over', () {
      final plan = SpendPlan(target: 100000, spent: 50000, billsAhead: 60000, now: DateTime(2026, 11, 20));
      expect(plan.left, -10000);
      expect(plan.over, isTrue);
      expect(plan.pace, SpendPace.over);
    });

    test('projection carries the everyday rate on and adds the bills to come', () {
      // 10 Nov of 30 days: €200 everyday spending in 10 days is €20 a day; 20 days after today.
      final plan = SpendPlan(
        target: 180000,
        spent: 30000,
        billsAhead: 20000,
        billsPaid: 10000,
        now: DateTime(2026, 11, 10, 18),
      );
      expect(plan.projected, 30000 + 20000 + 40000);
      expect(plan.projectedLeft, 90000);
      expect(plan.dailyAllowance, (150000 / 30).floor());
    });
  });

  test('safe to spend today keeps the later days whole', () {
    // 29 Oct: 3 days left, €100 left before today's €10.
    final plan = SpendPlan(target: 100000, spent: 91000, billsAhead: 0, now: DateTime(2026, 10, 29));
    final safe = safeToSpend(plan, 1000);
    expect(safe.today, 3333 - 1000);
    expect(safe.after, ((10000 - 3333) / 2).floor());
    // Spending past today's share shrinks the days after it.
    final heavy = safeToSpend(
      SpendPlan(target: 100000, spent: 96000, billsAhead: 0, now: DateTime(2026, 10, 29)),
      6000,
    );
    expect(heavy.today, 3333 - 6000);
    expect(heavy.after, 2000);
    // On the last day there is no "after".
    final last = safeToSpend(SpendPlan(target: 100000, spent: 90000, billsAhead: 0, now: DateTime(2026, 10, 31)), 0);
    expect(last, (today: 10000, after: 0));
  });

  group('MonthDays', () {
    test('lays out everyday spending and counts no-spend days and runs', () {
      final now = DateTime(2026, 10, 10, 12);
      final days = MonthDays.of(
        [
          _e(DateTime(2026, 10, 1, 9), 1200),
          _e(DateTime(2026, 10, 1, 18), 800),
          _e(DateTime(2026, 10, 2), 500, kind: EntryKind.subscription), // A bill is not everyday spending.
          _e(DateTime(2026, 10, 6, 23, 59), 300),
          _e(DateTime(2026, 10, 12), 999), // After today.
          _e(DateTime(2026, 9, 30, 23, 59), 999), // Last month.
        ],
        DateTime(2026, 10),
        now,
      );
      expect(days.daysInMonth, 31);
      expect(days.daysSoFar, 10);
      expect(days.everyday[0], 2000);
      expect(days.everyday[5], 300);
      expect(days.spent, 2300);
      expect(days.noSpend, 8);
      expect(days.longestRun, 4); // 2nd to 5th, and 7th to 10th.
      expect(days.currentRun, 4);
      expect(days.lastDay, DateTime(2026, 10, 31));
    });

    test('past, future and summer-time months', () {
      final now = DateTime(2026, 11, 5);
      expect(MonthDays.of(const [], DateTime(2026, 10), now).daysSoFar, 31);
      expect(MonthDays.of(const [], DateTime(2026, 12), now).daysSoFar, 0);
      expect(MonthDays.of(const [], DateTime(2026, 12), now).noSpend, 0);
      // A late entry on the day the clocks go back lands on that day, not the next.
      final oct = MonthDays.of([_e(DateTime(2026, 10, 25, 23, 30), 700)], DateTime(2026, 10), now);
      expect(oct.everyday[24], 700);
      expect(oct.noSpend, 30);
      expect(oct.longestRun, 24);
      expect(oct.currentRun, 6);
      final mar = MonthDays.of([_e(DateTime(2026, 3, 29, 3, 30), 700)], DateTime(2026, 3), now);
      expect(mar.everyday[28], 700);
    });
  });

  test('bills left this month: due today counts, next month and income do not', () {
    final now = DateTime(2026, 12, 20, 15);
    final bills = billsLeftThisMonth([
      _s(DateTime(2026, 12, 20), 1000),
      _s(DateTime(2026, 12, 31), 2000),
      _s(DateTime(2027, 1, 1), 4000),
      _s(DateTime(2026, 12, 19), 8000), // Overdue but not booked: left out.
      _s(DateTime(2026, 12, 24), 16000, kind: EntryKind.income),
      _s(DateTime(2026, 12, 24), 32000, active: false),
    ], now);
    expect(bills, (cents: 3000, count: 2));
  });

  test('fixed costs booked are the non-everyday outgoings up to now', () {
    final now = DateTime(2026, 10, 10);
    expect(
      fixedCostsBooked([
        _e(DateTime(2026, 10, 1), 80000, kind: EntryKind.subscription),
        _e(DateTime(2026, 10, 2), 5000, kind: EntryKind.tax),
        _e(DateTime(2026, 10, 3), 999),
        _e(DateTime(2026, 10, 4), 999, kind: EntryKind.income),
        _e(DateTime(2026, 10, 20), 999, kind: EntryKind.subscription),
      ], now),
      85000,
    );
  });

  group('goal pace', () {
    final made = DateTime(2026, 1, 1);
    final deadline = DateTime(2026, 12, 31);
    GoalPace? at(int saved, DateTime now, {DateTime? by}) =>
        goalPace(target: 365000, saved: saved, created: made, deadline: by ?? deadline, now: now);

    test('compares with a straight line to the deadline', () {
      // 1 Jul is 181 of 364 days in.
      final now = DateTime(2026, 7, 1, 20);
      final expected = (365000 * 181 / 364).round();
      expect(at(expected, now)!.state, GoalState.onTrack);
      expect(at(expected, now)!.expected, expected);
      expect(at(expected + 20000, now)!.state, GoalState.ahead);
      expect(at(expected - 20000, now)!.state, GoalState.behind);
      expect(at(expected - 20000, now)!.gap, -20000);
    });

    test('reached, past the deadline, and no deadline', () {
      expect(at(365000, DateTime(2026, 3, 1))!.state, GoalState.reached);
      expect(at(300000, DateTime(2027, 1, 2))!.state, GoalState.behind);
      expect(at(300000, DateTime(2027, 1, 2))!.gap, -65000);
      expect(goalPace(target: 1000, saved: 0, created: made, deadline: null, now: DateTime(2026, 5, 1)), isNull);
      // Made on the deadline day itself: the whole target is due.
      expect(at(0, made, by: made)!.expected, 365000);
    });
  });
}
