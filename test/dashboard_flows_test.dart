// Every Home widget at every size it offers, with demo data, on the owner's phone and a small one with large
// text: each one draws without overflowing and a tap opens its app without a crash.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/shell/dashboard.dart';

import '../screenshots/screenshots_test.dart' show loadFonts;
import 'flows_test.dart' show configName, done, pumpPage, scrollThrough, settle;

void main() {
  personalEdition = false;
  setUpAll(loadFonts);
  setUp(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (_) async => null);
  });

  final layout = jsonEncode([
    for (final k in dashKinds)
      if (!k.ownCard)
        for (final s in k.sizes) {'id': '${k.type}-$s', 'type': k.type, 'size': s},
  ]);

  for (final c in const [(Size(412, 915), true, 1.3), (Size(360, 740), false, 1.3), (Size(412, 915), false, 1.0)]) {
    testWidgets('every Home widget draws and opens ${configName(c)}', (t) async {
      final db = await pumpPage(t, c, null, before: (s) => s.setRaw('home.layout', layout));
      await scrollThrough(t);
      // Back at the bottom of Home, where the widgets are, whatever the top of Home takes up.
      final home = t.state<ScrollableState>(
        find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      home.position.jumpTo(home.position.maxScrollExtent);
      await t.pump();
      expect(find.byType(DashFrame), findsWidgets);
      await done(t, db);
    });
  }

  testWidgets('the clock widget opens the calendar', (t) async {
    final db = await pumpPage(
      t,
      (const Size(412, 915), true, 1.3),
      null,
      before: (s) => s.setRaw(
        'home.layout',
        jsonEncode([
          {'id': 'c', 'type': 'clock', 'size': 's'},
        ]),
      ),
    );
    final week = find.textContaining('· week');
    await t.scrollUntilVisible(
      week,
      300,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
    await t.pump();
    await t.tap(week);
    await settle(t);
    expect(find.byType(CalendarPage), findsOneWidget);
    await done(t, db);
  });
}
