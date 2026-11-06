import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// Where a new event starts: the next full hour today, or 9:00 on any other day.
DateTime defaultEventStart(DateTime selectedDay, DateTime now) {
  final day = dateOnly(selectedDay);
  if (day != dateOnly(now)) return DateTime(day.year, day.month, day.day, 9);
  return DateTime(now.year, now.month, now.day, now.hour + 1);
}

const _allDayOnly = {-540, 900, 9540};
const _allDayReminders = {-540, 900, 1440, 9540};

/// Notification choices that make sense for a timed or an all-day event.
Map<int?, String> reminderChoices({required bool allDay}) => {
  for (final e in reminderOptions.entries)
    if (e.key == null || (allDay ? _allDayReminders.contains(e.key) : !_allDayOnly.contains(e.key))) e.key: e.value,
};

/// Keeps the reminder sensible when an event switches between timed and all-day:
/// "15 minutes before" an all-day event would ring at 23:45 the evening before.
int? reminderAfterAllDayToggle(int? current, {required bool allDay}) {
  if (current == null) return null;
  if (reminderChoices(allDay: allDay).containsKey(current)) return current;
  return allDay ? -540 : 15;
}

/// The time line for [o] as it shows on [day]: "10:00 – 11:00", "All day",
/// "Day 2 of 3", or "Until 02:00" / "From 22:00" for a timed event that crosses midnight.
String timeOnDay(Occurrence o, DateTime day) {
  final d = dateOnly(day);
  String hm(DateTime t) => DateFormat.Hm().format(t);
  final startDay = dateOnly(o.start);
  final lastDay = o.end.isAfter(o.start) ? dateOnly(o.end.subtract(const Duration(seconds: 1))) : startDay;
  if (o.allDay) {
    final total = daysBetween(startDay, lastDay) + 1;
    if (total <= 1) return 'All day';
    return 'Day ${daysBetween(startDay, d) + 1} of $total';
  }
  if (startDay == lastDay) return o.end.isAfter(o.start) ? '${hm(o.start)} – ${hm(o.end)}' : hm(o.start);
  if (d == startDay) return 'From ${hm(o.start)}';
  if (d == lastDay) return 'Until ${hm(o.end)}';
  return 'All day';
}

/// A short "how soon" note for the event sheet: "Now", "In 20 min", "In 3 h", "Tomorrow".
/// Null once the event is over or when it is a week or more away.
String? startsIn(Occurrence o, DateTime now) {
  if (!o.end.isAfter(now)) return null;
  if (!o.start.isAfter(now)) return o.allDay ? 'Today' : 'Now';
  final days = daysBetween(dateOnly(now), dateOnly(o.start));
  if (days == 0) {
    if (o.allDay) return 'Today';
    final m = (o.start.difference(now).inSeconds / 60).ceil();
    if (m < 60) return 'In $m min';
    final h = m ~/ 60, rest = m % 60;
    return rest == 0 || h >= 3 ? 'In $h h' : 'In $h h $rest min';
  }
  if (days == 1) return 'Tomorrow';
  if (days < 7) return 'In $days days';
  return null;
}
