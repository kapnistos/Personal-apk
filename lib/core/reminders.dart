import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import 'automations.dart';
import 'db/database.dart';
import 'format.dart';

/// Schedules local notifications for to-do, calendar and internship reminders.
///
/// Every reminder is derived from the database, so [resync] can rebuild the
/// whole schedule at any time (app start, after edits).
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _exact = false;
  AppDatabase? _db;

  /// Called when a notification is tapped, with its payload (for example "todo:12").
  void Function(String payload)? onOpen;

  static const _todoActions = [
    AndroidNotificationAction('done', 'Done', showsUserInterface: true),
    AndroidNotificationAction('snooze', 'Snooze 10 min', showsUserInterface: true),
  ];

  static NotificationDetails _details({bool todo = false}) => NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'To-do, calendar and internship reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: 'ic_stat_hub',
      color: const Color(0xFF1F6F54),
      actions: todo ? _todoActions : null,
    ),
    windows: WindowsNotificationDetails(
      actions: todo
          ? const [
              WindowsAction(content: 'Done', arguments: 'done'),
              WindowsAction(content: 'Snooze 10 min', arguments: 'snooze'),
            ]
          : const [],
    ),
  );

  static const _automationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'automations',
      'Briefings and alerts',
      channelDescription: 'Morning briefing, bill reminders, low-balance alerts, weekly review and habits',
      importance: Importance.defaultImportance,
      icon: 'ic_stat_hub',
      color: Color(0xFF1F6F54),
      styleInformation: BigTextStyleInformation(''),
    ),
    windows: WindowsNotificationDetails(),
  );

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  Future<void> init(AppDatabase db) async {
    _db = db;
    if (!supported || _ready) return;
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Unknown zone name: fall back to UTC offsets, which is still correct
      // for scheduling because we convert from local DateTimes.
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_hub'),
          windows: WindowsInitializationSettings(
            appName: 'Hub',
            appUserModelId: 'Georgios.Hub',
            guid: '6a1f4c9e-8b2d-4f3a-9c7e-2d5b8a1e0f43',
          ),
        ),
        onDidReceiveNotificationResponse: _handle,
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final r = launch!.notificationResponse;
        if (r != null) await _handle(r);
      }
      await _refreshExact();
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<void> _handle(NotificationResponse r) async {
    final payload = r.payload ?? '';
    final db = _db;
    final todoId = payload.startsWith('todo:') ? int.tryParse(payload.substring(5)) : null;
    final action = r.actionId ?? '';
    if (db != null && todoId != null && action == 'done') {
      await db.setTodoDone(todoId, true);
      return;
    }
    if (db != null && todoId != null && action == 'snooze') {
      await db.snoozeTodo(todoId, const Duration(minutes: 10));
      return;
    }
    if (payload.isNotEmpty) onOpen?.call(payload);
  }

  Future<void> _refreshExact() async {
    if (!Platform.isAndroid) {
      _exact = true;
      return;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    _exact = await android?.canScheduleExactNotifications() ?? false;
  }

  /// Whether reminders can show. Null when unknown.
  Future<bool?> allowed() async {
    if (!_ready) return null;
    if (Platform.isAndroid) {
      return _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    }
    return true;
  }

  /// Asks Android 13+ for permission to post notifications and to ring on time.
  Future<void> requestPermission() async {
    if (!_ready || !Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    if (!(await android?.canScheduleExactNotifications() ?? true)) {
      await android?.requestExactAlarmsPermission();
    }
    await _refreshExact();
  }

  /// Asks once, the first time a reminder is set, so reminders don't silently never show.
  Future<void> ensurePermission() async {
    if (!_ready || !Platform.isAndroid) return;
    if (await allowed() == true && _exact) return;
    await requestPermission();
    if (_db != null) await resync(_db!);
  }

  Future<void>? _running;
  bool _again = false;
  String? _lastPlan;

  /// Rebuilds all pending reminders for the next 30 days.
  ///
  /// Calls that arrive while one is running are folded into a single rerun,
  /// and nothing is touched when the plan is the same as last time.
  Future<void> resync(AppDatabase db) async {
    if (!_ready) return;
    if (_running != null) {
      _again = true;
      return _running;
    }
    final run = _resyncLoop(db);
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
  }

  Future<void> _resyncLoop(AppDatabase db) async {
    do {
      _again = false;
      try {
        final plan = await planReminders(db, DateTime.now());
        final key = '$_exact\n${plan.join('\n')}';
        if (key == _lastPlan) continue;
        await _plugin.cancelAll();
        _lastPlan = null;
        for (final r in plan) {
          await _schedule(r.id, r.at, r.title, r.body, payload: r.payload, todo: r.todo, quiet: r.quiet);
        }
        _lastPlan = key;
      } catch (e) {
        _lastPlan = null;
        debugPrint('Could not schedule reminders: $e');
      }
    } while (_again);
  }

  Future<void> _schedule(
    int id,
    DateTime at,
    String title,
    String body, {
    String? payload,
    bool todo = false,
    bool quiet = false,
  }) => _plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(at, tz.local),
    notificationDetails: quiet ? _automationDetails : _details(todo: todo),
    androidScheduleMode: _exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    title: title,
    body: body,
    payload: payload,
  );
}

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder(this.id, this.at, this.title, this.body, this.payload, {this.todo = false, this.quiet = false});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
  final bool todo;
  final bool quiet;

  @override
  String toString() => '$id $at $title $body $payload $todo $quiet';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Every reminder for the next 30 days, worked out from the database.
