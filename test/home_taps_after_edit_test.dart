import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/dashboard.dart';
import 'package:hub/shell/home_page.dart';

import 'widget_test.dart' show pumpWithDb;

/// After arranging Home (shape, style, size, colour) and pressing Done, everything on Home still opens:
/// the app circles (a space of your own, Wallet) and the widgets themselves.
void main() {
  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 4));
    }
  }

  bool homeOnTop(WidgetTester tester) =>
      ModalRoute.of(tester.element(find.byType(HomePage, skipOffstage: false)))!.isCurrent;
  Finder home(Finder f) => find.descendant(of: find.byType(HomePage), matching: f);

  Future<void> reveal(WidgetTester tester, Finder f) async {
    tester.state<ScrollableState>(home(find.byType(Scrollable)).first).position.jumpTo(0);
    // What comes into view loads its lists from the database.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump();
    await tester.scrollUntilVisible(f, 250, scrollable: home(find.byType(Scrollable)).first);
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 100));
    // Keep it clear of the ask bar and the bottom bar.
    final y = tester.getCenter(f).dy;
    final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    if (y > h - 200) {
      await tester.drag(home(find.byType(Scrollable)).first, Offset(0, -(y - h / 2)));
      await settle(tester, 200);
    }
  }

  /// Taps [f] and checks that a page opened over Home, then goes back.
  Future<void> expectOpens(WidgetTester tester, Finder f, String what) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester, 800);
    expect(tester.takeException(), isNull, reason: what);
    expect(homeOnTop(tester), isFalse, reason: '$what did not open');
    await tester.binding.handlePopRoute();
    await settle(tester, 800);
    expect(homeOnTop(tester), isTrue, reason: 'back from $what');
  }

  for (final style in dashStyles) {
    testWidgets('Home still opens things after customising, style $style', (tester) async {
      tester.view.physicalSize = const Size(1080, 2424);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (db) async {
        // A space of your own, made once the starting data is in.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await db.saveSpace(SpacesCompanion.insert(name: 'Gym', icon: const Value('fitness'), color: 0xFF2F8F5B));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        expect((await tester.runAsync(() => db.select(db.spaces).get()))!.map((s) => s.name), contains('Gym'));
        // Every widget kind that opens something inside Hub. Shortcuts open other apps; the clock only tells time.
        final kinds = [
          for (final k in dashKinds)
            if (k.type != 'shortcuts' && k.type != 'clock') k,
        ];
        final settings = tester.element(find.byType(HomePage)).settings;
        await tester.runAsync(
          () => saveDashboard(settings, [
            for (final k in kinds)
              DashItem(
                id: 't-${k.type}',
                type: k.type,
                size: k.size,
                label: k.type == 'countdown' ? 'Trip' : null,
                date: k.type == 'countdown' ? DateTime(2030) : null,
                text: k.type == 'focus' ? 'Ship it' : null,
              ),
          ]),
        );
        await settle(tester);
        final shapes = dashShapes.keys.toList();
        for (final (round, size) in const ['Small', 'Medium', 'Large'].indexed) {
          // Arrange: every widget gets this style, a shape, a colour and a size.
          // Back to the top of Home, where the Edit home button is.
          tester.state<ScrollableState>(home(find.byType(Scrollable)).first).position.jumpTo(0);
          await settle(tester, 100);
          await tester.tap(find.byTooltip('Edit home'));
          await settle(tester);
          final n = find.byTooltip('Customise').evaluate().length;
          for (var i = 0; i < n; i++) {
            final badge = find.byTooltip('Customise').at(i);
            // Well clear of the glass panel at the bottom, as a thumb would have it.
            await Scrollable.ensureVisible(badge.evaluate().single, alignment: 0.3);
            await settle(tester, 100);
            await tester.tap(badge);
            await settle(tester, 600);
            final sheet = find.byType(BottomSheet);
            await tester.tap(
              find.descendant(of: sheet, matching: find.text(dashShapeLabels[shapes[(i + round) % 4]]!)),
            );
            await settle(tester, 100);
            final styleChip = find.descendant(of: sheet, matching: find.text(dashStyleLabels[style]!));
            if (styleChip.evaluate().isNotEmpty) {
              await tester.tap(styleChip);
              await settle(tester, 100);
              await tester.tap(find.descendant(of: sheet, matching: find.byType(InkWell)).at(i % 3));
              await settle(tester, 100);
            }
            final sizes = find.descendant(of: sheet, matching: find.text(size));
            if (sizes.evaluate().isNotEmpty) {
              await tester.tap(sizes.first);
              await settle(tester, 100);
            }
            await tester.tap(find.descendant(of: sheet, matching: find.text('Done')));
            await settle(tester, 600);
          }
          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(find.text('Edit home'), findsNothing);
          // The app grid is built again after arranging; let its lists load from the database.
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await settle(tester);
          // The apps.
          await expectOpens(tester, home(find.text('Gym')), 'Gym');
          await expectOpens(tester, home(find.text('Wallet')).first, 'Wallet');

          // The widgets: each opens something when tapped where it shows its name.
          for (final item in loadDashboard(settings)) {
            final frame = find.byWidgetPredicate((w) => w is DashFrame && w.item.id == item.id);
            final what = '${item.type} (${item.size}, ${item.shape}, ${item.style})';
            await reveal(tester, frame);
            await tester.tapAt(tester.getTopLeft(frame) + const Offset(30, 24));
            await settle(tester, 800);
            expect(tester.takeException(), isNull, reason: what);
            expect(homeOnTop(tester), isFalse, reason: '$what did not open');
            await tester.binding.handlePopRoute();
            await settle(tester, 800);
            expect(homeOnTop(tester), isTrue, reason: 'back from $what');
          }
        }
      });
    });
  }
}
