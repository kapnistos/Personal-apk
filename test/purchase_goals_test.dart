import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/goals_page.dart';
import 'package:hub/apps/wallet/insights.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/core/backup.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/sync/sync_engine.dart';

import 'flows_test.dart' show done, pumpPage, settle;
import 'sync_test.dart' show roundTrip, tick;

const _phone = (Size(412, 915), false, 1.0);

SavingsGoal _goal({
  int id = 1,
  String name = 'New laptop',
  int target = 180000,
  DateTime? deadline,
  DateTime? created,
  bool archived = false,
}) => SavingsGoal(
  id: id,
  name: name,
  targetCents: target,
  deadline: deadline,
  color: 0xFF3A78C9,
  archived: archived,
  createdAt: created ?? DateTime(2026, 11, 1),
  purpose: purchasePurpose,
  icon: 'laptop',
  link: '',
  note: '',
);

Future<int> _purchase(AppDatabase db, String name, int cents, {DateTime? by, String link = ''}) => db.saveGoal(
  SavingsGoalsCompanion.insert(
    name: name,
    targetCents: cents,
    color: 0xFF3A78C9,
    deadline: Value(by),
    purpose: const Value(purchasePurpose),
    icon: const Value('laptop'),
    link: Value(link),
  ),
);

void main() {
  final now = DateTime(2026, 11, 6, 10);

  group('purchase plan', () {
    test('a dated goal says what is needed each month and week, rounded up', () {
      final plan = purchasePlan(
        target: 180000,
        saved: 60000,
        start: DateTime(2026, 11, 1),
        date: DateTime(2027, 3, 1),
        now: now,
      );
      expect(plan.left, 120000);
      expect(plan.daysLeft, 115);
      // November to February: four months to put it aside, the current one included.
      expect(plan.perMonth, 30000);
      // 17 weeks; 120000 / 17 = 7058.8, rounded up so following it always gets there.
      expect(plan.perWeek, 7059);
      expect(plan.fraction, closeTo(1 / 3, 1e-9));
      expect(plan.pace!.state, GoalState.ahead);
      expect(plan.overdue, isFalse);
      expect(neededLine(plan, 'EUR'), '€300.00 a month or €70.59 a week to make it');
    });

    test('behind the even pace shows as behind', () {
      final plan = purchasePlan(
        target: 120000,
        saved: 0,
        start: DateTime(2026, 5, 6),
        date: DateTime(2027, 5, 6),
        now: now,
      );
      expect(plan.pace!.state, GoalState.behind);
      expect(plan.pace!.gap, lessThan(0));
    });

    test('reached goals need nothing more', () {
      final plan = purchasePlan(
        target: 50000,
        saved: 52000,
        start: DateTime(2026, 10, 1),
        date: DateTime(2027, 1, 1),
        now: now,
      );
      expect(plan.reached, isTrue);
      expect(plan.left, 0);
      expect(plan.fraction, 1);
      expect(plan.perMonth, isNull);
      expect(neededLine(plan, 'EUR'), isNull);
    });

    test('a date that has passed is overdue, not a plan', () {
      final plan = purchasePlan(
        target: 50000,
        saved: 10000,
        start: DateTime(2026, 6, 1),
        date: DateTime(2026, 11, 1),
        now: now,
      );
      expect(plan.overdue, isTrue);
      expect(plan.daysLeft, -5);
      expect(plan.perMonth, isNull);
      expect(plan.perWeek, isNull);
    });

    test('a date today or close by asks for the rest in one go', () {
      final today = purchasePlan(target: 50000, saved: 10000, start: DateTime(2026, 6, 1), date: now, now: now);
      expect(today.overdue, isFalse);
      expect(today.perWeek, 40000);
      expect(today.perMonth, 40000);
      expect(neededLine(today, 'EUR'), 'Put €400.00 aside by then to make it');
    });

    test('without a date, the pace so far gives a likely month', () {
      final plan = purchasePlan(target: 90000, saved: 30000, start: DateTime(2026, 10, 7), now: now);
      // €10 a day over 30 days; €600 more takes 60 days.
      expect(plan.projected, DateTime(2027, 1, 5));
      expect(plan.perMonth, isNull);
      expect(plan.pace, isNull);
      // Too little history to promise anything.
      expect(purchasePlan(target: 90000, saved: 30000, start: DateTime(2026, 11, 1), now: now).projected, isNull);
      expect(purchasePlan(target: 90000, saved: 0, start: DateTime(2026, 1, 1), now: now).projected, isNull);
    });

    test('more taken out than put in never shows as negative progress', () {
      final plan = purchasePlan(target: 10000, saved: -500, start: DateTime(2026, 10, 1), now: now);
      expect(plan.fraction, 0);
      // The €5 overdrawn has to be put back too.
      expect(plan.left, 10500);
    });

    test('planFor counts only this goal\'s moves and starts at an earlier first deposit', () {
      final g = _goal(deadline: DateTime(2027, 3, 1), created: DateTime(2026, 11, 1));
      final moves = [
        SavingsMove(id: 1, goalId: 1, amountCents: 30000, date: DateTime(2026, 9, 1), note: ''),
        SavingsMove(id: 2, goalId: 1, amountCents: -5000, date: DateTime(2026, 10, 1), note: ''),
        SavingsMove(id: 3, goalId: 2, amountCents: 99999, date: DateTime(2026, 10, 1), note: ''),
      ];
      expect(goalStart(g, moves), DateTime(2026, 9, 1));
      final plan = planFor(g, moves, now: now);
      expect(plan.saved, 25000);
      expect(plan.left, 155000);
    });

    test('soonest date first, undated goals last', () {
      final list = sortPurchaseGoals([
        _goal(id: 1, name: 'Sofa', created: DateTime(2026, 1, 1)),
        _goal(id: 2, name: 'Bike', deadline: DateTime(2027, 6, 1)),
        _goal(id: 3, name: 'Trip', deadline: DateTime(2027, 2, 1)),
        _goal(id: 4, name: 'Camera', created: DateTime(2025, 1, 1)),
      ]);
      expect(list.map((g) => g.name), ['Trip', 'Bike', 'Camera', 'Sofa']);
    });

    test('the icon follows the name', () {
      expect(purchaseIconFor('New laptop'), 'laptop');
      expect(purchaseIconFor('MacBook Air'), 'laptop');
      expect(purchaseIconFor('Summer trip to Crete'), 'travel');
      expect(purchaseIconFor('e-bike'), 'bike');
      expect(purchaseIconFor('Something nice'), 'bag');
      // Whole words only: "scarf" is not a car.
      expect(purchaseIconFor('Wool scarf'), 'bag');
    });
  });

  group('purchase goals in the database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('new goals are savings goals unless made as a purchase', () async {
      await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Rainy day', targetCents: 1000, color: 1));
      await _purchase(db, 'New laptop', 180000, link: 'example.com/laptop');
      final goals = await db.watchGoals().first;
      expect({for (final g in goals) g.name: g.purpose}, {'Rainy day': 'savings', 'New laptop': 'purchase'});
      expect(goals.firstWhere(isPurchase).link, 'example.com/laptop');
    });

    test('marking bought archives with the day, and undo puts it back', () async {
      final id = await _purchase(db, 'Headphones', 30000);
      await db.addMove(id, 30000);
      await db.setGoalBought(id, true, at: DateTime(2026, 11, 6));
      var g = (await db.watchGoals().first).single;
      expect((g.archived, g.doneAt), (true, DateTime(2026, 11, 6)));
      expect(isBought(g), isTrue);
      await db.setGoalBought(id, false);
      g = (await db.watchGoals().first).single;
      expect((g.archived, g.doneAt), (false, null));
    });

    test('money for something bought leaves net worth, money still put aside stays', () async {
      final laptop = await _purchase(db, 'Laptop', 100000);
      final bike = await _purchase(db, 'Bike', 50000);
      await db.addMove(laptop, 100000);
      await db.addMove(bike, 20000);
      expect((await computeNetWorth(db)).savings, 120000);
      await db.setGoalBought(laptop, true);
      expect((await computeNetWorth(db)).savings, 20000);
      // A savings goal that is reached and put away is still money owned.
      final fund = await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Fund', targetCents: 1000, color: 1));
      await db.addMove(fund, 1000);
      await (db.update(
        db.savingsGoals,
      )..where((g) => g.id.equals(fund))).write(const SavingsGoalsCompanion(archived: Value(true)));
      expect((await computeNetWorth(db)).savings, 21000);
    });

    test('a deleted goal comes back with its history', () async {
      final id = await _purchase(db, 'Camera', 80000, by: DateTime(2027, 4, 1));
      await db.addMove(id, 10000, note: 'First');
      await db.addMove(id, 5000, note: 'Second');
      final goal = (await db.watchGoals().first).single;
      final moves = await db.watchMoves().first;
      await db.deleteGoal(id);
      expect(await db.watchGoals().first, isEmpty);
      expect(await db.watchMoves().first, isEmpty);
      await db.restoreGoal(goal, moves);
      expect((await db.watchGoals().first).single, goal);
      expect((await db.watchMoves().first).map((m) => m.note), ['Second', 'First']);
    });

    test('a removed move can be put back', () async {
      final id = await _purchase(db, 'Desk', 40000);
      await db.addMove(id, 1500);
      final m = (await db.watchMoves().first).single;
      await db.deleteMove(m.id);
      await db.restoreMove(m);
      expect((await db.watchMoves().first).single, m);
    });

    test('a backup keeps everything about a purchase goal', () async {
      final id = await _purchase(db, 'Sofa', 90000, by: DateTime(2027, 2, 1), link: 'https://example.com/sofa');
      await (db.update(
        db.savingsGoals,
      )..where((g) => g.id.equals(id))).write(const SavingsGoalsCompanion(note: Value('The grey one')));
      await db.addMove(id, 20000);
      await db.setGoalBought(id, true, at: DateTime(2026, 11, 6));
      final json = await backupJson(db);
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await restoreBackup(other, json, replace: true);
      final g = (await other.watchGoals().first).single;
      expect(
        (g.name, g.purpose, g.icon, g.link, g.note, g.deadline, g.doneAt, g.archived),
        (
          'Sofa',
          'purchase',
          'laptop',
          'https://example.com/sofa',
          'The grey one',
          DateTime(2027, 2, 1),
          DateTime(2026, 11, 6),
          true,
        ),
      );
      expect((await other.watchMoves().first).single.amountCents, 20000);
    });
  });

  test('purchase goals sync between devices', () async {
    final server = AppDatabase(NativeDatabase.memory());
    final phone = AppDatabase(NativeDatabase.memory());
    final pc = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await server.close();
      await phone.close();
      await pc.close();
    });
    final s = SyncEngine(server), a = SyncEngine(phone), b = SyncEngine(pc);
    await s.setRole('server');
    await a.setRole('client');
    await b.setRole('client');
    final id = await _purchase(phone, 'New laptop', 180000, by: DateTime(2027, 3, 1), link: 'example.com');
    await phone.addMove(id, 25000);
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    final g = (await pc.watchGoals().first).single;
    expect((g.purpose, g.icon, g.link, g.deadline), ('purchase', 'laptop', 'example.com', DateTime(2027, 3, 1)));
    expect((await pc.watchMoves().first).single.goalId, g.id);
    // Bought on the PC shows as bought on the phone.
    await pc.setGoalBought(g.id, true, at: DateTime(2026, 11, 6));
    await tick();
    await roundTrip(b, s);
    await roundTrip(a, s);
    final back = (await phone.watchGoals().first).single;
    expect((back.archived, back.doneAt), (true, DateTime(2026, 11, 6)));
  });

  test('a version 6 database upgrades: old goals stay savings goals and purchase goals can be added', () async {
    final dir = Directory.systemTemp.createTempSync('hub');
    final file = File('${dir.path}/hub.db');
    File('test/fixtures/v6.db').copySync(file.path);
    final db = AppDatabase(NativeDatabase(file));
    final old = (await db.watchGoals().first).single;
    expect(
      (old.name, old.purpose, old.icon, old.link, old.note, old.doneAt),
      ('Rainy day', 'savings', '', '', '', null),
    );
    expect((await db.watchMoves().first).single.amountCents, 25000);
    final id = await _purchase(db, 'New laptop', 180000);
    await db.setGoalBought(id, true);
    final gid = await db
        .customSelect('SELECT gid FROM savings_goals WHERE id = ?', variables: [Variable(id)])
        .getSingle();
    expect(gid.read<String?>('gid'), isNotNull);
    await db.close();
    // Opening again does not try to add the columns twice.
    final again = AppDatabase(NativeDatabase(file));
    expect((await again.watchGoals().first).length, 2);
    await again.close();
    dir.deleteSync(recursive: true);
  });

  group('Goals tab', () {
    setUp(() => personalEdition = false);

    testWidgets('plan a purchase, put money aside, buy it, and undo a delete', (t) async {
      final db = await pumpPage(t, _phone, () => const WalletPage(initialTab: 3), demo: false);
      expect(find.text('Nothing planned yet'), findsOneWidget);

      // A new goal with money already put aside.
      await t.tap(find.text('Plan a purchase').last);
      await settle(t);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), 'New laptop');
      await t.enterText(fields.at(1), '1200');
      await t.enterText(fields.at(2), '200');
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Create goal'));
      await settle(t);
      var goals = await t.runAsync(() => db.watchGoals().first);
      expect(goals!.single.purpose, 'purchase');
      expect(goals.single.icon, 'laptop', reason: 'the icon follows the name');
      expect(find.text('New laptop'), findsOneWidget);
      expect(find.textContaining('€1,000.00 to go'), findsWidgets);

      // Taking out more than is there is refused.
      await t.tap(find.text('Take out'));
      await settle(t);
      await t.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, '500');
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton)));
      await settle(t);
      expect(find.textContaining('There is €200.00 in this goal'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settle(t);

      // Add the rest: the card offers to mark it bought.
      await t.tap(find.text('Add money'));
      await settle(t);
      await t.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, '1000');
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton)));
      await settle(t);
      expect(find.text('You have the full amount'), findsOneWidget);
      await t.tap(find.text('Mark as bought'));
      await settle(t);
      expect(find.text('Bought'), findsOneWidget);
      goals = await t.runAsync(() => db.watchGoals().first);
      expect(goals!.single.archived, isTrue);

      // Delete from the sheet, then Undo brings back the goal and its history.
      await t.tap(find.text('New laptop'));
      await settle(t);
      expect(find.text('History'), findsOneWidget);
      await t.ensureVisible(find.widgetWithText(TextButton, 'Delete'));
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(t);
      expect(await t.runAsync(() => db.watchGoals().first), isEmpty);
      await t.tap(find.text('Undo'));
      await settle(t);
      expect((await t.runAsync(() => db.watchGoals().first))!.single.name, 'New laptop');
      expect((await t.runAsync(() => db.watchMoves().first))!.length, 2);
      await done(t, db);
    });

    testWidgets('a dated goal shows what it takes per month and whether it is on track', (t) async {
      final db = await pumpPage(t, _phone, () => const WalletPage(initialTab: 3), demo: false);
      // One write per runAsync, with a pump between, so the page's streams keep up.
      await t.runAsync(
        () => db.saveGoal(SavingsGoalsCompanion.insert(name: 'Rainy day', targetCents: 100000, color: 1)),
      );
      await settle(t);
      final id = await t.runAsync(
        () => _purchase(db, 'Trip', 120000, by: DateTime.now().add(const Duration(days: 200))),
      );
      await settle(t);
      await t.runAsync(() => db.addMove(id!, 2000));
      await settle(t);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.textContaining('a month or'), findsOneWidget);
      expect(find.text('On track'), findsOneWidget);
      // Savings goals stay on their own tab.
      expect(find.text('Rainy day'), findsNothing);
      await done(t, db);
    });
  });
}
