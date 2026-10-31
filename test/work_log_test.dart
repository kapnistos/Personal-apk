// The Job space's work log: old rows load, hours go in through the day sheet, the contract through the tune sheet.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/spaces/work_hours.dart';
import 'package:intl/intl.dart';
import 'package:hub/apps/spaces/work_log.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';

void main() {
  Future<(AppDatabase, AppSettings)> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
    final today = dateOnly(DateTime.now());
    await tester.runAsync(() async {
      await settings.load();
      // Rows as older versions wrote them: a status, sometimes hours, a plain note.
      await db.setWorkDay(today, 'work');
      await db.setWorkDay(addDays(today, -1), 'holiday', note: 'Beach');
    });
    await tester.pumpWidget(
      Hub(
        db: db,
        settings: settings,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en', 'GB')],
          locale: const Locale('en', 'GB'),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [WorkLogCard(color: Color(0xFF1F7A5A))],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (db, settings);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('hold a day, pick 9 h, save: the hours land on that day', (tester) async {
    final (db, _) = await pump(tester);
    final today = dateOnly(DateTime.now());
    expect(find.textContaining('Hours in'), findsOneWidget);
    await tester.longPress(find.bySemanticsLabel(RegExp('^${DateFormat('d MMMM').format(today)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 h'));
    await tester.pump();
    // Weekends have no contract hours, so there all 9 count as overtime.
    final weekend = today.weekday >= DateTime.saturday;
    expect(find.text(weekend ? 'All overtime: not a workday' : '1 h more than a normal day'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final days = await tester.runAsync(() => db.watchWorkDays(today, addDays(today, 1)).first);
    expect(days!.single.hours, 9);
    expect(days.single.status, 'work');
    expect(find.text('9h'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(db.close);
  });

  testWidgets('the tune sheet saves the contract and the allowance', (tester) async {
    final (db, settings) = await pump(tester);
    await tester.tap(find.byTooltip('Hours and holidays'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Less').first);
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Friday'));
    await tester.pump();
    expect(find.text('9 h a day over 4 days'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(WorkSchedule.parse(settings.raw(WorkSchedule.key)).hours, [9, 9, 9, 9, 0, 0, 0]);
    expect(settings.raw('job.holidayAllowance'), '25');
    expect(find.textContaining('36 h a week, Mon–Thu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(db.close);
  });

  testWidgets('large text: card and both sheets fit at 360 wide', (tester) async {
    final (db, _) = await pump(tester, scale: 1.6);
    await tester.longPress(find.bySemanticsLabel(RegExp('^${DateFormat('d MMMM').format(DateTime.now())}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Save'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hours and holidays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Per day'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(db.close);
  });
}
