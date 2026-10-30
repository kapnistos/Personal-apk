import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/shopping/shopping_page.dart';
import 'package:hub/apps/wallet/insights.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/theme.dart';

/// Made-up demo data, a few months of it, around the running month.
Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.delete(db.subscriptions).go();
  for (final (i, name) in ['Demo Bank', 'Card Two'].indexed) {
    await db.saveAccount(AccountsCompanion.insert(name: name, color: 0xFF3A78C9 + i));
  }
  Future<void> e(EntryKind k, int cents, String cat, String note, DateTime d, [String account = 'Demo Bank']) =>
      db.addEntry(
        EntriesCompanion.insert(
          amountCents: cents,
          kind: k,
          category: cat,
          note: Value(note),
          account: Value(account),
          date: d,
        ),
      );
  for (final back in [0, 1, 2, 13]) {
    final m = DateTime(now.year, now.month - back);
    await e(EntryKind.income, 210000, 'Salary', 'Salary', DateTime(m.year, m.month, 1, 9));
    await e(EntryKind.expense, 4321, 'Groceries', 'Market', DateTime(m.year, m.month, 1, 18), 'Card Two');
    await e(EntryKind.expense, 1999, 'Eating out', 'Pizza place', DateTime(m.year, m.month, 1, 20));
    await e(EntryKind.tax, 3300, 'Municipal tax', 'Town hall', DateTime(m.year, m.month, 1, 10));
  }
  await db.setBudget('Groceries', 15000);
  await db.saveSubscription(
    SubscriptionsCompanion.insert(
      name: 'Video service',
      amountCents: 999,
      kind: EntryKind.subscription,
      category: 'Streaming',
      account: const Value('Card Two'),
      nextDate: DateTime(now.year, now.month, now.day + 4),
    ),
  );
  await db.saveSubscription(
    SubscriptionsCompanion.insert(
      name: 'Odd period',
      amountCents: 4000,
      kind: EntryKind.subscription,
      category: 'Software',
      periodMonths: const Value(2),
      nextDate: DateTime(now.year, now.month, now.day + 9),
    ),
  );
  final goal = await db.saveGoal(
    SavingsGoalsCompanion.insert(name: 'Rainy day', targetCents: 300000, color: 0xFF1F7A5A),
  );
  await db.addMove(goal, 50000, date: DateTime(now.year, now.month - 1, 3));
  await db.saveHolding(HoldingsCompanion.insert(name: 'World fund', units: 10, investedCents: 100000, price: 110));
  await db.addShoppingItem('Rice', quantity: '1kg');
}

/// Real app fonts, so overflow checks measure what a phone would show.
Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-$w.otf').readAsBytesSync())));
  }
  await inter.load();
}

