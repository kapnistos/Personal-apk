import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/wallet_logic.dart';
import 'package:hub/core/db/database.dart';

Entry _e(
  int cents,
  DateTime date, {
  String note = '',
  String category = 'Groceries',
  EntryKind kind = EntryKind.expense,
}) => Entry(id: 0, amountCents: cents, kind: kind, category: category, note: note, account: 'Card', date: date);

Subscription _s(DateTime next, {int period = 1, bool active = true, String name = 'Gym'}) => Subscription(
  id: 1,
  name: name,
  amountCents: 2000,
  kind: EntryKind.subscription,
  category: 'Gym',
  account: '',
  periodMonths: period,
  nextDate: next,
  active: active,
);

void main() {
  paydayTests();
  test('budget status follows an even pace through the month', () {
    final oct = DateTime(2026, 10);
    // Day 10 of 31: an even pace has spent about a third.
    final calm = budgetStatus(spent: 10000, budget: 31000, month: oct, now: DateTime(2026, 10, 10, 20));
    expect(calm.expected, 10000);
    expect(calm.state, BudgetState.onTrack);
    expect(calm.left, 21000);
    final fast = budgetStatus(spent: 20000, budget: 31000, month: oct, now: DateTime(2026, 10, 10));
    expect(fast.state, BudgetState.watch);
    final over = budgetStatus(spent: 32000, budget: 31000, month: oct, now: DateTime(2026, 10, 10));
    expect(over.state, BudgetState.over);
    expect(over.fraction, 1);
    // A finished month is judged on the whole budget.
    final past = budgetStatus(spent: 30000, budget: 31000, month: DateTime(2026, 9), now: DateTime(2026, 10, 2));
    expect(past.expected, 31000);
    expect(past.state, BudgetState.onTrack);
  });

  test('search matches words and amounts', () {
    final e = _e(1250, DateTime(2026, 10, 3), note: 'Albert Heijn');
    expect(entryMatches(e, ''), isTrue);
    expect(entryMatches(e, 'albert'), isTrue);
    expect(entryMatches(e, 'heijn groceries'), isTrue);
    expect(entryMatches(e, 'card'), isTrue);
    expect(entryMatches(e, '12'), isTrue);
    expect(entryMatches(e, '12,50'), isTrue);
    expect(entryMatches(e, '12.5'), isTrue);
    expect(entryMatches(e, '13'), isFalse);
    expect(entryMatches(e, 'lidl'), isFalse);
  });

  test('weekday totals and top places count only everyday spending', () {
    final list = [
      _e(1000, DateTime(2026, 10, 5), note: 'Lidl'), // Monday
      _e(500, DateTime(2026, 10, 12), note: ' lidl '), // Monday
      _e(3000, DateTime(2026, 10, 10), note: 'Cinema'), // Saturday
      _e(9999, DateTime(2026, 10, 6), note: 'Salary', kind: EntryKind.income),
      _e(700, DateTime(2026, 10, 7)),
    ];
    expect(weekdayTotals(list), [1500, 0, 700, 0, 0, 3000, 0]);
    final top = topMerchants(list);
    expect(top.map((m) => m.name), ['Cinema', 'Lidl']);
    expect(top[1].cents, 1500);
    expect(top[1].count, 2);
  });

  test('price changes are spotted from booked payments', () {
    final a = _e(999, DateTime(2026, 7, 1));
    final b = _e(999, DateTime(2026, 8, 1));
    final c = _e(1299, DateTime(2026, 9, 1));
    expect(priceChangeOf(1299, [c, a, b])!.diff, 300);
    expect(priceChangeOf(1299, [a, b, c])!.up, isTrue);
    expect(priceChangeOf(999, [a, b]), isNull);
    // The next payment is set lower than the last one.
    final down = priceChangeOf(899, [a, b])!;
    expect(down.before, 999);
    expect(down.up, isFalse);
    // An old change is not news any more.
    expect(priceChangeOf(1299, [a, c, _e(1299, DateTime(2026, 10, 1))]), isNull);
  });

  test('bill calendar repeats items inside the window and skips paused ones', () {
    final from = DateTime(2026, 10, 30);
    final days = billCalendar(
      [
        _s(DateTime(2026, 10, 31)),
        _s(DateTime(2026, 11, 15), period: 12, name: 'Insurance'),
        _s(DateTime(2026, 11, 2), active: false, name: 'Paused'),
      ],
      from,
      days: 62,
    );
    expect(days.map((d) => d.sub.name), ['Gym', 'Insurance', 'Gym']);
    // 31 Oct + 1 month clamps to 30 Nov.
    expect(days.last.date, DateTime(2026, 11, 30));
  });
}

void paydayTests() {
  test('payday rule parses and suggests saving once per salary', () {
    expect(parsePaydayRule(null), isNull);
    expect(parsePaydayRule('3:5000'), (goalId: 3, cents: 5000));
    expect(parsePaydayRule('3:0'), isNull);
    final salary = _e(250000, DateTime(2026, 10, 25), category: 'Salary', kind: EntryKind.income);
    final now = DateTime(2026, 10, 30);
    expect(pendingPayday(entries: [salary], moves: [], goalId: 3, now: now), DateTime(2026, 10, 25));
    final move = SavingsMove(id: 1, goalId: 3, amountCents: 5000, date: DateTime(2026, 10, 26), note: '');
    expect(pendingPayday(entries: [salary], moves: [move], goalId: 3, now: now), isNull);
    expect(pendingPayday(entries: [salary], moves: [], goalId: 3, now: now, skipped: DateTime(2026, 10, 25)), isNull);
    // Too long ago to still be news.
    expect(pendingPayday(entries: [salary], moves: [], goalId: 3, now: DateTime(2026, 11, 10)), isNull);
  });
}
