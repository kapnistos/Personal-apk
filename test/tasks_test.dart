import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';

Todo todo(String title, {DateTime? due, DateTime? remindAt, bool important = false, DateTime? created}) => Todo(
  id: title.hashCode,
  title: title,
  details: '',
  due: due,
  done: false,
  important: important,
  remindAt: remindAt,
  createdAt: created ?? DateTime(2026, 10, 1),
  repeat: 'none',
);

Note note(String title, {required DateTime created, required DateTime updated, bool pinned = false}) =>
    Note(id: title.hashCode, title: title, body: '', pinned: pinned, createdAt: created, updatedAt: updated, color: 0);

Future<void> pumpWithDb(
  WidgetTester tester,
  Widget Function(AppDatabase, AppSettings) build,
  Future<void> Function(AppDatabase db) body,
) async {
  final db = AppDatabase(NativeDatabase.memory());
  final settings = AppSettings(db);
  await tester.runAsync(settings.load);
  await tester.pumpWidget(build(db, settings));
  await tester.pump(const Duration(milliseconds: 50));
  await body(db);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
  await tester.runAsync(db.close);
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('task sorting', () {
    final a = todo('banana', due: DateTime(2026, 11, 3), created: DateTime(2026, 10, 1));
    final b = todo('apple', due: DateTime(2026, 11, 1), created: DateTime(2026, 10, 5));
    final c = todo('cherry', important: true, created: DateTime(2026, 10, 3));

    List<String> sorted(TodoSort s) => ([a, b, c]..sort((x, y) => compareTodos(x, y, s))).map((t) => t.title).toList();

    test('important first, then by date', () => expect(sorted(TodoSort.smart), ['cherry', 'apple', 'banana']));
    test('by date puts undated last', () => expect(sorted(TodoSort.due), ['apple', 'banana', 'cherry']));
    test('newest first', () => expect(sorted(TodoSort.added), ['apple', 'cherry', 'banana']));
    test('a to z', () => expect(sorted(TodoSort.title), ['apple', 'banana', 'cherry']));
  });

  test('moving a task keeps its reminder time', () {
    final t = todo('x', due: DateTime(2026, 10, 30), remindAt: DateTime(2026, 10, 30, 18, 30));
    final moved = moveTodoTo(t, DateTime(2026, 11, 2));
    expect(moved.due, DateTime(2026, 11, 2));
    expect(moved.remindAt, DateTime(2026, 11, 2, 18, 30));
    final cleared = moveTodoTo(t, null);
    expect(cleared.due, isNull);
    expect(cleared.remindAt, isNull);
  });

  test('quick add chips describe what was understood', () {
    final q = parseQuickTask('Gym every monday 18:00 !', now: DateTime(2026, 10, 30, 10));
    final labels = quickTaskChips(q).map((c) => c.$2).toList();
    expect(labels, ['Monday', '18:00', 'Every week', 'Important']);
    expect(quickTaskChips(parseQuickTask('Just a title')), isEmpty);
  });

  test('notes sort by edit, creation or title', () {
    final x = note('beta', created: DateTime(2026, 1, 1), updated: DateTime(2026, 10, 1));
    final y = note('alpha', created: DateTime(2026, 5, 1), updated: DateTime(2026, 9, 1));
    expect(sortNotes([y, x], NoteSort.edited).first.title, 'beta');
    expect(sortNotes([x, y], NoteSort.created).first.title, 'alpha');
    expect(sortNotes([x, y], NoteSort.title).first.title, 'alpha');
  });

  group('habits', () {
    final h = Habit(
      id: 1,
      name: 'Read',
      icon: 'book',
      color: 0,
      days: '1111111',
      remindAt: '',
      position: 0,
      archived: false,
      createdAt: DateTime(2026, 1, 1),
    );
    test('best streak finds the longest run', () {
      final done = {'2026-10-01', '2026-10-02', '2026-10-03', '2026-10-10', '2026-10-11'};
      expect(habitBestStreak(h, done, now: DateTime(2026, 10, 30)), 3);
      expect(habitBestStreak(h, {}, now: DateTime(2026, 10, 30)), 0);
    });
  });

  test('calendar blocks use clock time on summer time days', () {
    // 29 March 2026: clocks go forward in Europe. A 10:00 event still sits at 10:00.
    final day = DateTime(2026, 3, 29);
    expect(minutesOnDay(DateTime(2026, 3, 29, 10), DateTime(2026, 3, 29, 11, 30), day), (600, 690));
    expect(minutesOnDay(DateTime(2026, 3, 28, 22), DateTime(2026, 3, 30, 1), day), (0, 1440));
  });

  testWidgets('quick add shows the parsed date while typing', (tester) async {
    await pumpWithDb(
      tester,
      (db, s) => Hub(
        db: db,
        settings: s,
        child: const MaterialApp(home: TodoPage()),
      ),
      (db) async {
        await tester.enterText(find.byType(TextField), 'Pay rent tomorrow !');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('quick-Tomorrow')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick-Important')), findsOneWidget);
      },
    );
  });

  testWidgets('holding a task moves it to tomorrow', (tester) async {
    await pumpWithDb(
      tester,
      (db, s) => Hub(
        db: db,
        settings: s,
        child: const MaterialApp(home: TodoPage()),
      ),
      (db) async {
        await tester.runAsync(() => db.addTodo('Water plants', important: true, due: DateTime.now()));
        await settle(tester);
        await tester.longPress(find.text('Water plants'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.widgetWithText(ActionChip, 'Tomorrow'));
        await settle(tester);
        expect(find.text('Moved to tomorrow'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
      },
    );
  });

  testWidgets('habit history ticks a past day', (tester) async {
    await pumpWithDb(
      tester,
      (db, s) => Hub(
        db: db,
        settings: s,
        child: const MaterialApp(home: HabitsPage()),
      ),
      (db) async {
        await tester.runAsync(() => db.saveHabit(HabitsCompanion.insert(name: 'Read', color: 0xFF1F7A5A)));
        await settle(tester);
        await tester.longPress(find.text('Read'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Best'), findsOneWidget);
        final first = DateTime(DateTime.now().year, DateTime.now().month, 1);
        await tester.tap(find.byKey(ValueKey('habit-day-${AppDatabase.dayKey(first)}')));
        await settle(tester);
        final checks = (await tester.runAsync(() => db.habitChecksSince(first)))!;
        expect(checks.map((c) => c.day), contains(AppDatabase.dayKey(first)));
      },
    );
  });
}