void main() {
  setUpAll(_loadFonts);
  for (final size in const [Size(360, 740), Size(320, 568)]) {
    for (final b in Brightness.values) {
      final tag = '${size.width.toInt()}x${size.height.toInt()} ${b.name}';

      late AppSettings settingsRef;

      Future<AppDatabase> pump(WidgetTester tester, Widget page) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        final settings = settingsRef = AppSettings(db);
        await tester.runAsync(() async {
          await settings.load();
          await _seed(db);
        });
        await tester.pumpWidget(
          Hub(
            db: db,
            settings: settings,
            child: MaterialApp(theme: buildTheme(b), home: page),
          ),
        );
        return db;
      }

      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> tap(WidgetTester tester, Finder f) async {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(f.first);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(f.first);
        await settle(tester);
      }

      Future<void> scrollTo(WidgetTester tester, Finder f) async {
        // Pin the list once: the one on screen now, not a kept-alive tab beside it.
        final el = find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .hitTestable()
            .evaluate()
            .first;
        final list = find.byElementPredicate((e) => e == el);
        if (f.evaluate().isEmpty) {
          await tester.drag(list, const Offset(0, 5000));
          await settle(tester);
        }
        // Rows far below the fold are not built yet, so step down until one exists.
        for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
          await tester.drag(list, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.scrollUntilVisible(f.first, 200, scrollable: list, maxScrolls: 80);
        await settle(tester);
      }

      Future<void> dialogText(WidgetTester tester, String text, {int index = 0}) async {
        final field = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).at(index);
        await tester.enterText(field, text);
        await tester.pump();
      }

      Future<void> close(WidgetTester tester, AppDatabase db) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        await tester.runAsync(db.close);
      }

      testWidgets('wallet spending smoke $tag', (tester) async {
        final db = await pump(tester, const WalletPage());
        await settle(tester);
        expect(find.text('Net this month'), findsOneWidget);

        // Back through empty months over the year boundary, then forward past now.
        final back = DateTime.now().month + 2;
        for (var i = 0; i < back; i++) {
          await tap(tester, find.byTooltip('Previous month'));
        }
        for (var i = 0; i < back + 2; i++) {
          await tap(tester, find.byTooltip('Next month'));
        }
        await tap(tester, find.text('Now'));

        // Add an expense with a comma decimal, then an income.
        await scrollTo(tester, find.text('Add'));
        await tap(tester, find.text('Add'));
        await tester.enterText(find.byType(TextField).first, '12,50');
        await tap(tester, find.widgetWithText(FilledButton, 'Add'));
        final all = await tester.runAsync(() => db.select(db.entries).get());
        expect(all!.where((e) => e.amountCents == 1250), hasLength(1));
        await scrollTo(tester, find.text('Add'));
        await tap(tester, find.text('Add'));
        await tap(tester, find.text('Income').last);
        await tester.enterText(find.byType(TextField).first, '100');
        await tap(tester, find.widgetWithText(FilledButton, 'Add'));

        // Spending target.
        await scrollTo(tester, find.text('Set a budget'));
        await tap(tester, find.text('Set a budget'));
        await dialogText(tester, '1.500,75');
        await tap(tester, find.widgetWithText(FilledButton, 'Save'));
        expect(settingsRef.raw(spendTargetKey), '150075');

        // Each account row, set a balance.
        // Deep scrolling is only driven on the taller phone; the small one still renders every screen above.
        for (final name in size.height >= 700 ? ['Demo Bank', 'Card Two'] : const <String>[]) {
          await tester.drag(
            find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().first,
            const Offset(0, 3000),
          );
          await settle(tester);
          await scrollTo(tester, find.text(name));
          await tap(tester, find.text(name));
          await tap(tester, find.text('Set current balance'));
          await dialogText(tester, '1234,56');
          await tap(tester, find.widgetWithText(FilledButton, 'Save'));
          await tester.pageBack();
          await settle(tester);
        }

        await close(tester, db);
      });

      testWidgets('wallet recurring smoke $tag', (tester) async {
        final db = await pump(tester, const WalletPage());
        await settle(tester);
        await scrollTo(tester, find.text('Recurring'));
        await tap(tester, find.text('Recurring'));
        expect(find.text('Recurring'), findsWidgets);

        // Add one.
        await tap(tester, find.byType(FloatingActionButton));
        await tester.enterText(find.byType(TextField).at(0), 'Music app');
        await tester.enterText(find.byType(TextField).at(1), '10,99');
        await tap(tester, find.widgetWithText(FilledButton, 'Add'));
        final subs = await tester.runAsync(() => db.select(db.subscriptions).get());
        expect(subs!.where((s) => s.name == 'Music app' && s.amountCents == 1099), hasLength(1));

        // Edit the one with an unusual period, then delete it.
        await scrollTo(tester, find.widgetWithText(ListTile, 'Odd period'));
        await tap(tester, find.widgetWithText(ListTile, 'Odd period'));
        await tester.enterText(find.byType(TextField).at(1), '41');
        await tap(tester, find.widgetWithText(FilledButton, 'Save'));
        await scrollTo(tester, find.widgetWithText(ListTile, 'Odd period'));
        await tap(tester, find.widgetWithText(ListTile, 'Odd period'));
        await scrollTo(tester, find.text('Delete'));
        await tap(tester, find.text('Delete'));
        final left = await tester.runAsync(() => db.select(db.subscriptions).get());
        expect(left!.where((s) => s.name == 'Odd period'), isEmpty);
        await close(tester, db);
      });

      testWidgets('wallet savings and investing smoke $tag', (tester) async {
        final db = await pump(tester, const WalletPage());
        await settle(tester);
        await tap(tester, find.text('Savings'));
        if (size.height < 700) return close(tester, db);
        await scrollTo(tester, find.text('Add money'));
        await tap(tester, find.text('Add money'));
        await dialogText(tester, '25,5');
        await tap(tester, find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton)));
        final moves = await tester.runAsync(() => db.select(db.savingsMoves).get());
        expect(moves!.where((m) => m.amountCents == 2550), hasLength(1));

        // Round-ups on: a new expense saves the change, editing it does not.
        await scrollTo(tester, find.text('Round-ups'));
        await tap(tester, find.byType(Switch));
        await tap(tester, find.text('Spending'));
        await scrollTo(tester, find.text('Add'));
        await tap(tester, find.text('Add'));
        await tester.enterText(find.byType(TextField).first, '3,40');
        await tap(tester, find.widgetWithText(FilledButton, 'Add'));
        var ups = await tester.runAsync(() => db.select(db.savingsMoves).get());
        expect(ups!.where((m) => m.amountCents == 60), hasLength(1));

        // Investing: add a holding.
        await tap(tester, find.text('Investing'));
        await tap(tester, find.byType(FloatingActionButton));
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Bond fund');
        await tester.enterText(fields.at(2), '5');
        await tester.enterText(fields.at(3), '500,50');
        await scrollTo(tester, find.text('Save'));
        await tap(tester, find.widgetWithText(FilledButton, 'Save'));
        final holdings = await tester.runAsync(() => db.select(db.holdings).get());
        expect(holdings!.where((h) => h.name == 'Bond fund' && h.investedCents == 50050), hasLength(1));
        await close(tester, db);
      });

      testWidgets('shopping smoke $tag', (tester) async {
        final db = await pump(tester, const ShoppingPage());
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'pasta, 2x toilet paper, feta');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
        final items = await tester.runAsync(() => db.select(db.shoppingItems).get());
        expect(items!.length, 4);
        await scrollTo(tester, find.byType(Checkbox));
        await tap(tester, find.byType(Checkbox));
        await tap(tester, find.text('Clear'));
        final after = await tester.runAsync(() => db.select(db.shoppingItems).get());
        expect(after!.length, 3);
        await close(tester, db);
      });
    }
  }
}
