import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/weather/weather_service.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/dashboard.dart';
import 'package:hub/shell/home_page.dart';

/// Edit home end to end: every widget kind can be added, renders at phone sizes in both themes, and
/// removing, moving, resizing and resetting all stick across a restart.
void main() {
  void seedWeather() {
    final now = DateTime.now();
    final h0 = DateTime(now.year, now.month, now.day, now.hour);
    final today = DateTime(now.year, now.month, now.day);
    final f = Forecast(
      temperature: 11.4,
      feelsLike: 8.9,
      humidity: 78,
      wind: 21,
      code: 61,
      isDay: true,
      hours: [
        for (var i = 0; i < 24; i++)
          HourForecast(time: h0.add(Duration(hours: i)), temperature: 11, code: 61, rainChance: 70),
      ],
      days: [
        for (var d = 0; d < 3; d++)
          DayForecast(
            date: today.add(Duration(days: d)),
            max: 13,
            min: 6,
            code: 61,
            rainChance: 70,
            sunrise: today.add(Duration(days: d, hours: 7)),
            sunset: today.add(Duration(days: d, hours: 17)),
          ),
      ],
      fetchedAt: DateTime.now(),
    );
    final n = Nowcast(
      source: 'test',
      points: [for (var i = 0; i < 12; i++) RainPoint(now.add(Duration(minutes: 5 * i)), i < 4 ? 0 : 1.2)],
    );
    // The seeded city: Amsterdam.
    WeatherService.instance.seed(52.37403, 4.88969, f, n);
  }

  /// Runs [body] on Home with a fresh database. [restart] throws the app away and builds it again from the
  /// same database and settings, the way a phone does after the app is closed.
  Future<void> onHome(
    WidgetTester tester,
    Size size,
    ThemeMode mode,
    Future<void> Function(AppSettings s, Future<void> Function() restart) body, {
    String? layout,
  }) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
    await tester.runAsync(() async {
      await settings.load();
      await settings.setThemeMode(mode);
      if (layout != null) await settings.setRaw('home.layout', layout);
    });
    Future<void> settle([int ms = 400]) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(Duration(milliseconds: ms ~/ 4));
      }
    }

    await tester.pumpWidget(HubApp(db: db, settings: settings));
    await settle();
    Future<void> restart() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(HubApp(db: db, settings: settings));
      await settle();
    }

    await body(settings, restart);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(db.close);
  }

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 4));
    }
  }

  Finder home(Finder f) => find.descendant(of: find.byType(HomePage), matching: f);
  List<DashItem> saved(AppSettings s) => [
    for (final j in jsonDecode(s.raw('home.layout') ?? '[]') as List) DashItem.fromJson((j as Map).cast()),
  ];

  Future<void> startEditing(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Edit home'));
    await settle(tester);
    expect(find.text('Edit home'), findsOneWidget);
  }

  Future<void> addFromGallery(WidgetTester tester, DashKind kind) async {
    await tester.ensureVisible(find.byTooltip('Add a widget'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Add a widget'));
    await settle(tester, 600);
    final tile = find.descendant(of: find.byType(BottomSheet), matching: find.text(kind.description));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'gallery preview of ${kind.type}');
    await tester.tap(tile);
    await settle(tester, 600);
    if (kind.type == 'shortcuts') {
      await tester.tap(find.text('X').last);
      await tester.tap(find.text('Done').last);
      await settle(tester, 600);
    }
    if (kind.type == 'countdown' || kind.type == 'focus') {
      await tester.enterText(find.byType(TextField).last, 'Trip');
      await tester.tap(find.text('Save'));
      await settle(tester, 600);
    }
  }

  for (final size in const [Size(412, 915), Size(360, 740)]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      final name = '${size.width.toInt()}x${size.height.toInt()} ${mode.name}';

      testWidgets('every widget kind can be added and renders, $name', (tester) async {
        seedWeather();
        await onHome(tester, size, mode, (s, restart) async {
          await startEditing(tester);
          // Start from nothing, so each added widget is easy to find.
          while (find.byTooltip('Remove').evaluate().isNotEmpty) {
            await tester.ensureVisible(find.byTooltip('Remove').first);
            await tester.tap(find.byTooltip('Remove').first);
            await settle(tester, 200);
          }
          expect(saved(s), isEmpty);
          expect(dashKinds.map((k) => k.type), contains('weather'));

          for (final kind in dashKinds) {
            await addFromGallery(tester, kind);
            expect(tester.takeException(), isNull, reason: 'add ${kind.type}');
            expect(saved(s).last.type, kind.type, reason: 'saved ${kind.type}');
          }
          expect(saved(s).map((i) => i.type), [for (final k in dashKinds) k.type]);

          // Every widget draws something, at every size it offers.
          for (final pass in ['start', 's', 'm', 'l']) {
            if (pass != 'start') {
              final items = saved(s);
              for (final i in items) {
                if (kindOf(i.type).sizes.contains(pass)) i.size = pass;
              }
              await tester.runAsync(() => saveDashboard(s, items));
              await settle(tester);
            }
            for (final item in saved(s)) {
              final frame = find.byWidgetPredicate((w) => w is DashFrame && w.item.id == item.id);
              expect(frame, findsOneWidget, reason: '${item.type} on Home');
              await tester.ensureVisible(frame);
              await tester.pump(const Duration(milliseconds: 50));
              expect(tester.takeException(), isNull, reason: '${item.type} at ${item.size}');
              expect(tester.getSize(frame).height, greaterThan(40), reason: '${item.type} at ${item.size} is empty');
            }
          }

          // Leaving edit mode shows them all, still without errors.
          // Done waits in the bar at the bottom, however far down the list you are.
          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(find.text('Edit home'), findsNothing);
          for (final item in saved(s)) {
            final frame = find.byWidgetPredicate((w) => w is DashFrame && w.item.id == item.id);
            await tester.scrollUntilVisible(frame, 300, scrollable: home(find.byType(Scrollable)).first);
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull, reason: '${item.type} outside edit mode');
          }
        });
      });
    }
  }

  testWidgets('remove, move, resize and reset are saved and survive a restart', (tester) async {
    await onHome(tester, const Size(412, 915), ThemeMode.dark, (s, restart) async {
      await startEditing(tester);
      final start = saved(s).isEmpty ? defaultDashboard() : saved(s);
      final types = start.map((i) => i.type).toList();

      // Remove the second widget.
      await tester.tap(find.byTooltip('Remove').at(1));
      await settle(tester);
      expect(saved(s).map((i) => i.type), [...types]..removeAt(1));

      // Move the first one down with the buttons in its sheet.
      await tester.tap(find.byTooltip('Customise').first);
      await settle(tester, 600);
      await tester.tap(find.byTooltip('Move down'));
      await settle(tester, 200);
      // Make it small.
      await tester.tap(find.text('Small').last);
      await settle(tester, 200);
      await tester.tap(find.text('Done').last);
      await settle(tester, 600);
      final afterMove = saved(s);
      expect(afterMove[1].type, types[0]);
      expect(afterMove[1].size, 's');

      // Drag the third widget onto the first.
      final third = afterMove[2];
      final first = afterMove[0];
      Finder frameOf(DashItem i) => find.byWidgetPredicate((w) => w is DashFrame && w.item.id == i.id);
      await tester.ensureVisible(frameOf(first));
      await settle(tester, 200);
      final from = tester.getCenter(frameOf(third));
      final to = tester.getCenter(frameOf(first));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 400));
      expect(frameOf(third), findsNWidgets(2), reason: 'the drag started');
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await gesture.up();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(saved(s).first.id, third.id, reason: 'dragged to the top');

      final before = saved(s).map((i) => '${i.type}/${i.size}').toList();
      await restart();
      expect(saved(s).map((i) => '${i.type}/${i.size}').toList(), before);
      await startEditing(tester);
      expect(find.byTooltip('Remove').evaluate().length, before.length);

      // Reset goes back to the starting widgets.
      await tester.tap(find.byTooltip('Back to the starting layout'));
      await settle(tester);
      await tester.tap(find.text('Reset'));
      await settle(tester);
      expect(saved(s).map((i) => i.type), defaultDashboard().map((i) => i.type));
      await restart();
      expect(saved(s).map((i) => i.type), defaultDashboard().map((i) => i.type));
    });
  });

  testWidgets('a weather widget shows even before a city is chosen', (tester) async {
    final layout = jsonEncode([
      {'id': 'a', 'type': 'weather', 'size': 's'},
      {'id': 'b', 'type': 'weather', 'size': 'm'},
    ]);
    await onHome(tester, const Size(360, 740), ThemeMode.dark, layout: layout, (s, restart) async {
      final db = tester.element(find.byType(HomePage)).db;
      await tester.runAsync(() => db.delete(db.cities).go());
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Choose a city').first,
        300,
        scrollable: home(find.byType(Scrollable)).first,
      );
      expect(find.text('Choose a city'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an older layout with unknown, retired or broken widgets loads without losing them', (tester) async {
    final old = jsonEncode([
      {'id': 'a', 'type': 'weather', 'size': 'l'},
      {'id': 'b', 'type': 'search', 'size': 'l'},
      {'id': 'c', 'type': 'apps', 'size': 'l'},
      {'id': 'd', 'type': 'tasks', 'size': 'xl'},
      {'id': 'e', 'type': 'from-the-future', 'size': 'm'},
      {'type': 'notes'},
      'nonsense',
      {'id': 'f', 'type': 'clock', 'size': 's', 'color': 'red', 'shortcuts': 'none'},
    ]);
    await onHome(tester, const Size(360, 740), ThemeMode.light, layout: old, (s, restart) async {
      expect(tester.takeException(), isNull);
      await startEditing(tester);
      // Tasks (at a size it offers), notes (given an id) and the clock (without the broken colour) show. The big
      // weather card, search and apps are part of Home itself now; the unknown kind waits in the saved layout
      // for a build that knows it.
      expect(find.byTooltip('Remove').evaluate().length, 3);
      expect(loadDashboard(s).map((i) => i.type), ['tasks', 'notes', 'clock']);
      await tester.tap(find.byTooltip('Remove').last);
      await settle(tester);
      expect(s.raw('home.layout'), contains('from-the-future'));
      expect(find.byTooltip('Remove').evaluate().length, 2);
      await restart();
      expect(tester.takeException(), isNull);
      expect(loadDashboard(s).map((i) => i.type), ['tasks', 'notes']);
      expect(s.raw('home.layout'), contains('from-the-future'));
    });
  });
}
