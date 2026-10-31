// One test per bug fixed in the bug-hunt pass, so none of them comes back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/event_editor.dart';
import 'package:hub/apps/spaces/work_hours.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/insights.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/format.dart';

import 'flows_test.dart' show done, pumpPage, settle;

const _phone = (Size(412, 915), true, 1.3);

void main() {
  personalEdition = false;

  testWidgets('todo editor keeps what was typed when the sheet is swiped away', (t) async {
    final db = await pumpPage(t, _phone, () => const TodoPage(), demo: false);
    await t.runAsync(() => db.addTodo('Call the bank'));
    await settle(t);
    await t.tap(find.text('Call the bank'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Details'), 'Ask about the card');
    // Tap the dimmed page above the sheet, as a swipe down would.
    await t.tapAt(const Offset(200, 40));
    await settle(t);
    final todo = (await t.runAsync(() => db.select(db.todos).getSingle()))!;
    expect(todo.details, 'Ask about the card');
    await done(t, db);
  });

  testWidgets('duplicating a task keeps its details', (t) async {
    final db = await pumpPage(t, _phone, () => const TodoPage(), demo: false);
    await t.runAsync(() => db.addTodo('Pack', details: 'Passport, charger'));
    await settle(t);
    await t.longPress(find.text('Pack'));
    await settle(t);
    await t.tap(find.text('Duplicate'));
    await settle(t);
    final all = (await t.runAsync(() => db.select(db.todos).get()))!;
    expect(all.length, 2);
    expect(all.every((x) => x.details == 'Passport, charger'), isTrue);
    await done(t, db);
  });

  testWidgets('Clear all asks before deleting completed tasks', (t) async {
    final db = await pumpPage(t, _phone, () => const TodoPage(), demo: false);
    final id = (await t.runAsync(() => db.addTodo('Old')))!;
    await settle(t);
    await t.runAsync(() => db.setTodoDone(id, true));
    await settle(t);
    await t.ensureVisible(find.text('Done'));
    await t.pump();
    await t.tap(find.text('Done'));
    await settle(t);
    await t.tap(find.text('Clear all'));
    await settle(t);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect((await t.runAsync(() => db.select(db.todos).get()))!.length, 1);
    await done(t, db);
  });

  testWidgets('event editor asks before discarding changes on back', (t) async {
    final db = await pumpPage(
      t,
      _phone,
      () => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => openEventEditor(context), child: const Text('open')),
          ),
        ),
      ),
      demo: false,
    );
    await t.tap(find.text('open'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Dentist');
    await t.pump();
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    await nav.maybePop();
    await settle(t);
    expect(find.text('Discard changes?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await settle(t);
    expect(find.text('Dentist'), findsOneWidget);
    await t.tap(find.text('Save'));
    await settle(t);
    final events = (await t.runAsync(() => db.select(db.events).get()))!;
    expect(events.single.title, 'Dentist');
    expect(find.text('open'), findsOneWidget);
    await done(t, db);
  });

  test('Home money numbers come from the same plan as the Wallet hero', () {
    final now = DateTime(2026, 10, 10, 12);
    Entry e(int cents, DateTime d, EntryKind k) => Entry(
      id: d.day * 100 + cents % 97,
      date: d,
      amountCents: cents,
      kind: k,
      category: 'Food',
      note: '',
      account: '',
    );
    final entries = [
      e(5000, DateTime(2026, 10, 2), EntryKind.expense),
      e(95000, DateTime(2026, 10, 1), EntryKind.subscription),
      e(3000, DateTime(2026, 10, 20), EntryKind.expense), // Planned, not spent yet.
    ];
    final plan = monthSpendPlan(target: 180000, monthEntries: entries, subs: const [], now: now);
    expect(plan.spent, 100000);
    expect(plan.billsPaid, 95000);
    expect(spentSoFar(entries, now), 100000);
  });

  test('month hours for the dashboard match the Job page sums', () {
    final today = DateTime(2026, 10, 14); // A Wednesday.
    final days = [
      for (var d = 12; d <= 14; d++)
        WorkDay(day: AppDatabase.dayKey(DateTime(2026, 10, d)), status: 'work', hours: 9, note: ''),
    ];
    final s = monthHours(days, WorkSchedule.standard, today);
    expect(s.balance, 3);
    expect(hoursBalanceWords(s.balance), '+3 h overtime');
    expect(hoursBalanceWords(-2.5), '2.5 h owed');
    expect(addDays(today, 0), today);
  });
}
