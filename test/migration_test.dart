import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';

void main() {
  test('a version 4 database upgrades and keeps its data', () async {
    final dir = Directory.systemTemp.createTempSync('hub');
    final file = File('${dir.path}/hub.db');
    File('test/fixtures/v4.db').copySync(file.path);
    final db = AppDatabase(NativeDatabase(file));
    final todos = await db.watchTodos().first;
    expect(todos.single.title, 'Old task');
    expect(todos.single.repeat, 'none');
    expect((await db.watchNotes().first).single.title, 'Old note');
    final spaces = await db.watchSpaces().first;
    expect(spaces.map((s) => s.name), ['Job', 'Lab research', 'University']);
    final cals = await db.watchCalendars().first;
    expect(cals.map((c) => c.name), containsAll(['Work', 'Lab', 'Study']));
    expect(cals.length, 4);
    // New tables sync like the old ones.
    await db.addMove(await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Trip', targetCents: 1000, color: 1)), 500);
    final gid = await db.customSelect('SELECT gid FROM savings_moves').getSingle();
    expect(gid.read<String?>('gid'), isNotNull);
    final spaceGid = await db.customSelect("SELECT gid FROM spaces WHERE name = 'Job'").getSingle();
    expect(spaceGid.read<String>('gid'), 'seed-job');
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('finishing a repeating task adds the next one', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final today = dateOnly(DateTime.now());
    final id = await db.addTodo('Gym', due: today, remindAt: today.add(const Duration(hours: 18)), repeat: 'weekly');
    await db.setTodoDone(id, true);
    final todos = await db.watchTodos().first;
    final open = todos.where((t) => !t.done).single;
    expect(open.due, addDays(today, 7));
    expect(open.remindAt, DateTime(today.year, today.month, today.day + 7, 18));
    expect(open.repeat, 'weekly');
    await db.close();
  });

  test('work days are stored per day', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.setWorkDay(DateTime(2026, 10, 5), 'work', hours: 8);
    await db.setWorkDay(DateTime(2026, 10, 5), 'off');
    await db.setWorkDay(DateTime(2026, 10, 6), 'work');
    final days = await db.watchWorkDays(DateTime(2026, 10), DateTime(2026, 11)).first;
    expect({for (final d in days) d.day: d.status}, {'2026-10-05': 'off', '2026-10-06': 'work'});
    await db.close();
  });

  test('day math ignores summer time', () {
    // Summer time ended in Europe on 25 October 2026.
    expect(addDays(DateTime(2026, 10, 24), 7), DateTime(2026, 10, 31));
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(nextRepeat(DateTime(2026, 10, 30, 9), 'weekdays'), DateTime(2026, 11, 2, 9));
    expect(nextRepeat(DateTime(2026, 1, 31), 'monthly'), DateTime(2026, 2, 28));
  });
}
