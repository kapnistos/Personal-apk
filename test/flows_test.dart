// Every mini-app, filled with demo data, scrolled from top to bottom on the owner's phone (412x915) and a
// small one (360x740), light and dark, normal and large text. Overflows and crashes anywhere on a page fail.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/apps/internships/internships_page.dart';
import 'package:hub/apps/mail/mail_page.dart';
import 'package:hub/apps/news/news_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/shopping/shopping_page.dart';
import 'package:hub/apps/spaces/my_spaces.dart';
import 'package:hub/apps/spaces/space_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/apps/wallet/year_page.dart';
import 'package:hub/apps/weather/weather_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';
import 'package:hub/main.dart';

import '../screenshots/screenshots_test.dart' show loadFonts, seed;

/// The phone sizes, themes and text sizes every page is checked at.
const configs = [
  (Size(412, 915), false, 1.0),
  (Size(412, 915), true, 1.3),
  (Size(360, 740), true, 1.0),
  (Size(360, 740), false, 1.3),
];

String configName((Size, bool, double) c) =>
    '${c.$1.width.toInt()}x${c.$1.height.toInt()} ${c.$2 ? 'dark' : 'light'} x${c.$3}';

/// Pumps [page] (or the whole app when null) with demo data at [c].
Future<AppDatabase> pumpPage(
  WidgetTester t,
  (Size, bool, double) c,
  Widget Function()? page, {
  bool demo = true,
  Future<void> Function(AppSettings s)? before,
}) async {
  t.view.physicalSize = c.$1;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = c.$3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  final settings = AppSettings(db);
  await t.runAsync(() async {
    await settings.load();
    if (demo) await seed(db, settings);
    await settings.setThemeMode(c.$2 ? ThemeMode.dark : ThemeMode.light);
    await before?.call(settings);
  });
  await t.pumpWidget(
    page == null
        ? HubApp(db: db, settings: settings)
        : Hub(
            db: db,
            settings: settings,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: c.$2 ? ThemeMode.dark : ThemeMode.light,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('en', 'GB')],
              locale: const Locale('en', 'GB'),
              home: page(),
            ),
          ),
  );
  await settle(t);
  return db;
}

Future<void> settle(WidgetTester t, [int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pump(const Duration(milliseconds: 400));
}

/// Scrolls every vertical scroll view on screen from top to bottom, so rows below the fold get built.
Future<void> scrollThrough(WidgetTester t) async {
  final scrollables = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  for (var i = 0; i < scrollables.evaluate().length && i < 4; i++) {
    final s = scrollables.at(i);
    if (s.evaluate().isEmpty) continue;
    final state = t.state<ScrollableState>(s);
    for (var step = 0; step < 30; step++) {
      final pos = state.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      pos.jumpTo((pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent));
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
    state.position.jumpTo(0);
    await t.pump();
  }
}

Future<void> done(WidgetTester t, AppDatabase db) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 15));
  await t.runAsync(db.close);
}

void main() {
  personalEdition = false;
  setUpAll(loadFonts);
  final pages = <String, Widget Function()?>{
    'home': null,
    'weather': () => const WeatherPage(),
    'calendar': () => const CalendarPage(),
    'todo': () => const TodoPage(),
    'notes': () => const NotesPage(),
    'wallet': () => const WalletPage(),
    'savings': () => const WalletPage(initialTab: 1),
    'investing': () => const WalletPage(initialTab: 2),
    'subscriptions': () => const SubscriptionsPage(),
    'year': () => const YearPage(),
    'shopping': () => const ShoppingPage(),
    'habits': () => const HabitsPage(),
    'internships': () => const InternshipsPage(),
    'spaces': () => const SpacesPage(),
    'university': () => const SpaceLauncher(gid: 'seed-uni', fallbackName: 'University'),
    'job': () => const SpaceLauncher(gid: 'seed-job', fallbackName: 'Job'),
    'news': () => const NewsPage(),
    'mail': () => const MailPage(),
  };
  for (final c in configs) {
    for (final e in pages.entries) {
      testWidgets('scroll ${e.key} ${configName(c)}', (t) async {
        final db = await pumpPage(t, c, e.value);
        await scrollThrough(t);
        await done(t, db);
      });
    }
    for (final e in pages.entries.where((e) => e.value != null)) {
      testWidgets('empty ${e.key} ${configName(c)}', (t) async {
        final db = await pumpPage(t, c, e.value, demo: false);
        await scrollThrough(t);
        await done(t, db);
      });
    }
  }
}
