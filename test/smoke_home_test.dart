import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/ai/ai_page.dart';
import 'package:hub/core/theme.dart';
import 'package:hub/shell/home_page.dart';
import 'package:hub/shell/me_page.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/dashboard.dart';

import 'widget_test.dart' show pumpWithDb;

/// Walks the main phone flows at small sizes in both themes and fails on any
/// exception or layout overflow.
void main() {
  const sizes = [Size(360, 740), Size(320, 568)];
  for (final size in sizes) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('smoke ${size.width.toInt()}x${size.height.toInt()} ${mode.name}', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        var step = 'start';
        Future<void> settle([int ms = 400]) async {
          for (var i = 0; i < 4; i++) {
            await tester.pump(Duration(milliseconds: ms ~/ 4));
          }
          expect(tester.takeException(), isNull, reason: step);
        }

        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(f);
        }

        Finder nav(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
        Future<void> show(Finder f, Type page, [double step = 200]) async {
          await tester.scrollUntilVisible(
            f,
            step,
            scrollable: find.descendant(of: find.byType(page), matching: find.byType(Scrollable)).first,
          );
          await tester.ensureVisible(f);
          await tester.pump(const Duration(milliseconds: 100));
        }

        await pumpWithDb(
          tester,
          (db, s) {
            s.themeMode = mode;
            return HubApp(db: db, settings: s);
          },
          (db) async {
            await settle();

            // Every tab.
            for (final tab in ['Calendar', 'Wallet', 'To-do', 'AI', 'Home']) {
              await tap(nav(tab));
              await settle();
            }

            // AI: the tab is the chat; settings sit behind the model chip.
            await tap(nav('AI'));
            await settle();
            await tap(find.text('Hub agent'));
            await settle();
            expect(find.text('Ask your Hub'), findsOneWidget);
            await tap(find.text('Chat'));
            await settle();
            await tap(find.byTooltip('AI settings'));
            await settle(800);
            await tap(find.text('API key'));
            await settle();
            expect(find.text('Paste'), findsOneWidget);
            await tap(find.text('Anthropic'));
            await settle();
            await tap(find.text('Claude Sonnet'));
            await settle();
            await tap(find.text('Claude Code (my plan)'));
            await settle();
            await tap(find.text('Opus'));
            await settle();
            await tap(find.text('Claude app (my plan)'));
            await settle();
            await tester.tapAt(const Offset(10, 10));
            await settle(800);
            expect(find.text('AI settings'), findsNothing);
            expect(find.byType(AiPage), findsOneWidget);
            await tap(nav('Home'));
            await settle();

            // Profile and settings apply at once.
            await tap(find.descendant(of: find.byType(HomePage), matching: find.byType(CircleAvatar)).first);
            await settle(800);
            expect(find.text('Appearance'), findsOneWidget);
            await tap(find.byTooltip('Pink'));
            await settle();
            final pink = accentById('pink').forBrightness(mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
            expect(Palette.of(tester.element(find.text('Appearance'))).accent, pink);
            await show(find.text('Compact'), MePage);
            await tap(find.text('Compact'));
            await tap(find.text('Dark grey'));
            await settle();
            await show(find.text('Greeting on Home'), MePage);
            await tap(find.text('Greeting on Home'));
            await settle();
            await tester.pageBack();
            await settle(800);
            expect(find.textContaining('Good '), findsNothing);
            expect(Palette.of(tester.element(find.byType(NavigationBar))).accent, pink);

            // Edit home with the button, then with a long press.
            await tap(find.byTooltip('Edit home'));
            await settle();
            expect(find.text('Edit home'), findsOneWidget);
            await tap(find.text('Done'));
            await settle();
            await tester.longPress(find.descendant(of: find.byType(HomePage), matching: find.text('Search')).first);
            await settle();
            expect(find.text('Edit home'), findsOneWidget);

            // Add every kind from the gallery.
            for (final kind in dashKinds) {
              step = 'add ${kind.type}';
              await tap(find.byTooltip('Add a widget'));
              await settle(600);
              final tile = find.text(kind.description);
              await tester.scrollUntilVisible(
                tile,
                200,
                scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
              );
              await tester.pump(const Duration(milliseconds: 100));
              await tap(tile);
              await settle(600);
              if (kind.type == 'shortcuts') {
                await tap(find.text('X').last);
                await tap(find.text('Done').last);
                await settle(600);
              }
              if (kind.type == 'countdown' || kind.type == 'focus') {
                await tester.enterText(find.byType(TextField).last, 'Trip');
                await tap(find.text('Save'));
                await settle(600);
              }
            }

            // Customise each widget.
            await show(find.byTooltip('Add a widget'), HomePage, -500);
            final count = find.byTooltip('Customise').evaluate().length;
            expect(count, greaterThanOrEqualTo(dashKinds.length));
            for (var i = 0; i < count; i++) {
              step = 'customise $i';
              final badge = find.byTooltip('Customise').at(i);
              await tester.ensureVisible(badge);
              await settle(100);
              await tap(badge);
              await settle(600);
              await tap(find.text('Rounded').last);
              await settle(100);
              await tap(find.text('Done').last);
              await settle(600);
            }

            // Remove with undo.
            step = 'undo';
            await tester.ensureVisible(find.byTooltip('Remove').first);
            final before = find.byTooltip('Remove').evaluate().length;
            await tap(find.byTooltip('Remove').first);
            await settle();
            expect(find.byTooltip('Remove').evaluate().length, before - 1);
            tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
            await settle();
            expect(find.byTooltip('Remove').evaluate().length, before);
            await show(find.byTooltip('Add a widget'), HomePage, -500);
            await tap(find.text('Done').first);
            await settle();

            // Spaces: open and make one.
            step = 'spaces';
            await tester.pump(const Duration(seconds: 5));
            await show(find.text('Spaces').first, HomePage, 300);
            await tap(find.text('Spaces').first);
            await settle(800);
            await tap(find.text('New space'));
            await settle(600);
            await tester.enterText(find.byType(TextField).last, 'Gym');
            await tester.pump();
            await tester.tap(find.text('Save'));
            await settle(600);
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
            await settle();
            expect(find.widgetWithText(ListTile, 'Gym'), findsOneWidget);
            await tester.pageBack();
            await settle(800);
          },
        );
      });
    }
  }
}
