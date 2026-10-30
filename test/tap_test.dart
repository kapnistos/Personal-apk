import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/registry.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/dashboard.dart';
import 'package:hub/shell/home_page.dart';
import 'package:hub/shell/shell.dart';
import 'package:hub/shell/shortcuts.dart';

import 'widget_test.dart' show pumpWithDb;

/// Every tappable thing on Home has to answer the first tap, also right after
/// scrolling, after leaving edit mode, and when tapped twice quickly.
void main() {
  final launched = <Uri>[];
  setUp(() {
    launched.clear();
    shortcutLauncher = (url, mode) async {
      launched.add(url);
      return true;
    };
  });

  const shortcutNames = ['X', 'Instagram', 'Reddit', 'Gmail', 'GitHub', 'ABN AMRO', 'WhatsApp', 'Revolut'];

  for (final size in const [Size(360, 740), Size(412, 915)]) {
    testWidgets('every Home tap works ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      Future<void> settle([int ms = 400]) async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(Duration(milliseconds: ms ~/ 4));
        }
        expect(tester.takeException(), isNull);
      }

      bool homeOnTop() => ModalRoute.of(tester.element(find.byType(Shell, skipOffstage: false)))!.isCurrent;
      final homeList = find.descendant(of: find.byType(HomePage), matching: find.byType(Scrollable)).first;

      Future<void> reveal(Finder f) async {
        // Scroll to the top first so every target is found by scrolling down.
        await tester.drag(homeList, const Offset(0, 5000));
        await tester.pump(const Duration(seconds: 1));
        // Home's own top is tall, so widgets further down are only built once scrolled near.
        bool built() {
          try {
            return f.hitTestable().evaluate().isNotEmpty;
          } on StateError {
            return false;
          }
        }

        for (var i = 0; i < 80 && !built(); i++) {
          await tester.drag(homeList, const Offset(0, -150));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 100));
        // Keep it clear of the bottom bar.
        await tester.ensureVisible(f.first);
        await tester.pump(const Duration(seconds: 1));
      }

      Future<void> back() async {
        if (!homeOnTop()) {
          Navigator.of(tester.element(find.byType(Shell, skipOffstage: false))).pop();
          await settle(800);
        }
        expect(homeOnTop(), isTrue);
      }

      await pumpWithDb(
        tester,
        (db, s) {
          final items = defaultDashboard();
          items.firstWhere((i) => i.type == 'shortcuts').shortcuts = [
            for (final n in shortcutNames) shortcutCatalog.firstWhere((s) => s.name == n),
          ];
          s.setRaw('home.layout', jsonEncode([for (final i in items) i.toJson()]));
          return HubApp(db: db, settings: s);
        },
        (db) async {
          await settle();

          // Every app tile opens its page (or says it is coming later).
          final grid = find.byType(AppGrid);
          for (final app in miniApps) {
            final tile = find.descendant(of: grid, matching: find.text(app.title));
            await reveal(tile);
            await tester.tap(tile, warnIfMissed: false);
            await settle(800);
            if (app.available) {
              expect(homeOnTop(), isFalse, reason: 'tap ${app.title}');
              await back();
            } else {
              expect(find.byType(SnackBar), findsOneWidget, reason: 'tap ${app.title}');
            }
          }

          // The space around each circle belongs to it too: no dead band under a label or between two circles.
          for (final name in ['Calendar', 'To-do']) {
            final tile = find.descendant(of: grid, matching: find.text(name));
            await reveal(tile);
            final label = tester.getRect(tile);
            await tester.tapAt(Offset(label.center.dx, label.bottom + 6));
            await settle(800);
            expect(homeOnTop(), isFalse, reason: 'tap under $name');
            await back();
          }
          // Bring the Plan label to the top, so the whole first row of circles is on screen.
          await reveal(find.descendant(of: grid, matching: find.text('Plan')));
          final cal = tester.getRect(find.descendant(of: grid, matching: find.text('Calendar')));
          final todo = tester.getRect(find.descendant(of: grid, matching: find.text('To-do')));
          // Halfway between the two circles, level with them (a circle sits about 35 above its label).
          await tester.tapAt(Offset((cal.center.dx + todo.center.dx) / 2, cal.top - 35));
          await settle(800);
          expect(homeOnTop(), isFalse, reason: 'tap between two circles');
          await back();

          // Every shortcut launches.
          for (final n in shortcutNames) {
            final s = shortcutCatalog.firstWhere((x) => x.name == n);
            final all = find.descendant(of: find.byType(DashFrame), matching: find.text(n));
            // Home's own top comes first now, so the widgets may not be built until scrolled to.
            await reveal(all);
            final tile = all.first;
            launched.clear();
            await tester.tap(tile, warnIfMissed: false);
            await settle();
            expect(launched, isNotEmpty, reason: 'shortcut $n');
            expect(launched.first.toString(), s.appUrl ?? s.url, reason: 'shortcut $n');
          }

          // Right after a fling, then a tap: the first tap only stops the fling, as on Android,
          // but once the list rests a tap must land.
          final weather = find.descendant(of: grid, matching: find.text('Weather'));
          await reveal(weather);
          await tester.fling(homeList, const Offset(0, -300), 2000);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          await reveal(weather);
          await tester.tap(weather, warnIfMissed: false);
          await settle(800);
          expect(homeOnTop(), isFalse, reason: 'tap after scroll');
          await back();

          // In and out of edit mode, then tap at once.
          // Holding an app tile starts arranging, like holding any other part of Home.
          await reveal(weather);
          await tester.longPress(weather);
          await settle();
          expect(tester.widget<Dashboard>(find.byType(Dashboard)).editing, isTrue);
          await reveal(find.text('Edit home'));
          await tester.tap(find.text('Done').first);
          await tester.pump(const Duration(milliseconds: 50));
          await reveal(weather);
          await tester.tap(weather, warnIfMissed: false);
          await settle(800);
          expect(homeOnTop(), isFalse, reason: 'tap after edit mode');
          await back();
          final xs = find.descendant(of: find.byType(DashFrame), matching: find.text('X'));
          await reveal(xs);
          final x = xs.first;
          launched.clear();
          await tester.tap(x, warnIfMissed: false);
          await settle();
          expect(launched, isNotEmpty, reason: 'shortcut after edit mode');

          // A quick double tap opens one page, not two, and does not get stuck.
          final notes = find.descendant(of: grid, matching: find.text('Notes'));
          await reveal(notes);
          await tester.tap(notes, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 60));
          await tester.tap(notes, warnIfMissed: false);
          await settle(800);
          expect(homeOnTop(), isFalse);
          await back();

          // Other tappable widgets on Home.
          final search = find.descendant(of: find.byType(HomePage), matching: find.text('Search')).first;
          await reveal(search);
          await tester.tap(search);
          await settle(800);
          expect(homeOnTop(), isFalse, reason: 'search');
          await back();

          // Every bottom tab.
          final nav = find.byType(NavigationBar);
          for (final (i, tab) in ['Calendar', 'To-do', 'AI', 'Home'].indexed) {
            await tester.tap(find.descendant(of: nav, matching: find.text(tab)));
            await settle();
            expect(tester.widget<NavigationBar>(nav).selectedIndex, (i + 1) % 4, reason: 'tab $tab');
          }
        },
      );
    });
  }
}
