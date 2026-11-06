// The calendar's quick-create defaults, day list and event sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_model.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/calendar/event_editor.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/format.dart';

import 'flows_test.dart' show done, pumpPage, settle;

const _phone = (Size(412, 915), false, 1.0);

Occurrence occ(DateTime start, DateTime end, {bool allDay = false}) => Occurrence(
  Event(
    id: 1,
    calendarId: 1,
    title: 'x',
    location: '',
    notes: '',
    start: start,
    end: end,
    allDay: allDay,
    repeat: 'none',
    remindMinutes: null,
  ),
  start,
  end,
  Colors.blue,
);

void main() {
  personalEdition = false;

  group('new event defaults', () {
    test('today starts at the next full hour', () {
      final now = DateTime(2026, 11, 6, 10, 12);
      expect(defaultEventStart(now, now), DateTime(2026, 11, 6, 11));
      expect(defaultEventStart(now, DateTime(2026, 11, 6, 10)), DateTime(2026, 11, 6, 11));
    });

    test('late in the evening rolls over to midnight', () {
      final now = DateTime(2026, 11, 6, 23, 40);
      expect(defaultEventStart(now, now), DateTime(2026, 11, 7));
    });

    test('another day starts at 9:00', () {
      expect(defaultEventStart(DateTime(2026, 11, 9), DateTime(2026, 11, 6, 15, 5)), DateTime(2026, 11, 9, 9));
    });
  });

  group('reminders', () {
    test('timed and all-day events get their own choices', () {
      expect(reminderChoices(allDay: false).keys, containsAll([null, 0, 15, 60, 1440]));
      expect(reminderChoices(allDay: false).keys, isNot(contains(-540)));
      expect(reminderChoices(allDay: true).keys, containsAll([null, -540, 900, 9540]));
      expect(reminderChoices(allDay: true).keys, isNot(contains(15)));
    });

    test('switching to all day moves a minutes-before reminder to the morning', () {
      expect(reminderAfterAllDayToggle(15, allDay: true), -540);
      expect(reminderAfterAllDayToggle(1440, allDay: true), 1440);
      expect(reminderAfterAllDayToggle(-540, allDay: false), 15);
      expect(reminderAfterAllDayToggle(null, allDay: true), isNull);
    });
  });

  group('time labels', () {
    test('a plain event shows its range', () {
      final o = occ(DateTime(2026, 11, 6, 10), DateTime(2026, 11, 6, 11, 30));
      expect(timeOnDay(o, DateTime(2026, 11, 6)), '10:00 – 11:30');
    });

    test('an event past midnight reads from and until', () {
      final o = occ(DateTime(2026, 11, 6, 22), DateTime(2026, 11, 7, 2));
      expect(timeOnDay(o, DateTime(2026, 11, 6)), 'From 22:00');
      expect(timeOnDay(o, DateTime(2026, 11, 7)), 'Until 02:00');
    });

    test('an event ending exactly at midnight stays on its day', () {
      final o = occ(DateTime(2026, 11, 6, 20), DateTime(2026, 11, 7));
      expect(timeOnDay(o, DateTime(2026, 11, 6)), '20:00 – 00:00');
    });

    test('multi-day all-day events count their days', () {
      final o = occ(DateTime(2026, 11, 2), DateTime(2026, 11, 7), allDay: true);
      expect(timeOnDay(o, DateTime(2026, 11, 2)), 'Day 1 of 5');
      expect(timeOnDay(o, DateTime(2026, 11, 6)), 'Day 5 of 5');
      expect(
        timeOnDay(occ(DateTime(2026, 11, 2), DateTime(2026, 11, 3), allDay: true), DateTime(2026, 11, 2)),
        'All day',
      );
    });

    test('how soon an event starts', () {
      final now = DateTime(2026, 11, 6, 10);
      expect(startsIn(occ(DateTime(2026, 11, 6, 10, 20), DateTime(2026, 11, 6, 11)), now), 'In 20 min');
      expect(startsIn(occ(DateTime(2026, 11, 6, 11, 30), DateTime(2026, 11, 6, 12)), now), 'In 1 h 30 min');
      expect(startsIn(occ(DateTime(2026, 11, 6, 9), DateTime(2026, 11, 6, 11)), now), 'Now');
      expect(startsIn(occ(DateTime(2026, 11, 7, 9), DateTime(2026, 11, 7, 10)), now), 'Tomorrow');
      expect(startsIn(occ(DateTime(2026, 11, 9, 9), DateTime(2026, 11, 9, 10)), now), 'In 3 days');
      expect(startsIn(occ(DateTime(2026, 11, 6, 8), DateTime(2026, 11, 6, 9)), now), isNull);
      expect(startsIn(occ(DateTime(2026, 12, 6, 8), DateTime(2026, 12, 6, 9)), now), isNull);
    });
  });

  testWidgets('an empty day offers to add an event on that day', (t) async {
    final db = await pumpPage(t, _phone, () => const CalendarPage(), demo: false);
    await settle(t);
    expect(find.text('Nothing planned'), findsOneWidget);
    await t.tap(find.text('Add event'));
    await settle(t);
    expect(find.text('New event'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Dentist');
    await t.tap(find.text('Save'));
    await settle(t);
    final e = (await t.runAsync(() => db.select(db.events).getSingle()))!;
    expect(e.title, 'Dentist');
    expect(e.start.minute, 0, reason: 'starts on a full hour');
    expect(e.end.difference(e.start), const Duration(hours: 1));
    expect(find.text('Dentist'), findsWidgets, reason: 'shows in the day list');
    await done(t, db);
  });

  testWidgets('duplicate from the event sheet makes a second event', (t) async {
    final db = await pumpPage(t, _phone, () => const CalendarPage(), demo: false);
    final cal = (await t.runAsync(() => db.watchCalendars().first))!.first;
    final today = dateOnly(DateTime.now());
    await t.runAsync(
      () => db.saveEvent(
        EventsCompanion.insert(
          calendarId: cal.id,
          title: 'Haircut',
          start: today.add(const Duration(hours: 23)),
          end: today.add(const Duration(hours: 23, minutes: 30)),
        ),
      ),
    );
    await settle(t);
    await t.tap(find.text('Haircut'));
    await settle(t);
    expect(find.text('Duplicate'), findsOneWidget);
    await t.tap(find.text('Duplicate'));
    await settle(t);
    await t.tap(find.text('Save'));
    await settle(t);
    final events = (await t.runAsync(() => db.select(db.events).get()))!;
    expect(events.map((e) => e.title), ['Haircut', 'Haircut']);
    expect(events.map((e) => e.start).toSet().length, 1);
    await done(t, db);
  });

  testWidgets('all day switches the reminder to the morning of the day', (t) async {
    final db = await pumpPage(
      t,
      _phone,
      () => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openEventEditor(context, start: DateTime(2026, 11, 9, 9)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      demo: false,
    );
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('15 minutes before'), findsOneWidget);
    await t.tap(find.text('All day'));
    await settle(t);
    expect(find.text('On the day at 9:00'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Exam');
    await t.tap(find.text('Save'));
    await settle(t);
    final e = (await t.runAsync(() => db.select(db.events).getSingle()))!;
    expect((e.allDay, e.remindMinutes), (true, -540));
    await done(t, db);
  });
}
