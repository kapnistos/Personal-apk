import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/spaces/work_hours.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';

Map<String, WorkDay> log(Map<DateTime, (String, double?)> days) => {
  for (final MapEntry(key: d, value: (s, h)) in days.entries)
    AppDatabase.dayKey(d): WorkDay(day: AppDatabase.dayKey(d), status: s, hours: h, note: ''),
};

HoursSummary sum(DateTime from, DateTime to, Map<String, WorkDay> days, DateTime today, [WorkSchedule? s]) =>
    HoursSummary.of(from: from, to: to, days: days, schedule: s ?? WorkSchedule.standard, today: today);

void main() {
  group('WorkSchedule', () {
    test('reads, writes and falls back to 40 h Mon–Fri', () {
      expect(WorkSchedule.parse(null), WorkSchedule.standard);
      expect(WorkSchedule.parse('garbage'), WorkSchedule.standard);
      expect(WorkSchedule.parse('8,8,8,8'), WorkSchedule.standard);
      final s = WorkSchedule.parse('9,9,9,9,4,0,0');
      expect(s.weekly, 40);
      expect(s.even, isFalse);
      expect(WorkSchedule.parse(s.encode()), s);
      expect(WorkSchedule.standard.describe(), '40 h a week, Mon–Fri');
    });

    test('spreads a week over the chosen days', () {
      final s = WorkSchedule.spread(36, {1, 2, 3, 4});
      expect(s.hours, [9, 9, 9, 9, 0, 0, 0]);
      expect(s.describe(), '36 h a week, Mon–Thu');
      expect(WorkSchedule.spread(32, {1, 3, 5}).describe(), '32 h a week, 3 days');
      expect(WorkSchedule.parse(WorkSchedule.spread(32, {1, 3, 5}).encode()).weekly, closeTo(32, 1e-9));
      expect(WorkSchedule.spread(40, {}).weekly, 0);
    });
  });

  group('HoursSummary', () {
    // Monday 5 October 2026 to Monday 12 October.
    final mon = DateTime(2026, 10, 5);
    final next = addDays(mon, 7);

    test('a full logged week in the past: overtime and owed hours', () {
      final s = sum(
        mon,
        next,
        log({
          mon: ('work', 9),
          addDays(mon, 1): ('work', 8.5),
          addDays(mon, 2): ('remote', null), // a normal day
          addDays(mon, 3): ('work', 7),
          addDays(mon, 4): ('work', 8),
          addDays(mon, 5): ('work', 2), // Saturday: all overtime
        }),
        DateTime(2026, 10, 20),
      );
      expect(s.expected, 40);
      expect(s.worked, 42.5);
      expect(s.balance, 2.5);
      expect(s.remaining, -2.5);
      expect(s.perOpenDay, isNull);
      expect(s.openDays, 0);
    });

    test('holidays, sick days and public holidays lower what is expected', () {
      final s = sum(
        mon,
        next,
        log({
          mon: ('holiday', null),
          addDays(mon, 1): ('sick', 3), // hours on a sick day do not count
          addDays(mon, 2): ('public', null),
          addDays(mon, 3): ('work', 8),
          addDays(mon, 4): ('work', 8),
        }),
        DateTime(2026, 10, 20),
      );
      expect(s.expected, 16);
      expect(s.covered, 24);
      expect(s.worked, 16);
      expect(s.balance, 0);
    });

    test('a day off on a workday comes out of the balance', () {
      final s = sum(
        mon,
        next,
        log({
          mon: ('off', null),
          addDays(mon, 1): ('work', 10),
          addDays(mon, 2): ('work', 10),
          addDays(mon, 3): ('work', 10),
          addDays(mon, 4): ('work', 10),
          addDays(mon, 6): ('off', null), // Sunday off changes nothing
        }),
        DateTime(2026, 10, 20),
      );
      expect(s.expected, 40);
      expect(s.balance, 0);
    });

    test('past days not logged are left out, and counted', () {
      final s = sum(mon, next, log({mon: ('work', 9)}), DateTime(2026, 10, 20));
      expect(s.unloggedPast, 4); // Tue–Fri; the weekend has no hours
      expect(s.expected, 8);
      expect(s.balance, 1);
    });

    test('mid-week: worked, planned, open days and hours needed per day', () {
      // Today is Wednesday. Mon 9 h, Tue 9 h worked; Thursday planned 6 h; Wed and Fri open.
      final s = sum(
        mon,
        next,
        log({mon: ('work', 9), addDays(mon, 1): ('work', 9), addDays(mon, 3): ('work', 6)}),
        addDays(mon, 2),
      );
      expect(s.expected, 40);
      expect(s.worked, 18);
      expect(s.planned, 6);
      expect(s.openDays, 2);
      expect(s.openHours, 16);
      expect(s.remaining, 16);
      expect(s.perOpenDay, 8);
      expect(s.balance, 2); // only days up to today
      expect(s.projected, 0);
    });

    test('today counts as worked once logged, planned hours after it', () {
      final s = sum(mon, next, log({mon: ('work', 9), addDays(mon, 4): ('work', 4)}), mon);
      expect(s.worked, 9);
      expect(s.planned, 4);
      expect(s.openDays, 3);
      expect(s.remaining, 27);
      expect(s.perOpenDay, 9);
    });

    test('behind with no workdays left', () {
      final s = sum(mon, next, log({for (var i = 0; i < 5; i++) addDays(mon, i): ('work', 7)}), DateTime(2026, 11));
      expect(s.remaining, 5);
      expect(s.perOpenDay, isNull);
      expect(s.balance, -5);
    });

    test('a whole month across the summer time change has every day once', () {
      // Clocks go back on 25 October 2026 in Europe; March 29 they go forward.
      for (final m in [DateTime(2026, 3), DateTime(2026, 10)]) {
        final s = sum(m, DateTime(m.year, m.month + 1), const {}, DateTime(2026, 1, 1));
        final weekdays = List.generate(
          daysBetween(m, DateTime(m.year, m.month + 1)),
          (i) => addDays(m, i),
        ).where((d) => d.weekday <= 5).length;
        expect(s.openDays, weekdays);
        expect(s.expected, weekdays * 8);
      }
      final oct = sum(
        DateTime(2026, 10, 19),
        DateTime(2026, 11, 2),
        log({DateTime(2026, 10, 26): ('work', 10)}),
        DateTime(2026, 10, 27),
      );
      expect(oct.worked, 10);
      expect(oct.unloggedPast, 5);
    });

    test('a schedule per weekday', () {
      final s = sum(mon, next, const {}, mon, WorkSchedule.parse('9,9,9,9,4,0,0'));
      expect(s.expected, 40);
      expect(s.openDays, 5);
      expect(s.perOpenDay, 8);
    });
  });

  group('DayTimes', () {
    test('hours from start and end, with a break and past midnight', () {
      expect(const DayTimes(9 * 60, 17 * 60 + 30, breakMinutes: 30).hours, 8);
      expect(const DayTimes(22 * 60, 6 * 60).hours, 8);
      expect(const DayTimes(9 * 60, 9 * 60 + 15, breakMinutes: 60).hours, 0);
    });

    test('ride along in the note and come back out', () {
      const t = DayTimes(8 * 60 + 45, 17 * 60, breakMinutes: 45);
      final note = DayTimes.join(t, 'Release day');
      expect(note, '[08:45-17:00 -45m] Release day');
      final back = DayTimes.parse(note)!;
      expect((back.start, back.end, back.breakMinutes), (t.start, t.end, t.breakMinutes));
      expect(DayTimes.strip(note), 'Release day');
      expect(DayTimes.parse('Just a note'), isNull);
      expect(DayTimes.strip('Just a note'), 'Just a note');
      expect(DayTimes.join(null, 'x'), 'x');
      expect(DayTimes.parse(DayTimes.join(const DayTimes(540, 1020), ''))!.breakMinutes, 0);
    });
  });

  test('hours read the way people write them', () {
    expect(formatHours(8), '8');
    expect(formatHours(7.5), '7.5');
    expect(formatHours(7.25), '7.25');
    expect(signedHours(3.5), '+3.5 h');
    expect(signedHours(-6), '−6 h');
    expect(signedHours(0.001), '0 h');
  });
}
