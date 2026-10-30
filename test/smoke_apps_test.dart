import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_model.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/apps/internships/internships_page.dart';
import 'package:hub/apps/mail/mail_page.dart';
import 'package:hub/apps/news/news_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/weather/weather_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';

const _sizes = [Size(360, 740), Size(320, 568)];

/// Pumps [page] inside Hub at each phone size, light and dark, and runs [body].
void smoke(String name, Widget Function() page, Future<void> Function(WidgetTester t, AppDatabase db) body) {
  for (final size in _sizes) {
    for (final dark in [false, true]) {
      testWidgets('$name ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        final settings = AppSettings(db);
        await tester.runAsync(settings.load);
        await tester.pumpWidget(
          Hub(
            db: db,
            settings: settings,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: page(),
            ),
          ),
        );
        await settle(tester);
        await body(tester, db);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        await tester.runAsync(db.close);
      });
    }
  }
}

/// Lets database streams deliver and animations finish.
Future<void> settle(WidgetTester t, [int ms = 120]) async {
  await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> tapIf(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.tap(f.last, warnIfMissed: false);
  await settle(t);
}

Future<void> back(WidgetTester t) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).last);
  nav.maybePop();
  await settle(t);
}

void main() {
  smoke('todo', () => const TodoPage(), (t, db) async {
    await t.enterText(find.byType(TextField).first, 'gym friday 7pm every week !');
    await t.pump();
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t, 200);
    expect(find.text('gym'), findsOneWidget);
    final todo = (await t.runAsync(() => db.select(db.todos).get()))!.singleWhere((x) => x.title == 'gym');
    expect(todo.repeat, 'weekly');
    expect(todo.important, isTrue);
    expect(todo.remindAt!.weekday, DateTime.friday);
    expect(todo.remindAt!.hour, 19);

    await t.enterText(find.byType(TextField).first, 'Read a book tomorrow');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t, 200);

    // Tick, undo, tick again: the repeating task never leaves two copies.
    await t.runAsync(() => db.setTodoDone(todo.id, true));
    await t.runAsync(() => db.setTodoDone(todo.id, false));
    await t.runAsync(() => db.setTodoDone(todo.id, true));
    await settle(t);
    final open = (await t.runAsync(() => db.select(db.todos).get()))!.where((x) => x.title == 'gym' && !x.done);
    expect(open.length, 1);
    expect(daysBetween(todo.due!, open.single.due!), 7);
    expect(open.single.remindAt!.hour, 19);

    await t.longPress(find.text('Read a book'));
    await settle(t);
    await tapIf(t, find.text('Mark important'));
    await tapIf(t, find.byTooltip('Sort'));
    await t.tapAt(const Offset(5, 5));
    await settle(t);
    for (final chip in find.byType(FilterChip).evaluate().toList()) {
      await t.tap(find.byWidget(chip.widget), warnIfMissed: false);
      await settle(t);
    }
  });

  smoke('notes', () => const NotesPage(), (t, db) async {
    await tapIf(t, find.byTooltip('New note'));
    await t.enterText(find.byType(TextField).at(0), 'Groceries');
    await t.enterText(find.byType(TextField).at(1), 'Milk');
    await tapIf(t, find.byTooltip('Checklist item'));
    await t.pump(const Duration(milliseconds: 700));
    await settle(t);
    await back(t);
    await settle(t, 200);
    final notes = (await t.runAsync(() => db.select(db.notes).get()))!;
    expect(notes.length, 1, reason: 'one note, not a duplicate');
    expect(find.text('Groceries'), findsWidgets);
    await t.longPress(find.text('Groceries').first);
    await settle(t);
    await tapIf(t, find.text('Pin to the top'));
    await t.longPress(find.text('Groceries').first);
    await settle(t);
    await tapIf(t, find.text('Delete'));
    await settle(t);
    await tapIf(t, find.text('Undo'));
    await tapIf(t, find.byTooltip('Sort'));
    await t.tapAt(const Offset(5, 5));
    await settle(t);
  });

  smoke('calendar', () => const CalendarPage(), (t, db) async {
    final cal = (await t.runAsync(() => db.watchCalendars().first))!.first;
    final now = DateTime.now();
    await t.runAsync(
      () => db.saveEvent(
        EventsCompanion.insert(
          calendarId: cal.id,
          title: 'Standup',
          start: DateTime(now.year, now.month, now.day, 9),
          end: DateTime(now.year, now.month, now.day, 10),
          repeat: const Value('daily'),
        ),
      ),
    );
    await settle(t);
    for (final v in ['Day', 'Week', 'Agenda', 'Month']) {
      await tapIf(t, find.byTooltip('View'));
      await tapIf(t, find.text(v));
      for (var i = 0; i < 3; i++) {
        await tapIf(t, find.byTooltip('Next'));
      }
      await tapIf(t, find.byTooltip('Previous'));
      await tapIf(t, find.text('Today'));
    }
    await tapIf(t, find.byTooltip('New event'));
    if (find.widgetWithText(TextField, 'Add title').evaluate().isNotEmpty) {
      await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Dentist');
      await tapIf(t, find.text('Save'));
    }
    await settle(t);
  });

  smoke('habits', () => const HabitsPage(), (t, db) async {
    await tapIf(t, find.text('New habit'));
    await t.enterText(find.byType(TextField).first, 'Read');
    await tapIf(t, find.text('Save'));
    await settle(t, 200);
    expect(find.text('Read'), findsWidgets);
  });

  smoke('internships', () => const InternshipsPage(), (t, db) async {
    await tapIf(t, find.text('Add'));
    await t.enterText(find.byType(TextField).first, 'Acme');
    await tapIf(t, find.text('Save'));
    await settle(t, 200);
    expect(find.text('Acme'), findsWidgets);
    await tapIf(t, find.byTooltip('Move to'));
    await tapIf(t, find.text('Applied'));
    await settle(t);
  });

  for (final (name, page) in [
    ('weather', () => const WeatherPage() as Widget),
    ('news', () => const NewsPage() as Widget),
    ('mail', () => const MailPage() as Widget),
  ]) {
    smoke(name, page, (t, db) async {
      // Requests fail in tests; give them time and make sure nothing spins forever.
      for (var i = 0; i < 5; i++) {
        await settle(t, 300);
      }
      await t.pump(const Duration(seconds: 30));
      await settle(t, 300);
      expect(find.byType(CircularProgressIndicator), findsNothing, reason: '$name keeps spinning offline');
    });
  }

  test('all-day events over the October clock change stay on their days', () {
    final e = Event(
      id: 1,
      calendarId: 1,
      title: 'Trip',
      start: DateTime(2026, 10, 24),
      end: DateTime(2026, 10, 26),
      allDay: true,
      location: '',
      notes: '',
      repeat: 'weekly',
      remindMinutes: null,
      uid: null,
    );
    final cal = Calendar(id: 1, name: 'x', color: 0, visible: true, icsUrl: null, syncedAt: null);
    final occ = expand([e], {1: cal}, DateTime(2026, 10, 20), DateTime(2026, 11, 10));
    for (final o in occ) {
      expect(o.end.hour, 0);
      expect(o.touches(addDays(dateOnly(o.end), 0)), isFalse);
    }
  });
}
