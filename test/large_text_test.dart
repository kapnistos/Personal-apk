// The main screens at the smallest phone size with large text, filled with demo data, must not overflow.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/news/news_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/spaces/space_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/apps/weather/weather_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/me_page.dart';

import '../screenshots/screenshots_test.dart' show loadFonts, seed;

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
    'me': () => const MePage(),
    'university': () => const SpacePage(spaceId: 2),
    'news': () => const NewsPage(),
  };
  for (final e in pages.entries) {
    testWidgets('large text 320x568 ${e.key}', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await tester.runAsync(() async {
        await settings.load();
        await seed(db, settings);
      });
      final Widget app = e.value == null
          ? HubApp(db: db, settings: settings)
          : Hub(
              db: db,
              settings: settings,
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('en', 'GB')],
                locale: const Locale('en', 'GB'),
                home: e.value!(),
              ),
            );
      await tester.pumpWidget(app);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      await tester.runAsync(db.close);
    });
  }
}
