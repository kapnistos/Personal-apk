import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'apps/calendar/calendar_page.dart';
import 'apps/calendar/feed_sync.dart';
import 'apps/internships/internships_page.dart';
import 'apps/habits/habits_page.dart';
import 'apps/todo/todo_page.dart';
import 'apps/wallet/wallet_page.dart';
import 'core/automations.dart';
import 'core/backup.dart';
import 'core/db/database.dart';
import 'core/reminders.dart';
import 'core/settings.dart';
import 'core/sync/sync_service.dart';
import 'core/edition.dart';
import 'core/theme.dart';
import 'shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final settings = AppSettings(db);
  await settings.load();
  if (!personalEdition) await checkImportedApps(db).catchError((_) {});
  runApp(HubApp(db: db, settings: settings));
  unawaited(_startBackground(db, settings));
}

/// Work that should not delay the first frame.
Future<void> _startBackground(AppDatabase db, AppSettings settings) async {
  tzdata.initializeTimeZones();
  await settings.startSync();
  // Days pass while the app sits in the background, so the reminder schedule is
  // checked again too; it skips the work when nothing changed.
  AppLifecycleListener(
    onResume: () {
      SyncService.instance.syncNow();
      Reminders.instance.resync(db);
    },
  );
  await db.bookDueSubscriptions();
  // A copy of everything, once a day, kept for two weeks (Me → Backup).
  if (settings.raw('auto.backup') != 'off') unawaited(autoBackup(db));
  unawaited(FeedSync.instance.syncStale(db));
  Timer.periodic(const Duration(minutes: 30), (_) => FeedSync.instance.syncStale(db));
  Reminders.instance.onOpen = (payload) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final Widget? page = switch (payload.split(':').first) {
      'todo' => const TodoPage(),
      'event' => const CalendarPage(),
      'application' => const InternshipsPage(),
      'wallet' => const WalletPage(),
      'habit' => const HabitsPage(),
      _ => null, // "today" (briefing, weekly review) opens Home.
    };
    // Start from Home so taps on several notifications don't pile pages up.
    nav.popUntil((r) => r.isFirst);
    if (page != null) nav.push(MaterialPageRoute(builder: (_) => page));
  };
  await Reminders.instance.init(db);
  await Reminders.instance.resync(db);
  // Ask for notification permission on first start instead of waiting for a visit to Me.
  if (settings.raw('asked-notifications') == null) {
    await settings.setRaw('asked-notifications', '1', quiet: true);
    await Reminders.instance.requestPermission();
    await Reminders.instance.resync(db);
  }
  // Rebuild the schedule a moment after data changes. Settings only count when
  // an automation setting changed, so caches and layout tweaks don't trigger it.
  Timer? debounce;
  void later() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () => Reminders.instance.resync(db));
  }

  db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.todos,
          db.events,
          db.applications,
          db.subscriptions,
          db.accounts,
          db.entries,
          db.habits,
          db.habitChecks,
        ]),
      )
      .listen((_) => later());
  var autoKeys = automationSignature(settings);
  settings.addListener(() {
    final next = automationSignature(settings);
    if (next == autoKeys) return;
    autoKeys = next;
    later();
  });
}

/// Lets a tapped notification open the right page.
final navigatorKey = GlobalKey<NavigatorState>();

class HubApp extends StatefulWidget {
  const HubApp({super.key, required this.db, required this.settings});

  final AppDatabase db;
  final AppSettings settings;

  @override
  State<HubApp> createState() => _HubAppState();
}

class _HubAppState extends State<HubApp> {
  late ThemeMode _mode = widget.settings.themeMode;
  late String _accent = widget.settings.raw(accentKey) ?? 'blue';
  late String _background = widget.settings.raw(darkBackgroundKey) ?? 'black';

  // buildTheme caches by its arguments, so these stay the same object until a colour changes.
  ThemeData get _light => buildTheme(Brightness.light, accent: _accent);
  ThemeData get _dark => buildTheme(Brightness.dark, accent: _accent, background: _background);

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_settingsChanged);
    super.dispose();
  }

  // Screens that read a setting redraw through Hub; the app itself only cares about the theme.
  void _settingsChanged() {
    final s = widget.settings;
    final accent = s.raw(accentKey) ?? 'blue';
    final background = s.raw(darkBackgroundKey) ?? 'black';
    if (s.themeMode == _mode && accent == _accent && background == _background) return;
    setState(() {
      _mode = s.themeMode;
      _accent = accent;
      _background = background;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Hub(
      db: widget.db,
      settings: widget.settings,
      child: MaterialApp(
        title: 'Hub',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: _mode,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US'), Locale('nl'), Locale('el')],
        locale: const Locale('en', 'GB'),
        home: const Shell(),
      ),
    );
  }
}
