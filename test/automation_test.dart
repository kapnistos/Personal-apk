import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/core/automations.dart';
import 'package:hub/core/backup.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/reminders.dart';

void main() {
  final now = DateTime(2026, 10, 30, 8); // A Friday morning.

  Future<AppDatabase> seeded() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.delete(db.subscriptions).go();
    await db.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Rent',
        amountCents: 98000,
        kind: EntryKind.subscription,
        category: 'Rent',
        account: const Value('ABN AMRO'),
        nextDate: DateTime(2026, 11, 1),
      ),
    );
    final abn = (await db.watchAccounts().first).first;
    await db.setAccountBalance(abn.id, 100000, at: DateTime(2026, 10, 29));
    await db.addTodo('Report', due: DateTime(2026, 10, 30));
    await db.addTodo('Late one', due: DateTime(2026, 10, 27));
    return db;
  }

  test('briefing, bill reminder, low balance and weekly review are planned', () async {
    final db = await seeded();
    final plan = await planAutomations(db, now: now);
    final morning = plan.where((p) => p.id >= 500000 && p.id < 510000).toList();
    // Today's 07:30 has passed; the next six mornings remain.
    expect(morning.length, 6);
    expect(morning.first.at, DateTime(2026, 10, 31, 7, 30));
    final sunday = morning.firstWhere((p) => p.at.day == 1);
    expect(sunday.body, contains('Rent €980 due'));

    final bill = plan.singleWhere((p) => p.title.startsWith('Tomorrow: Rent'));
    expect(bill.at, DateTime(2026, 10, 31, 18));
    expect(bill.body, 'From ABN AMRO');

    // 1000 - 980 = 20, under the default 100 threshold: warn two days before, which is now-ish.
    final low = plan.singleWhere((p) => p.title == 'ABN AMRO may run low');
    expect(low.at, DateTime(2026, 10, 30, 9));
    expect(low.body, contains('€20'));

    final weekly = plan.singleWhere((p) => p.title == 'Your week ahead');
    expect(weekly.at, DateTime(2026, 11, 1, 19));

    final overdue = plan.singleWhere((p) => p.title == '1 overdue task');
    expect(overdue.body, 'Late one');
    await db.close();
  });

  test('automations can be switched off', () async {
    final db = await seeded();
    for (final k in ['auto.briefing', 'auto.bills', 'auto.lowBalance', 'auto.weekly', 'auto.overdue']) {
      await db.writeSetting(k, 'off');
    }
    expect(await planAutomations(db, now: now), isEmpty);
    await db.close();
  });

  test('a backup restores into an empty install', () async {
    final db = await seeded();
    await db.saveNote(title: 'Precious', body: 'Do not lose');
    final json = await backupJson(db);
    await db.close();

    final fresh = AppDatabase(NativeDatabase.memory());
    final n = await restoreBackup(fresh, json);
    expect(n, greaterThan(5));
    expect((await fresh.watchNotes().first).single.title, 'Precious');
    expect((await fresh.watchTodos().first).map((t) => t.title), containsAll(['Report', 'Late one']));
    expect((await fresh.watchSubscriptions().first).map((s) => s.name), contains('Rent'));
    expect((await fresh.watchAccounts().first).first.balanceCents, 100000);
    // Restoring twice does not duplicate anything.
    await restoreBackup(fresh, json);
    expect((await fresh.watchNotes().first).length, 1);
    await fresh.close();
  });

  test('a replacing import leaves exactly what the backup holds', () async {
    final db = await seeded();
    await db.saveNote(title: 'In the backup', body: '');
    final json = await backupJson(db);
    await db.saveNote(title: 'Added later', body: '');
    await restoreBackup(db, json, replace: true);
    expect((await db.watchNotes().first).map((n) => n.title), ['In the backup']);
    // Only the note that is really gone is marked deleted for sync.
    final tombs = await db.customSelect("SELECT tbl FROM sync_tombstones WHERE tbl = 'notes'").get();
    expect(tombs, hasLength(1));
    await db.close();
  });

  test('habit streaks skip days the habit does not apply to', () {
    final h = Habit(
      id: 1,
      name: 'Gym',
      icon: 'gym',
      color: 0,
      days: '1010100', // Mon, Wed, Fri
      remindAt: '',
      archived: false,
      position: 0,
      createdAt: DateTime(2026),
    );
    final done = {'2026-10-26', '2026-10-28', '2026-10-30'};
    expect(habitStreak(h, done, now: DateTime(2026, 10, 30)), 3);
    // Saturday: Friday counts, the weekend doesn't break it.
    expect(habitStreak(h, done, now: DateTime(2026, 10, 31)), 3);
    expect(habitStreak(h, {'2026-10-26', '2026-10-30'}, now: DateTime(2026, 10, 30)), 1);
  });

  test('the reminder plan is stable, so an unchanged schedule is left alone', () async {
    final db = await seeded();
    await db.addTodo('Call the dentist', remindAt: DateTime(2026, 10, 30, 15));
    await db.addTodo('Old reminder', remindAt: DateTime(2026, 10, 29, 15));
    final a = await planReminders(db, now);
    final b = await planReminders(db, now);
    expect(a.join('\n'), b.join('\n'));
    final todo = a.singleWhere((r) => r.payload.startsWith('todo:'));
    expect(todo.title, 'Call the dentist');
    expect(todo.todo, isTrue);
    expect(a.where((r) => r.quiet), isNotEmpty);
    await db.close();
  });
}
