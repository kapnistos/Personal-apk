import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/lists/lists_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/core/backup.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/customize.dart';
import 'package:hub/shell/home_page.dart';
import 'package:hub/shell/me_page.dart';
import 'package:hub/shell/shell.dart';

import 'widget_test.dart' show pumpWithDb;

/// Personalisation: the bottom tabs, the top of Home, text size, and that all of it lands in a backup.
void main() {
  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 4));
    }
  }

  List<String> labels(WidgetTester tester) => [
    for (final d in tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations)
      (d as NavigationDestination).label,
  ];
  int selected(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('chosen tabs show in order; back and Ctrl+N still work; a removed tab opens as a page', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      final s = tester.element(find.byType(Shell)).getInheritedWidgetOfExactType<Hub>()!.settings;
      await tester.runAsync(() => setBarTabs(s, [ShellTab.todo, ShellTab.ai, ShellTab.calendar]));
      await settle(tester);
      expect(labels(tester), ['Home', 'Lists', 'AI', 'Calendar']);

      // Ctrl+2 is the second tab on the bar, now Lists.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(selected(tester), 1);
      expect(find.byType(ListsPage), findsOneWidget);

      // Back goes Home.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(selected(tester), 0);

      // Wallet is off the bar: the Today strip's money opens it as a page with a back button.
      final cell = find.descendant(of: find.byType(HomePage), matching: find.textContaining(RegExp('Spent|To spend')));
      await tester.ensureVisible(cell.first);
      await tester.pump();
      await tester.tap(cell.first);
      await settle(tester, 800);
      expect(find.byType(WalletPage), findsOneWidget);
      expect(find.byTooltip('Back'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the tabs sheet opens from a long press on the bar and toggles a tab', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      await tester.longPress(find.byType(NavigationBar));
      await settle(tester, 800);
      expect(find.text('Bottom tabs'), findsOneWidget);
      Finder row(String label) => find.ancestor(
        of: find.descendant(of: find.byType(BottomSheet), matching: find.text(label)),
        matching: find.byType(ListTile),
      );
      // Notes lives inside Lists now, so it has no switch of its own.
      expect(row('Notes'), findsNothing);
      // Turn AI off.
      await tester.tap(find.descendant(of: row('AI'), matching: find.byType(Switch)));
      await settle(tester);
      // Open on Lists next time.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Lists'));
      await settle(tester);
      await tester.tapAt(const Offset(200, 60));
      await settle(tester, 800);
      expect(labels(tester), ['Home', 'Calendar', 'Wallet', 'Lists']);
      final s = tester.element(find.byType(Shell)).getInheritedWidgetOfExactType<Hub>()!.settings;
      expect(startTab(s), ShellTab.todo);
      expect(tester.takeException(), isNull);
    });
  });

  test('a bar or start tab saved with Notes opens Lists', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final s = AppSettings(db);
    await s.load();
    await s.setRaw(tabsKey, 'notes,calendar');
    await s.setRaw(startTabKey, 'notes');
    expect(barTabs(s), [ShellTab.todo, ShellTab.calendar]);
    expect(startTab(s), ShellTab.todo);
  });

  testWidgets('Hub opens on the chosen start tab', (tester) async {
    phone(tester);
    await pumpWithDb(
      tester,
      (db, s) {
        s.setRaw(startTabKey, 'wallet');
        return HubApp(db: db, settings: s);
      },
      (_) async {
        await settle(tester, 800);
        expect(selected(tester), 2);
        expect(find.byType(WalletPage), findsOneWidget);
      },
    );
  });

  testWidgets('Home hides the weather, Today strip and apps it is told to', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      expect(find.byType(AppGrid), findsOneWidget);
      final s = tester.element(find.byType(Shell)).getInheritedWidgetOfExactType<Hub>()!.settings;
      await tester.runAsync(() => setHomeShows(s, 'apps', false));
      await tester.runAsync(() => setHomeShows(s, 'today', false));
      await settle(tester);
      expect(find.byType(AppGrid), findsNothing);
      expect(find.textContaining(RegExp('Spent|To spend')), findsNothing);
      await tester.runAsync(() => setHomeShows(s, 'apps', true));
      await tester.runAsync(() => s.setRaw(homeAppGroupsKey, 'off'));
      await settle(tester);
      expect(find.byType(AppGrid), findsOneWidget);
      expect(find.text('Plan'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Me shows the new options, and a larger text size scales text app-wide', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (db) async {
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(HomePage), matching: find.byType(CircleAvatar)).first);
      await settle(tester, 800);
      expect(find.byType(MePage), findsOneWidget);
      await tester.tap(find.text('Largest'));
      await settle(tester);
      final scaler = MediaQuery.textScalerOf(tester.element(find.byType(MePage)));
      expect(scaler.scale(10), closeTo(12.5, 0.01));
      await tester.scrollUntilVisible(find.text('Bottom tabs'), 300);
      expect(find.text('Group apps'), findsOneWidget);
      expect(find.text('Home, Calendar, Wallet, Lists, AI'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Everything chosen is in the settings table, which a backup carries.
      final backup = (await tester.runAsync(() => exportBackup(db)))!;
      final keys = [for (final r in backup['tables']['settings'] as List) r['key']];
      expect(keys, contains(textSizeKey));
    });
  });
}
