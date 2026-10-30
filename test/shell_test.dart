import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/home_page.dart';

import 'widget_test.dart' show pumpWithDb;

/// The tabs: Wallet is one of them, Ctrl+1 to 5 reach each, back goes Home before it leaves the app, and
/// Home's shortcuts open the right tab.
void main() {
  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 4));
    }
  }

  int selected(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
  Finder nav(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('Wallet is a tab, without a back button, between Calendar and To-do', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      final labels = [
        for (final d in tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations)
          (d as NavigationDestination).label,
      ];
      expect(labels, ['Home', 'Calendar', 'Wallet', 'To-do', 'AI']);
      await tester.tap(nav('Wallet'));
      await settle(tester, 800);
      expect(selected(tester), 2);
      expect(find.byType(WalletPage), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('back on another tab goes Home; back on Home is left to the system', (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      for (final tab in ['Calendar', 'Wallet', 'To-do', 'AI']) {
        await tester.tap(nav(tab));
        await settle(tester);
        expect(selected(tester), isNot(0));
        // Android's back button.
        final handled = await tester.binding.handlePopRoute();
        await settle(tester);
        expect(handled, isTrue, reason: tab);
        expect(selected(tester), 0, reason: 'back from $tab');
      }

      // Back while arranging Home only ends arranging.
      await tester.tap(find.byTooltip('Edit home'));
      await settle(tester);
      expect(find.text('Edit home'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Edit home'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Ctrl+1 to Ctrl+5 open the tabs, and the side rail lists Wallet on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);
      expect(find.descendant(of: rail, matching: find.text('Wallet')), findsOneWidget);
      const keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ];
      for (final i in [2, 4, 1, 3, 0]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(keys[i]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle(tester);
        expect(tester.widget<NavigationRail>(rail).selectedIndex, i);
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets("the Today strip's money opens the Wallet tab", (tester) async {
    phone(tester);
    await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (_) async {
      await settle(tester);
      final cell = find.descendant(of: find.byType(HomePage), matching: find.textContaining(RegExp('Spent|To spend')));
      await tester.ensureVisible(cell.first);
      await tester.pump();
      await tester.tap(cell.first);
      await settle(tester);
      expect(selected(tester), 2);
      // A tab, not a page pushed over Home.
      expect(find.byTooltip('Back'), findsNothing);
    });
  });
}