Future<List<PlannedReminder>> planReminders(AppDatabase db, DateTime now) async {
  final horizon = addDays(now, 30);
  final out = <PlannedReminder>[];

  for (final t in await db.todosWithReminders()) {
    final at = t.remindAt!;
    if (at.isBefore(now) || at.isAfter(horizon)) continue;
    out.add(
      PlannedReminder(
        100000 + t.id,
        at,
        t.title,
        t.due == null ? 'To-do' : 'Due ${friendlyDay(t.due!, now: now)}',
        'todo:${t.id}',
        todo: true,
      ),
    );
  }

  for (final a in await db.applicationsWithReminders()) {
    if (a.status == 'rejected' || a.status == 'offer') continue;
    final name = [a.company, if (a.role.isNotEmpty) a.role].join(' · ');
    if (a.remindAt != null && a.remindAt!.isAfter(now) && a.remindAt!.isBefore(horizon)) {
      out.add(
        PlannedReminder(
          300000 + a.id,
          a.remindAt!,
          'Internship: $name',
          a.deadline == null ? 'Time to work on this application' : 'Deadline ${friendlyDay(a.deadline!, now: now)}',
          'application:${a.id}',
        ),
      );
    }
    // Two days before an open deadline, at 9:00.
    final d = a.deadline;
    if (d != null && (a.status == 'wishlist' || a.status == 'preparing')) {
      final warn = DateTime(d.year, d.month, d.day - 2, 9);
      if (warn.isAfter(now) && warn.isBefore(horizon)) {
        out.add(
          PlannedReminder(
            400000 + a.id,
            warn,
            'Apply soon: $name',
            'Deadline ${friendlyDay(d, now: now)}',
            'application:${a.id}',
          ),
        );
      }
    }
  }

  // Briefings, bill reminders, low-balance warnings, weekly review, habits.
  for (final p in await planAutomations(db, now: now)) {
    out.add(PlannedReminder(p.id, p.at, p.title, p.body, p.payload, quiet: true));
  }

  var n = 0;
  for (final e in await db.eventsWithReminders()) {
    for (final start in occurrences(e, now, horizon)) {
      final at = start.subtract(Duration(minutes: e.remindMinutes!));
      if (at.isBefore(now)) continue;
      final when = e.allDay ? friendlyDay(start, now: now) : '${friendlyDay(start, now: now)} ${_hm(start)}';
      out.add(
        PlannedReminder(
          200000 + n,
          at,
          e.title,
          [when, if (e.location.isNotEmpty) e.location].join(' · '),
          'event:${e.id}',
        ),
      );
      n++;
      // Android allows each app about 500 pending alarms; stay well below.
      if (out.length > 400) return out;
    }
  }
  return out;
}

/// Start times of [e] that fall in [from, to), expanding repeats.
List<DateTime> occurrences(Event e, DateTime from, DateTime to) {
  final out = <DateTime>[];
  final length = e.end.difference(e.start);
  // Jump close to [from] so old daily or weekly events don't need thousands of steps.
  final gap = daysBetween(e.start, from) - length.inDays - 1;
  var i = switch (e.repeat) {
    'daily' when gap > 0 => gap,
    'weekly' when gap > 0 => gap ~/ 7,
    'monthly' when gap > 31 => gap ~/ 31,
    'yearly' when gap > 366 => gap ~/ 366,
    _ => 0,
  };
  DateTime nth(int n) => switch (e.repeat) {
    'daily' => DateTime(e.start.year, e.start.month, e.start.day + n, e.start.hour, e.start.minute),
    'weekly' => DateTime(e.start.year, e.start.month, e.start.day + 7 * n, e.start.hour, e.start.minute),
    'monthly' => addMonths(e.start, n),
    'yearly' => addMonths(e.start, 12 * n),
    _ => n == 0 ? e.start : to,
  };
  var start = nth(i);
  var steps = 0;
  while (start.isBefore(to) && steps < 1000) {
    final end = start.add(length);
    if (end.isAfter(from) || (length == Duration.zero && !start.isBefore(from))) {
      out.add(start);
    }
    i++;
    steps++;
    if (e.repeat == 'none') break;
    start = nth(i);
  }
  return out;
}
