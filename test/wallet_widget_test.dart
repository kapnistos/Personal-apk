import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/format.dart';
import 'package:hub/core/settings.dart';

/// Builds [page] on a small 320 x 640 phone with some wallet data already in place.
Future<void> pumpSmall(WidgetTester tester, Widget page, Future<void> Function() check, {String? target}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  final settings = AppSettings(db);
  final now = DateTime.now();
  await tester.runAsync(() async {
    await settings.load();
    if (target != null) await settings.setRaw('wallet.target', target);
    await db.setBudget('Groceries', 20000);
    for (var i = 0; i < 6; i++) {
      await db.addEntry(
        EntriesCompanion.insert(
          amountCents: 1234 + i,
          kind: EntryKind.expense,
          category: 'Groceries',
          note: const Value('Corner shop'),
          date: DateTime(now.year, now.month, 1, 12),
        ),
      );
    }
    await db.saveSubscription(
      SubscriptionsCompanion.insert(
        name: 'Gym',
        amountCents: 2500,
        kind: EntryKind.subscription,
        category: 'Gym',
        nextDate: addDays(dateOnly(now), 3),
      ),
    );
  });
  await tester.pumpWidget(
    Hub(
      db: db,
      settings: settings,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 100));
  await check();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
  await tester.runAsync(db.close);
}

void main() {
  testWidgets('spending tab fits a small phone and shows budget progress', (tester) async {
    await pumpSmall(tester, const WalletPage(), () async {
      expect(tester.takeException(), isNull);
      expect(find.text('Net this month'), findsOneWidget);
    });
  });

  testWidgets('recurring page shows the coming bills on a small phone', (tester) async {
    await pumpSmall(tester, const SubscriptionsPage(), () async {
      expect(tester.takeException(), isNull);
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('Gym'), findsWidgets);
    });
  });

  for (final target in [null, '150000']) {
    testWidgets('day-by-day pace card with ${target == null ? 'no budget' : 'a budget'} fits large text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSmall(tester, const WalletPage(), target: target, () async {
        final list = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('No-spend days'), 200, scrollable: list);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Day by day'), findsOneWidget);
        if (target == null) {
          expect(find.text('Set a monthly budget'), findsOneWidget);
        } else {
          expect(find.text('Safe to spend today'), findsOneWidget);
          expect(find.textContaining('Projected by'), findsOneWidget);
        }
      });
    });
  }
}
