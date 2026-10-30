import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/apps/shopping/shopping_page.dart';
import 'package:hub/shell/automations_page.dart' show BackupPage;
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/apps/claude/claude_page.dart';
import 'package:hub/apps/mail/mail_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/me_page.dart';
import 'package:hub/shell/search_page.dart';
import 'package:hub/apps/internships/internships_page.dart';
import 'package:hub/apps/news/news_page.dart';
import 'package:hub/apps/spaces/space_page.dart';
import 'package:hub/apps/wallet/year_page.dart';

/// Pumps [child] with a fresh in-memory database and tears it down cleanly.
Future<void> pumpWithDb(WidgetTester tester, Widget Function(AppDatabase, AppSettings) build,
    Future<void> Function(AppDatabase db) body) async {
  final db = AppDatabase(NativeDatabase.memory());
  final settings = AppSettings(db);
  await tester.runAsync(settings.load);
  await tester.pumpWidget(build(db, settings));
  await tester.pump(const Duration(milliseconds: 50));
  await body(db);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
  await tester.runAsync(db.close);
}

void main() {
  testWidgets('home screen shows the mini-apps', (tester) async {
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      for (final title in ['Weather', 'Calendar', 'Notes', 'Wallet', 'Claude']) {
        expect(find.text(title), findsWidgets);
      }
    });
  });

  final pages = <String, Widget Function()>{
    'notes': () => const NotesPage(),
    'todo': () => const TodoPage(),
    'calendar': () => const CalendarPage(),
    'wallet': () => const WalletPage(),
    'subscriptions': () => const SubscriptionsPage(),
    'claude': () => const ClaudePage(),
    'mail': () => const MailPage(),
    'mail accounts': () => const MailAccountsPage(),
    'me': () => const MePage(),
    'search': () => const SearchPage(),
    'internships': () => const InternshipsPage(),
    'news': () => const NewsPage(),
    'job space': () => const SpacePage(spaceId: 1),
    'university space': () => const SpacePage(spaceId: 3),
    'wallet savings': () => const WalletPage(initialTab: 1),
    'wallet investing': () => const WalletPage(initialTab: 2),
    'year overview': () => const YearPage(),
    'habits': () => const HabitsPage(),
    'shopping': () => const ShoppingPage(),
    'backup': () => const BackupPage(),
  };
  for (final e in pages.entries) {
    testWidgets('${e.key} page builds', (tester) async {
      await pumpWithDb(
        tester,
        (db, s) => Hub(db: db, settings: s, child: MaterialApp(home: e.value())),
        (_) async => expect(tester.takeException(), isNull),
      );
    });
  }

  testWidgets('adding a task shows it in the list', (tester) async {
    await pumpWithDb(tester, (db, s) => Hub(db: db, settings: s, child: const MaterialApp(home: TodoPage())),
        (db) async {
      await tester.enterText(find.byType(TextField), 'Buy milk tomorrow');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Tomorrow'), findsWidgets); // The group heading and the task's date.
    });
  });

  testWidgets('search finds a note', (tester) async {
    await pumpWithDb(tester, (db, s) => Hub(db: db, settings: s, child: const MaterialApp(home: SearchPage())),
        (db) async {
      await tester.runAsync(() => db.saveNote(title: 'Tax return', body: 'deadline in May'));
      await tester.enterText(find.byType(TextField), 'deadline');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Tax return'), findsOneWidget);
    });
  });
}
