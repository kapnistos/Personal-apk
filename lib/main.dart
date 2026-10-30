import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'apps/calendar/calendar_page.dart';
import 'apps/calendar/feed_sync.dart';
import 'apps/internships/internships_page.dart';
import 'apps/todo/todo_page.dart';
import 'core/db/database.dart';
import 'core/reminders.dart';
import 'core/settings.dart';
import 'core/sync/sync_service.dart';
import 'core/theme.dart';
import 'shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final settings = AppSettings(db);
  await settings.load();
  runApp(HubApp(db: db, settings: settings));
  unawaited(_startBackground(db, settings));
}

/// Work that should not delay the first frame.
Future<void> _startBackground(AppDatabase db, AppSettings settings) async {
  tzdata.initializeTimeZones();
  await settings.startSync();
  AppLifecycleListener(onResume: SyncService.instance.syncNow);
  await db.bookDueSubscriptions();
  unawaited(FeedSync.instance.syncStale(db));
  Timer.periodic(const Duration(minutes: 30), (_) => FeedSync.instance.syncStale(db));
  Reminders.instance.onOpen = (payload) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final page = switch (payload.split(':').first) {
      'todo' => const TodoPage(),
      'event' => const CalendarPage(),
      'application' => const InternshipsPage(),
      _ => null,
    };
    if (page != null) nav.push(MaterialPageRoute(builder: (_) => page));
  };
  await Reminders.instance.init(db);
  await Reminders.instance.resync(db);
  // Ask for notification permission on first start instead of waiting for a visit to Me.
  if (settings.raw('asked-notifications') == null) {
    await settings.setRaw('asked-notifications', '1');
    await Reminders.instance.requestPermission();
    await Reminders.instance.resync(db);
  }
  Timer? debounce;
  db.tableUpdates(TableUpdateQuery.onAllTables([db.todos, db.events, db.applications])).listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () => Reminders.instance.resync(db));
  });
}

/// Lets a tapped notification open the right page.
final navigatorKey = GlobalKey<NavigatorState>();

class HubApp extends StatelessWidget {
  const HubApp({super.key, required this.db, required this.settings});

  final AppDatabase db;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Hub(
      db: db,
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'Hub',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US'), Locale('nl'), Locale('el')],
          locale: const Locale('en', 'GB'),
          home: const Shell(),
        ),
      ),
    );
  }
}
