import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:hub/apps/ai/ai_chat_page.dart';
import 'package:hub/apps/ai/ai_service.dart';
import 'package:hub/apps/ai/chat_memory.dart';
import 'package:hub/core/app_info.dart';
import 'package:hub/core/automations.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';
import 'package:hub/shell/search_page.dart';

import 'ai_test.dart' show anthropicOk, json, settle, textOf;
import 'widget_test.dart' show pumpWithDb;

void main() {
  test('the version under About matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $appVersion+$appBuild');
  });

  group('chat memory', () {
    test('keeps the last 200 turns and survives bad data', () {
      final turns = [for (var i = 0; i < 260; i++) SavedTurn(i.isEven ? 'user' : 'assistant', 'm$i')];
      final back = ChatMemory.decode(ChatMemory.encode(turns));
      expect(back.length, ChatMemory.limit);
      expect(back.first.text, 'm60');
      expect(back.last.text, 'm259');
      expect(ChatMemory.decode('not json'), isEmpty);
      expect(ChatMemory.decode('[{"r":1},{"r":"user","t":"ok"}]').single.text, 'ok');
    });

    test('raw agent JSON and errors round-trip', () {
      const t = SavedTurn('assistant', 'Got it.', raw: '{"reply":"Got it."}', error: true);
      final back = ChatMemory.decode(ChatMemory.encode([t])).single;
      expect(back.raw, t.raw);
      expect(back.error, isTrue);
    });
  });

  test('Hub context sums up today', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 10, 30, 9);
    await db.addTodo('Hand in report', due: DateTime(2026, 10, 30));
    await db.addTodo('Old thing', due: DateTime(2026, 10, 20));
    await db.addEntry(
      EntriesCompanion.insert(amountCents: 1250, kind: EntryKind.expense, category: 'Eating out', date: now),
    );
    await db.saveNote(title: 'Ideas', body: 'Paint the hallway');
    final text = await hubContext(db, now: now);
    expect(text, contains('Tasks due today: Hand in report.'));
    expect(text, contains('Overdue tasks: Old thing.'));
    expect(text, contains('Spent this week (since Monday): €12.50'));
    expect(text, contains('Eating out €12.50'));
    expect(text, contains('Ideas: Paint the hallway'));
    await db.close();
  });

  test('recent searches put the newest first without repeats', () {
    var l = <String>[];
    for (final q in ['milk', 'rent', 'Milk', ' x ', 'gym']) {
      l = RecentSearches.add(l, q);
    }
    expect(l, ['gym', 'Milk', 'rent']);
    for (var i = 0; i < 20; i++) {
      l = RecentSearches.add(l, 'q$i');
    }
    expect(l.length, RecentSearches.limit);
  });

  test('end of day summary is off by default and plans today and the next days', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 10, 30, 18);
    expect((await planAutomations(db, now: now)).where((p) => p.id >= 560000 && p.id < 570000), isEmpty);
    await db.writeSetting('auto.evening', '21:30');
    final id = await db.addTodo('Done today');
    await db.setTodoDone(id, true);
    await (db.update(db.todos)..where((t) => t.id.equals(id))).write(TodosCompanion(completedAt: Value(now)));
    await db.addTodo('Due tomorrow', due: DateTime(2026, 10, 31));
    await db.addEntry(
      EntriesCompanion.insert(amountCents: 800, kind: EntryKind.expense, category: 'Groceries', date: now),
    );
    final plan = (await planAutomations(db, now: now)).where((p) => p.id >= 560000 && p.id < 570000).toList();
    expect(plan.length, 7);
    expect(plan.first.at, DateTime(2026, 10, 30, 21, 30));
    expect(plan.first.title, 'Your day in short');
    expect(plan.first.body, contains('1 task done'));
    expect(plan.first.body, contains('spent €8'));
    expect(plan.first.body, contains('1 task due tomorrow'));
    expect(plan[1].body, isNot(contains('spent')));
    await db.close();
  });

  testWidgets('chat keeps its history, and New chat empties it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    AiSetup.store = MemoryAiKeyStore()..values['ai-key-anthropic'] = 'k';
    String? system;
    AiSetup.newClient = () => MockClient((r) async {
      system = textOf((jsonDecode(r.body) as Map)['system']);
      return json(anthropicOk('Here is your plan.'));
    });
    late AppSettings settings;
    await pumpWithDb(
      tester,
      (db, s) {
        settings = s;
        s.setRaw(AiSettings.billing, 'api');
        s.setRaw(ChatMemory.contextKey, 'on');
        return HubApp(db: db, settings: s);
      },
      (db) async {
        await tester.runAsync(() => db.addTodo('Water the plants', due: DateTime.now()));
        navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage()));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Plan my day'));
        await settle(tester);
        expect(find.text('Here is your plan.'), findsOneWidget);
        expect(system, contains('Water the plants'));
        expect(ChatMemory(settings).load(false).map((t) => t.text), ['Plan my day', 'Here is your plan.']);

        // Leave and come back: still there.
        navigatorKey.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 400));
        navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage()));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Here is your plan.'), findsOneWidget);

        await tester.tap(find.byTooltip('New chat'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SelectableText), findsNothing);
        expect(ChatMemory(settings).load(false), isEmpty);
        // The old chat waits under Recent, and opens again from there.
        expect(find.text('Recent'), findsOneWidget);
        expect(ChatMemory(settings).list(agent: false).single.name, 'Plan my day');
        await tester.tap(find.text('Here is your plan.'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SelectableText), findsNWidgets(2));
        expect(ChatMemory(settings).load(false).length, 2);
      },
    );
  });

  testWidgets('search finds shopping, habits, recurring and saved items, and remembers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    late AppSettings settings;
    await pumpWithDb(
      tester,
      (db, s) {
        settings = s;
        return Hub(
          db: db,
          settings: s,
          child: const MaterialApp(home: SearchPage()),
        );
      },
      (db) async {
        await tester.runAsync(() async {
          await db.addShoppingItem('Oat milk', quantity: '2');
          await db.saveHabit(HabitsCompanion.insert(name: 'Milk the goats', color: 0xFF00AA00));
          await db.saveSubscription(
            SubscriptionsCompanion.insert(
              name: 'Milkman',
              amountCents: 900,
              kind: EntryKind.subscription,
              category: 'Groceries',
              nextDate: DateTime.now().add(const Duration(days: 3)),
            ),
          );
          final space = (await db.watchSpaces().first).first;
          await db.saveSpaceItem(
            SpaceItemsCompanion.insert(spaceId: space.id, kind: 'link', title: const Value('Milk prices')),
          );
        });
        await tester.enterText(find.byType(TextField), 'milk');
        await tester.pump(const Duration(milliseconds: 250));
        await settle(tester);
        for (final t in ['Shopping', 'Habits', 'Recurring', 'Saved in spaces']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('Oat milk (2)'), findsOneWidget);
        expect(find.text('Milk the goats'), findsOneWidget);
        expect(find.text('Milkman'), findsOneWidget);
        expect(find.text('Milk prices'), findsOneWidget);

        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(RecentSearches.read(settings), ['milk']);
        await tester.enterText(find.byType(TextField), '');
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Recent'), findsOneWidget);
      },
    );
  });
}
