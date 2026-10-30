import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/sync/sync_engine.dart';

/// Simulates the HTTP round trip between a client and the server.
Future<void> roundTrip(SyncEngine client, SyncEngine server) async {
  final state = await client.state();
  final pushStart = SyncEngine.now();
  final changes = await client.collect(state['lastPush']!);
  await server.apply(changes);
  final now = SyncEngine.now();
  final back = await server.collect(state['lastPull']!);
  await client.apply(back);
  await client.saveState(lastPull: now, lastPush: pushStart);
}

Future<void> tick() => Future.delayed(const Duration(milliseconds: 5));

void main() {
  late AppDatabase server, phone, pc;
  late SyncEngine s, a, b;

  setUp(() async {
    server = AppDatabase(NativeDatabase.memory());
    phone = AppDatabase(NativeDatabase.memory());
    pc = AppDatabase(NativeDatabase.memory());
    s = SyncEngine(server);
    a = SyncEngine(phone);
    b = SyncEngine(pc);
    await s.setRole('server');
    await a.setRole('client');
    await b.setRole('client');
  });

  tearDown(() async {
    await server.close();
    await phone.close();
    await pc.close();
  });

  test('a note written on the phone reaches the PC', () async {
    await phone.saveNote(title: 'Hello', body: 'from the phone');
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    final notes = await pc.watchNotes().first;
    expect(notes.single.title, 'Hello');
  });

  test('starter city and calendars merge instead of doubling', () async {
    await roundTrip(a, s);
    await roundTrip(b, s);
    await roundTrip(a, s);
    expect((await phone.watchCities().first).length, 1);
    expect((await pc.watchCalendars().first).length, 4);
    expect((await server.watchCalendars().first).length, 4);
  });

  test('a renamed starter calendar wins over the untouched copies', () async {
    final work = (await phone.watchCalendars().first).firstWhere((c) => c.name == 'Work');
    await phone.saveCalendar(work.toCompanion(false).copyWith(name: const Value('Job')));
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    expect((await pc.watchCalendars().first).map((c) => c.name), containsAll(['Personal', 'Job', 'Study']));
  });

  test('later edit wins and deletes propagate', () async {
    final id = await phone.saveNote(title: 'Draft', body: '');
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    final onPc = (await pc.watchNotes().first).single;

    await tick();
    await phone.saveNote(id: id, title: 'Phone edit', body: '');
    await tick();
    await pc.saveNote(id: onPc.id, title: 'PC edit', body: '');
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    await roundTrip(a, s);
    expect((await phone.watchNotes().first).single.title, 'PC edit');
    expect((await server.watchNotes().first).single.title, 'PC edit');

    await tick();
    await pc.deleteNote(onPc.id);
    await tick();
    await roundTrip(b, s);
    await roundTrip(a, s);
    expect(await phone.watchNotes().first, isEmpty);
    expect(await server.watchNotes().first, isEmpty);
  });

  test('events keep their calendar across devices', () async {
    final cal = await phone.saveCalendar(CalendarsCompanion.insert(name: 'Trips', color: 0xFF000000));
    await phone.saveEvent(EventsCompanion.insert(
      calendarId: cal,
      title: 'Flight',
      start: DateTime(2026, 11, 1, 9),
      end: DateTime(2026, 11, 1, 12),
    ));
    await tick();
    await roundTrip(a, s);
    await roundTrip(b, s);
    final cals = await pc.watchCalendars().first;
    final trips = cals.firstWhere((c) => c.name == 'Trips');
    final ev = await pc.watchEventsBetween(DateTime(2026, 10, 1), DateTime(2026, 12, 1)).first;
    expect(ev.single.calendarId, trips.id);
  });

  test('applied rows are not sent back by the client', () async {
    await server.saveNote(title: 'From server', body: '');
    await tick();
    await roundTrip(a, s);
    final changes = await a.collect((await a.state())['lastPush']!);
    final rows = changes['rows'] as Map;
    expect(rows['notes'], isNull);
  });

  test('feed events stay local', () async {
    final cal = await phone.saveCalendar(
        CalendarsCompanion.insert(name: 'Proton', color: 0xFF000000, icsUrl: const Value('https://x/y.ics')));
    await phone.replaceFeedEvents(cal, [
      EventsCompanion.insert(
          calendarId: cal, title: 'Feed', start: DateTime(2026, 11, 2), end: DateTime(2026, 11, 2, 1), uid: const Value('u1')),
    ]);
    await tick();
    await roundTrip(a, s);
    final ev = await server.watchEventsBetween(DateTime(2026, 10, 1), DateTime(2026, 12, 1)).first;
    expect(ev, isEmpty);
    expect((await server.watchCalendars().first).any((c) => c.icsUrl == 'https://x/y.ics'), isTrue);
  });
}
