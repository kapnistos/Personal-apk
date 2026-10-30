import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../../core/db/database.dart';
import 'ics.dart';

/// Keeps subscribed calendars (Proton, Google, Outlook share links) up to date.
class FeedSync {
  FeedSync._();
  static final instance = FeedSync._();

  final _client = http.Client();

  /// webcal:// links are plain https underneath.
  static Uri normalize(String url) {
    final u = url.trim().replaceFirst(RegExp(r'^webcals?://', caseSensitive: false), 'https://');
    return Uri.parse(u);
  }

  /// Downloads the feed and replaces the calendar's events. Throws a readable message.
  Future<int> sync(AppDatabase db, Calendar cal) async {
    final url = cal.icsUrl;
    if (url == null) return 0;
    final http.Response res;
    try {
      res = await _client.get(normalize(url)).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw 'Could not download ${cal.name}. Check your connection.';
    }
    if (res.statusCode != 200 || !res.body.contains('BEGIN:VCALENDAR')) {
      throw '${cal.name}: the link did not return a calendar (status ${res.statusCode}).';
    }
    final now = DateTime.now();
    final events = parseIcs(
      res.body,
      from: now.subtract(const Duration(days: 92)),
      to: now.add(const Duration(days: 400)),
    );
    await db.replaceFeedEvents(cal.id, [
      for (final e in events)
        EventsCompanion.insert(
          calendarId: cal.id,
          title: e.title,
          start: e.start,
          end: e.end,
          allDay: Value(e.allDay),
          location: Value(e.location),
          notes: Value(e.notes),
          uid: Value(e.uid),
        ),
    ]);
    return events.length;
  }

  /// Syncs feeds older than [maxAge]; errors are ignored here and shown on manual sync.
  Future<void> syncStale(AppDatabase db, {Duration maxAge = const Duration(hours: 1)}) async {
    for (final c in await db.feedCalendars()) {
      if (c.syncedAt != null && DateTime.now().difference(c.syncedAt!) < maxAge) continue;
      try {
        await sync(db, c);
      } catch (_) {}
    }
  }
}
