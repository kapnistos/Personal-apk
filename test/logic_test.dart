import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_model.dart';
import 'package:hub/apps/calendar/ics.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:hub/apps/mail/mail_service.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/accounts_page.dart';
import 'package:hub/apps/wallet/bank_import.dart';
import 'package:hub/apps/weather/weather_service.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/reminders.dart';

Event ev(DateTime start, Duration length, {String repeat = 'none', bool allDay = false}) => Event(
      id: 1,
      calendarId: 1,
      title: 'x',
      location: '',
      notes: '',
      start: start,
      end: start.add(length),
      allDay: allDay,
      repeat: repeat,
      remindMinutes: null,
    );

void main() {
  group('format', () {
    test('addMonths clamps to month end', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });
    test('parseMoney accepts comma and dot decimals', () {
      expect(parseMoney('12,50'), 1250);
      expect(parseMoney('1.234,56'), 123456);
      expect(parseMoney('1,234.56'), 123456);
      expect(parseMoney('abc'), isNull);
    });
    test('friendlyDay', () {
      final now = DateTime(2026, 10, 29, 12);
      expect(friendlyDay(DateTime(2026, 10, 29), now: now), 'Today');
      expect(friendlyDay(DateTime(2026, 10, 30), now: now), 'Tomorrow');
      expect(friendlyDay(DateTime(2026, 11, 2), now: now), 'Monday');
    });
  });

  test('quick-add reads a trailing day word', () {
    final now = DateTime(2026, 10, 29); // Thursday
    expect(parseQuickDue('Call mum tomorrow', now: now), ('Call mum', DateTime(2026, 10, 30)));
    expect(parseQuickDue('Gym fri', now: now), ('Gym', DateTime(2026, 10, 30)));
    expect(parseQuickDue('Report thursday', now: now), ('Report', DateTime(2026, 11, 5)));
    expect(parseQuickDue('Tomorrow', now: now), ('Tomorrow', null));
  });

  group('calendar', () {
    test('weekly repeats expand inside the range', () {
      final e = ev(DateTime(2026, 10, 1, 9), const Duration(hours: 1), repeat: 'weekly');
      final hits = occurrences(e, DateTime(2026, 10, 12), DateTime(2026, 10, 26));
      expect(hits, [DateTime(2026, 10, 15, 9), DateTime(2026, 10, 22, 9)]);
    });
    test('monthly repeats keep the time', () {
      final e = ev(DateTime(2026, 1, 31, 18), const Duration(hours: 2), repeat: 'monthly');
      final hits = occurrences(e, DateTime(2026, 2, 1), DateTime(2026, 3, 1));
      expect(hits, [DateTime(2026, 2, 28, 18)]);
    });
    test('overlapping events share columns', () {
      final cal = {1: const Calendar(id: 1, name: 'P', color: 0xFF000000, visible: true)};
      final day = DateTime(2026, 10, 29);
      final occ = expand([
        ev(day.add(const Duration(hours: 9)), const Duration(hours: 2)),
        ev(day.add(const Duration(hours: 10)), const Duration(hours: 1)),
        ev(day.add(const Duration(hours: 12)), const Duration(hours: 1)),
      ], cal, day, day.add(const Duration(days: 1)));
      final placed = layoutDay(occ);
      expect(placed.map((p) => (p.$2, p.$3)).toList(), [(0, 2), (1, 2), (0, 1)]);
    });
  });

  group('bank import', () {
    test('Revolut CSV', () {
      const csv = 'Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\n'
          'CARD_PAYMENT,Current,2026-10-01 10:00:00,2026-10-02 08:00:00,Albert Heijn,-23.40,0.00,EUR,COMPLETED,100\n'
          'CARD_PAYMENT,Current,2026-10-03 10:00:00,,Netflix,-13.99,0.00,EUR,PENDING,86\n'
          'TOPUP,Current,2026-10-04 10:00:00,2026-10-04 10:00:00,Apple Pay,50.00,0.00,EUR,COMPLETED,150\n';
      final r = parseBankExport(csv);
      expect(r.format, 'Revolut');
      expect(r.rows.length, 2);
      expect(r.rows.first.amountCents, -2340);
      expect(r.rows.first.category, 'Groceries');
      expect(r.rows.last.kind, EntryKind.transfer);
    });
    test('ABN AMRO TXT', () {
      const txt = '123456789\tEUR\t20261015\t1000,00\t986,01\t20261015\t-13,99\tBEA, Betaalpas                   NETFLIX.COM,PAS123\n'
          '123456789\tEUR\t20261025\t986,01\t2986,01\t20261025\t2000,00\t/TRTP/SEPA OVERBOEKING/IBAN/NL00/BIC/X/NAME/ACME BV/REMI/Salaris oktober/EREF/1\n';
      final r = parseBankExport(txt);
      expect(r.format, 'ABN AMRO');
      expect(r.rows.length, 2);
      expect(r.rows.first.kind, EntryKind.subscription);
      expect(r.rows.last.description, 'ACME BV · Salaris oktober');
      expect(r.rows.last.kind, EntryKind.income);
      expect(r.rows.last.category, 'Salary');
    });
    test('Greek bank CSV with debit and credit columns', () {
      const csv = 'Ημερομηνία;Περιγραφή;Χρέωση;Πίστωση\n'
          '15/10/2026;ΣΚΛΑΒΕΝΙΤΗΣ ΑΘΗΝΑ;42,10;\n'
          '20/10/2026;ΜΙΣΘΟΔΟΣΙΑ;;1.500,00\n';
      final r = parseBankExport(csv);
      expect(r.format, 'Eurobank');
      expect(r.rows.map((x) => x.amountCents), [-4210, 150000]);
      expect(r.rows.first.date, DateTime(2026, 10, 15));
      expect(r.rows.first.category, 'Groceries');
      expect(r.rows.last.category, 'Salary');
    });
    test('"action" does not match "transaction"', () {
      expect(guessCategory('card transaction fee', EntryKind.expense), 'Other');
      expect(guessCategory('Action Eindhoven', EntryKind.expense), 'Shopping');
    });
  });

  group('weather', () {
    test('Buienradar text parses into mm/h and rolls over midnight', () {
      final pts = Buienradar.parse('000|23:55\n077|00:00\n109|00:05\n', now: DateTime(2026, 10, 29, 23, 50));
      expect(pts.length, 3);
      expect(pts[0].mmPerHour, 0);
      expect(pts[1].mmPerHour, closeTo(0.1, 0.01));
      expect(pts[2].mmPerHour, closeTo(1.0, 0.01));
      expect(pts[2].time, DateTime(2026, 10, 30, 0, 5));
    });
    test('Nowcast summary', () {
      final t = DateTime(2026, 10, 29, 14);
      final n = Nowcast(source: 'x', points: [
        for (var i = 0; i < 24; i++) RainPoint(t.add(Duration(minutes: 5 * i)), i >= 6 ? 1.2 : 0),
      ]);
      expect(n.summary((d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}'), 'Rain starting around 14:30');
    });
    test('Google condition types map to WMO codes', () {
      expect(GoogleWeather.googleToWmo('CLEAR'), 0);
      expect(GoogleWeather.googleToWmo('HEAVY_RAIN'), 65);
      expect(GoogleWeather.googleToWmo('THUNDERSHOWER'), 95);
    });
    test('Google response parses', () {
      final f = GoogleWeather.parse(
        {
          'temperature': {'degrees': 11.5},
          'feelsLikeTemperature': {'degrees': 9.0},
          'relativeHumidity': 80,
          'wind': {'speed': {'value': 18, 'unit': 'KILOMETERS_PER_HOUR'}},
          'weatherCondition': {'type': 'LIGHT_RAIN'},
          'isDaytime': true,
        },
        {
          'forecastHours': [
            {
              'displayDateTime': {'year': 2026, 'month': 10, 'day': 29, 'hours': 15, 'utcOffset': '3600s'},
              'temperature': {'degrees': 12},
              'weatherCondition': {'type': 'CLOUDY'},
              'precipitation': {'probability': {'percent': 40}},
            }
          ]
        },
        {
          'forecastDays': [
            {
              'displayDate': {'year': 2026, 'month': 10, 'day': 29},
              'maxTemperature': {'degrees': 13},
              'minTemperature': {'degrees': 7},
              'daytimeForecast': {'weatherCondition': {'type': 'RAIN'}, 'precipitation': {'probability': {'percent': 70}}},
              'sunEvents': {'sunriseTime': '2026-10-29T07:10:00Z', 'sunsetTime': '2026-10-29T16:20:00Z'},
            }
          ]
        },
      );
      expect(f.temperature, 11.5);
      expect(f.code, 61);
      expect(f.hours.single.rainChance, 40);
      expect(f.days.single.code, 63);
      expect(f.days.single.sunrise, DateTime(2026, 10, 29, 8, 10));
    });
  });

  test('a new install starts with the usual recurring list, once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final subs = await db.watchSubscriptions().first;
    expect(subs.length, myRecurring.length);
    expect(await db.restoreRecurring(), 0);
    if (subs.isNotEmpty) {
      await db.deleteSubscription(subs.first.id);
      expect(await db.restoreRecurring(), 1);
    }
    expect((await db.watchAccounts().first).map((a) => a.name), ['ABN AMRO', 'Revolut', 'Eurobank']);
    await db.close();
  });

  test('a new install starts with my open tasks, once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect((await db.watchTodos().first).length, myTasks.length);
    expect(await db.restoreTasks(), 0);
    await db.close();
  });

  test('an account balance counts entries made after it was set', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final abn = (await db.watchAccounts().first).first;
    await db.setAccountBalance(abn.id, 100000, at: DateTime(2026, 10, 10));
    Future<void> add(int cents, EntryKind kind, DateTime d, String account) =>
        db.into(db.entries).insert(EntriesCompanion.insert(
            amountCents: cents, kind: kind, category: 'Other', date: d, account: Value(account)));
    await add(5000, EntryKind.expense, DateTime(2026, 10, 5), 'ABN AMRO'); // before the balance was set
    await add(2000, EntryKind.expense, DateTime(2026, 10, 12), 'abn amro');
    await add(89900, EntryKind.income, DateTime(2026, 10, 25), 'ABN AMRO');
    await add(700, EntryKind.expense, DateTime(2026, 10, 26), 'Revolut');
    final a = (await db.watchAccounts().first).first;
    await db.delete(db.subscriptions).go();
    await db.saveSubscription(SubscriptionsCompanion.insert(
        name: 'Rent', amountCents: 98000, kind: EntryKind.subscription, category: 'Rent', nextDate: DateTime(2026, 11, 30)));
    final rent = (await db.watchSubscriptions().first).single;
    await db.setSubscriptionAccount(rent.id, 'ABN AMRO');
    final s = AccountState(a, await db.watchAccountEntries('ABN AMRO').first, await db.watchSubscriptions().first,
        now: DateTime(2026, 10, 29));
    expect(s.balance, 100000 - 2000 + 89900);
    expect(s.monthIn, 89900);
    expect(s.monthOut, 7000);
    expect(s.recurring.single.name, 'Rent');
    expect(s.monthly, -98000);
    await db.close();
  });

  test('subscriptions book once per period and never twice', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.delete(db.subscriptions).go();
    await db.saveSubscription(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amountCents: 1399,
      kind: EntryKind.subscription,
      category: 'Streaming',
      nextDate: DateTime(2026, 8, 5),
    ));
    final now = DateTime(2026, 10, 29);
    expect(await db.bookDueSubscriptions(now: now), 3);
    expect(await db.bookDueSubscriptions(now: now), 0);
    final entries = await db.watchEntries(DateTime(2026, 1), DateTime(2027)).first;
    expect(entries.length, 3);
    final sub = (await db.watchSubscriptions().first).single;
    expect(sub.nextDate, DateTime(2026, 11, 5));
    await db.close();
  });

  test('HTML mail flattens to readable text', () {
    const html = '<html><head><style>p{color:red}</style></head><body><p>Hi Alex,</p>'
        '<p>Your order&nbsp;ships <b>today</b>.<br>Thanks &amp; regards</p><ul><li>One</li><li>Two</li></ul></body></html>';
    expect(htmlToText(html), 'Hi Alex,\nYour order ships today.\nThanks & regards\n• One\n• Two');
  });

  group('ics', () {
    setUpAll(tzdata.initializeTimeZones);
    const feed = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
        'BEGIN:VEVENT\r\nUID:a1\r\nSUMMARY:Lecture\\, room 4\r\nDTSTART:20261005T070000Z\r\nDTEND:20261005T090000Z\r\n'
        'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r\nEXDATE:20261007T070000Z\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:a2\r\nSUMMARY:Holiday\r\nDTSTART;VALUE=DATE:20261224\r\nDTEND;VALUE=DATE:20261227\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:a3\r\nSUMMARY:Long title that is\r\n  folded\r\nDTSTART;TZID=Europe/Athens:20261101T120000\r\nDURATION:PT30M\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n';
    late final events = parseIcs(feed, from: DateTime(2026, 9, 1), to: DateTime(2027, 1, 31));

    test('weekly rule with BYDAY, COUNT and EXDATE', () {
      final lectures = events.where((e) => e.title == 'Lecture, room 4').toList();
      expect(lectures.length, 5); // 6 generated, one excluded
      expect(lectures.first.start, DateTime.utc(2026, 10, 5, 7).toLocal());
      expect(lectures.first.end.difference(lectures.first.start), const Duration(hours: 2));
    });
    test('all-day spans and folded lines', () {
      final h = events.firstWhere((e) => e.title == 'Holiday');
      expect(h.allDay, isTrue);
      expect(h.end.difference(h.start).inDays, 3);
      final f = events.firstWhere((e) => e.uid == 'a3');
      expect(f.title, 'Long title that is folded');
    });
    test('TZID times convert to the same instant', () {
      final f = events.firstWhere((e) => e.uid == 'a3');
      expect(f.start.toUtc(), DateTime.utc(2026, 11, 1, 10));
      expect(f.end.difference(f.start), const Duration(minutes: 30));
    });
    test('monthly rule skips short months', () {
      final days = expandRule('FREQ=MONTHLY', DateTime(2026, 1, 31, 9), DateTime(2026, 6, 1)).toList();
      expect(days.map((d) => d.month), [1, 3, 5]);
    });
  });
}
