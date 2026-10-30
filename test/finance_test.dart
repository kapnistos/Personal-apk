import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/insights.dart';
import 'package:hub/core/db/database.dart';

void main() {
  test('left to spend counts bills still to come and gives a daily allowance', () {
    // 10 October of a 31-day month: 22 days left, today included.
    final plan = SpendPlan(target: 150000, spent: 40000, billsAhead: 20000, now: DateTime(2026, 10, 10, 15));
    expect(plan.daysLeft, 22);
    expect(plan.left, 90000);
    expect(plan.perDay, 4090);
    expect(plan.expectedByNow, (150000 * 10 / 31).round());
    expect(plan.paceDiff, plan.expectedByNow - 60000);
    expect(plan.over, isFalse);
  });

  test('insights pick out categories well above or below the usual', () {
    final list = categoryInsights(
      {'Groceries': 40000, 'Eating out': 5000, 'Transport': 10200, 'Gifts': 3000},
      [
        {'Groceries': 25000, 'Eating out': 15000, 'Transport': 10000},
        {'Groceries': 25000, 'Eating out': 15000, 'Transport': 10000},
      ],
    );
    expect(list.map((i) => i.category), ['Groceries', 'Eating out', 'Gifts']);
    expect(list.first.change, closeTo(0.6, 0.001));
    expect(list.last.usual, 0);
  });

  test('round-ups go to the chosen goal', () async {
    expect(roundUpCents(340), 60);
    expect(roundUpCents(500), 0);
    final db = AppDatabase(NativeDatabase.memory());
    final goal = await db.saveGoal(
      SavingsGoalsCompanion.insert(name: 'Trip', targetCents: 100000, color: 0xFF000000),
    );
    expect(await applyRoundUp(db, '$goal', 1234, 'Coffee'), 66);
    expect(await applyRoundUp(db, '', 1234, 'Coffee'), 0);
    expect(await applyRoundUp(db, '999', 1234, 'Coffee'), 0);
    final moves = await db.watchMoves().first;
    expect(moves.single.amountCents, 66);
    expect(moves.single.note, 'Round-up · Coffee');
    await db.close();
  });

  test('net worth adds cards, savings and investments', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.delete(db.subscriptions).go();
    final abn = (await db.watchAccounts().first).first;
    await (db.update(db.accounts)..where((a) => a.id.equals(abn.id))).write(
      AccountsCompanion(balanceCents: const Value(100000), balanceAt: Value(DateTime(2026, 10, 1))),
    );
    final goal = await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Fund', targetCents: 1, color: 0));
    await db.addMove(goal, 50000);
    await db.into(db.holdings).insert(
      HoldingsCompanion.insert(name: 'ETF', units: 2, investedCents: 10000, price: 75.5),
    );
    final w = await computeNetWorth(db, now: DateTime(2026, 10, 30));
    expect((w.cards, w.savings, w.investments, w.total), (100000, 50000, 15100, 165100));
    await db.close();
  });
}
