import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/reminders.dart';

/// One concrete appearance of an event (repeating events have many).
class Occurrence {
  Occurrence(this.event, this.start, this.end, this.color);
  final Event event;
  final DateTime start;
  final DateTime end;
  final Color color;

  bool get allDay => event.allDay;

  /// True if this occurrence covers any part of [day].
  bool touches(DateTime day) {
    final d0 = dateOnly(day);
    final d1 = addDays(d0, 1);
    if (end == start) return !start.isBefore(d0) && start.isBefore(d1);
    return start.isBefore(d1) && end.isAfter(d0);
  }
}

List<Occurrence> expand(List<Event> events, Map<int, Calendar> calendars, DateTime from, DateTime to) {
  final out = <Occurrence>[];
  for (final e in events) {
    final cal = calendars[e.calendarId];
    if (cal == null || !cal.visible) continue;
    for (final s in occurrences(e, from, to)) {
      out.add(Occurrence(e, s, occurrenceEnd(e, s), Color(cal.color)));
    }
  }
  out.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : b.end.compareTo(a.end);
  });
  return out;
}

/// First day shown in a month grid (weeks start on Monday).
DateTime monthGridStart(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  return addDays(first, 1 - first.weekday);
}

DateTime weekStart(DateTime d) => addDays(dateOnly(d), 1 - d.weekday);

/// Places timed occurrences of one day side by side when they overlap.
/// Returns (occurrence, column, columnCount).
List<(Occurrence, int, int)> layoutDay(List<Occurrence> timed) {
  final sorted = [...timed]..sort((a, b) => a.start.compareTo(b.start));
  final result = <(Occurrence, int, int)>[];
  var cluster = <(Occurrence, int)>[];
  var columnsEnd = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    final n = columnsEnd.length;
    for (final (o, col) in cluster) {
      result.add((o, col, n));
    }
    cluster = [];
    columnsEnd = [];
    clusterEnd = null;
  }

  for (final o in sorted) {
    // Very short events still take 20 minutes of space so they stay tappable.
    final end = o.end.difference(o.start).inMinutes < 20 ? o.start.add(const Duration(minutes: 20)) : o.end;
    if (clusterEnd != null && !o.start.isBefore(clusterEnd!)) flush();
    var col = columnsEnd.indexWhere((e) => !o.start.isBefore(e));
    if (col == -1) {
      col = columnsEnd.length;
      columnsEnd.add(end);
    } else {
      columnsEnd[col] = end;
    }
    cluster.add((o, col));
    if (clusterEnd == null || end.isAfter(clusterEnd!)) clusterEnd = end;
  }
  flush();
  return result;
}

const repeatLabels = {
  'none': 'Does not repeat',
  'daily': 'Every day',
  'weekly': 'Every week',
  'monthly': 'Every month',
  'yearly': 'Every year',
};

const reminderOptions = <int?, String>{
  null: 'No notification',
  0: 'At start time',
  5: '5 minutes before',
  10: '10 minutes before',
  15: '15 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  1440: '1 day before',
  // For all-day events, which start at midnight.
  -540: 'On the day at 9:00',
  900: 'The day before at 9:00',
  9540: 'A week before at 9:00',
};

const calendarColors = [0xFF3A78C9, 0xFF1F7A5A, 0xFFC0563F, 0xFF6650AE, 0xFFCF9418, 0xFFB5487A, 0xFF2D8C9E, 0xFF6F6A60];
