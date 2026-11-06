// One test per fix in the quality pass (see docs/ROADMAP.md), so none of them comes back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/weather/weather_service.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/widgets.dart';
import 'package:hub/shell/home_page.dart';
import 'package:hub/shell/search_page.dart';

import 'flows_test.dart' show done, pumpPage, settle;

const _phone = (Size(412, 915), false, 1.0);

Forecast _forecast(double temperature) {
  final now = DateTime.now();
  final h0 = DateTime(now.year, now.month, now.day, now.hour);
  final today = dateOnly(now);
  return Forecast(
    temperature: temperature,
    feelsLike: temperature,
    humidity: 70,
    wind: 10,
    code: 3,
    isDay: true,
    hours: [
      for (var i = 0; i < 24; i++)
        HourForecast(time: h0.add(Duration(hours: i)), temperature: 10, code: 3, rainChance: 0),
    ],
    days: [
      DayForecast(
        date: today,
        max: 14,
        min: 6,
        code: 3,
        rainChance: 0,
        sunrise: today.add(const Duration(hours: 7)),
        sunset: today.add(const Duration(hours: 17)),
      ),
    ],
    fetchedAt: DateTime.now(),
  );
}

/// The steps a phone goes through when the app is put away, and when it comes back.
void _background(WidgetTester t) {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
}

void _foreground(WidgetTester t) {
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  personalEdition = false;

  group('rain in the next hours', () {
    final now = DateTime(2026, 11, 6, 13, 2);
    Nowcast cast(DateTime from, int steps, {double mm = 1}) => Nowcast(
      source: 'test',
      points: [for (var i = 0; i < steps; i++) RainPoint(from.add(Duration(minutes: 5 * i)), mm)],
    );

    test('starts at the step that holds now', () {
      final n = cast(DateTime(2026, 11, 6, 12, 0), 24).upcoming(now);
      expect(n.points.first.time, DateTime(2026, 11, 6, 13, 0));
      expect(n.points.last.time, DateTime(2026, 11, 6, 13, 55));
    });

    test('a forecast that has fully passed says nothing about rain any more', () {
      final n = cast(DateTime(2026, 11, 6, 9, 0), 24).upcoming(now);
      expect(n.points, isEmpty);
      expect(n.summary((d) => '$d'), 'No short-term data');
    });

    test('one fetched just now is left as it is', () {
      final fresh = cast(DateTime(2026, 11, 6, 13, 0), 24);
      expect(fresh.upcoming(now).points.length, 24);
    });
  });

  testWidgets('reading a note, or moving the cursor in it, does not count as an edit', (t) async {
    final db = await pumpPage(t, _phone, () => const NotesPage(), demo: false);
    final id = (await t.runAsync(() => db.saveNote(title: 'Codes', body: 'Bike shed 4471')))!;
    final before = (await t.runAsync(() => (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle()))!;
    await settle(t);
    await t.tap(find.text('Codes'));
    await settle(t);
    // Put the cursor in the body, as a reader tapping around would.
    await t.tap(find.text('Bike shed 4471'));
    await t.pump(const Duration(seconds: 1));
    await settle(t);
    await t.pageBack();
    await settle(t);
    final after = (await t.runAsync(() => (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle()))!;
    expect(after.updatedAt, before.updatedAt);
    await done(t, db);
  });

  testWidgets('a note is saved the moment the app goes to the background', (t) async {
    final db = await pumpPage(t, _phone, () => const NotesPage(), demo: false);
    final id = (await t.runAsync(() => db.saveNote(title: 'Ideas', body: 'One')))!;
    await settle(t);
    await t.tap(find.text('Ideas'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'One'), 'One and two');
    // No wait for the save delay: the phone may close the app right after this.
    _background(t);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final note = (await t.runAsync(() => (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle()))!;
    expect(note.body, 'One and two');
    _foreground(t);
    await settle(t);
    await done(t, db);
  });

  testWidgets('search results follow changes made from them', (t) async {
    final db = await pumpPage(t, _phone, () => const SearchPage(), demo: false);
    await t.runAsync(() => db.addTodo('Renew passport'));
    final noteId = (await t.runAsync(() => db.saveNote(title: 'Passport photos', body: 'Kruidvat')))!;
    await t.enterText(find.byType(TextField), 'passport');
    await t.pump(const Duration(milliseconds: 300));
    await settle(t);
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Passport photos'), findsOneWidget);

    // Ticked off right in the results: the box shows it.
    await t.tap(find.byType(Checkbox));
    await t.pump(const Duration(milliseconds: 300));
    await settle(t);
    expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    // Deleted elsewhere: it leaves the results instead of opening a note that is gone.
    await t.runAsync(() => db.deleteNote(noteId));
    await t.pump(const Duration(milliseconds: 300));
    await settle(t);
    expect(find.text('Passport photos'), findsNothing);
    await t.pump(const Duration(seconds: 5));
    await done(t, db);
  });

  testWidgets('tasks under Today do not repeat the word Today', (t) async {
    final db = await pumpPage(t, _phone, () => const TodoPage(), demo: false);
    final today = dateOnly(DateTime.now());
    await t.runAsync(() => db.addTodo('Pay rent', due: today, remindAt: today.add(const Duration(hours: 18))));
    await t.runAsync(() => db.addTodo('Old one', due: addDays(today, -2)));
    await settle(t);
    // "Today" is the group heading (and the filter pill), not repeated under the task.
    expect(find.textContaining('18:00'), findsOneWidget);
    final line = t.widget<Text>(
      find
          .descendant(
            of: find.ancestor(of: find.text('Pay rent'), matching: find.byType(Column)).first,
            matching: find.byType(Text),
          )
          .last,
    );
    expect(line.textSpan!.toPlainText(), isNot(contains('Today')));
    // An overdue task still says which day it was due.
    expect(find.textContaining(friendlyDay(addDays(today, -2))), findsOneWidget);
    await done(t, db);
  });

  testWidgets('the clock text moves on by itself and after the app comes back', (t) async {
    var builds = 0;
    await t.pumpWidget(
      ClockBuilder(
        builder: (_, now) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    expect(builds, 1);
    await t.pump(const Duration(minutes: 1, seconds: 1));
    expect(builds, 2);
    _background(t);
    _foreground(t);
    await t.pump();
    expect(builds, 3);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the weather on Home loads again when the app comes back', (t) async {
    const lat = 41.123, lon = 23.456;
    WeatherService.instance.seed(lat, lon, _forecast(11), Nowcast(points: const [], source: 'test'));
    final db = await pumpPage(
      t,
      _phone,
      () => const Scaffold(body: SingleChildScrollView(child: WeatherHero())),
      demo: false,
    );
    await t.runAsync(() => db.addCity('Test town', '', lat, lon));
    await settle(t);
    final ctx = t.element(find.byType(WeatherHero));
    final id = (await t.runAsync(() => db.select(db.cities).get()))!.firstWhere((c) => c.name == 'Test town').id;
    await t.runAsync(() => ctx.settings.setRaw('weather.city', '$id'));
    await settle(t);
    expect(find.text('11°'), findsWidgets);

    WeatherService.instance.seed(lat, lon, _forecast(19), Nowcast(points: const [], source: 'test'));
    _background(t);
    _foreground(t);
    await settle(t);
    expect(find.text('19°'), findsWidgets);
    await done(t, db);
  });
}
