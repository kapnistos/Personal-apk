import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/ai/ai_chat_page.dart';
import 'package:hub/apps/ai/ai_service.dart';
import 'package:hub/apps/ai/ask_agent.dart';
import 'package:hub/apps/ai/hub_agent.dart';
import 'package:hub/apps/ai/hub_tools.dart';
import 'package:hub/apps/wallet/insights.dart' show spendTargetKey;
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';

import 'ai_test.dart' show anthropicOk, json, openAiOk;
import 'ai_tools_test.dart' show now, pumpSeeded, seedHub, settle;

/// What the agent can change, one case per write tool: the arguments the model sends, and a look at the
/// data that must change on Add and come back on Undo.
class _Case {
  const _Case(this.tool, this.args, this.state, this.after, {this.verb = 'Add'});
  final String tool;
  final Future<Map<String, dynamic>> Function(AppDatabase db) args;
  final Future<Object?> Function(AppDatabase db, AppSettings s) state;
  final Object? after;
  final String verb;
}

Future<int> _task(AppDatabase db, String title) async =>
    (await db.select(db.todos).get()).firstWhere((t) => t.title == title).id;
Future<int> _event(AppDatabase db, String title) async =>
    (await db.select(db.events).get()).firstWhere((e) => e.title == title).id;

/// The extra things the agent cases need on top of the seed: a savings goal and a habit.
Future<void> _seedMore(AppDatabase db) async {
  await db.saveGoal(SavingsGoalsCompanion.insert(name: 'Holiday', targetCents: 150000, color: 0xFF2D8C9E));
  await db.saveHabit(HabitsCompanion.insert(name: 'Read', color: 0xFF7A5BC0));
}

final _cases = <_Case>[
  _Case(
    'propose_edit_task',
    (db) async => {'id': await _task(db, 'Hand in report'), 'due': '2026-11-06', 'important': false},
    (db, _) async {
      final t = (await db.select(db.todos).get()).firstWhere((t) => t.title == 'Hand in report');
      return (t.due, t.important);
    },
    (DateTime(2026, 11, 6), false),
    verb: 'Save',
  ),
  _Case(
    'propose_complete_task',
    (db) async => {'id': await _task(db, 'Buy birthday gift for mum')},
    (db, _) async => (await db.select(db.todos).get()).firstWhere((t) => t.title == 'Buy birthday gift for mum').done,
    true,
    verb: 'Done',
  ),
  _Case(
    'propose_delete_task',
    (db) async => {'id': await _task(db, 'Buy birthday gift for mum')},
    (db, _) async => (await db.select(db.todos).get()).map((t) => t.title).toSet(),
    {'Hand in report'},
    verb: 'Delete',
  ),
  _Case('propose_event', (db) async => {'title': 'Team lunch', 'start': '2026-11-03T12:30', 'calendar': 'work'}, (
    db,
    _,
  ) async {
    final cals = {for (final c in await db.select(db.calendars).get()) c.id: c.name};
    return [
      for (final e in await db.select(db.events).get())
        if (e.title == 'Team lunch') (cals[e.calendarId], e.start, e.end),
    ];
  }, [('Work', DateTime(2026, 11, 3, 12, 30), DateTime(2026, 11, 3, 13, 30))]),
  _Case(
    'propose_edit_event',
    (db) async => {'id': await _event(db, 'Gym'), 'start': '2026-09-01T19:30', 'location': 'Basic-Fit'},
    (db, _) async {
      final e = (await db.select(db.events).get()).firstWhere((e) => e.title == 'Gym');
      return (e.start, e.end, e.location, e.repeat);
    },
    (DateTime(2026, 9, 1, 19, 30), DateTime(2026, 9, 1, 20, 30), 'Basic-Fit', 'weekly'),
    verb: 'Save',
  ),
  _Case(
    'propose_delete_event',
    (db) async => {'id': await _event(db, 'Gym')},
    (db, _) async => (await db.select(db.events).get()).map((e) => e.title).toSet(),
    {'Open day', 'Exam week'},
    verb: 'Delete',
  ),
  _Case(
    'propose_edit_note',
    (db) async => {'id': (await db.select(db.notes).get()).single.id, 'append': 'Next service due March 2027'},
    (db, _) async => (await db.select(db.notes).get()).single.body,
    'Model Remeha Tzerra, serviced in March\nNext service due March 2027',
    verb: 'Save',
  ),
  _Case(
    'propose_recurring',
    (db) async => {'name': 'Spotify', 'amount': 10.99, 'category': 'Streaming', 'next_date': '2026-11-12'},
    (db, _) async => [
      for (final s in await db.select(db.subscriptions).get())
        if (s.name == 'Spotify') (s.amountCents, s.nextDate),
    ],
    [(1099, DateTime(2026, 11, 12))],
  ),
  _Case(
    'propose_edit_recurring',
    (db) async => {
      'id': (await db.select(db.subscriptions).get()).firstWhere((s) => s.name == 'Netflix').id,
      'amount': 15.99,
      'next_date': '2026-11-05',
    },
    (db, _) async {
      final s = (await db.select(db.subscriptions).get()).firstWhere((s) => s.name == 'Netflix');
      return (s.amountCents, s.nextDate, s.active);
    },
    (1599, DateTime(2026, 11, 5), true),
    verb: 'Save',
  ),
  _Case(
    'propose_savings_deposit',
    (db) async => {'goal': 'holiday', 'amount': 50, 'note': 'Payday'},
    (db, _) async => [for (final m in await db.select(db.savingsMoves).get()) (m.amountCents, m.note)],
    [(5000, 'Payday')],
  ),
  _Case(
    'propose_budget_target',
    (db) async => {'amount': 1200},
    (db, s) async => (s.raw(spendTargetKey) ?? '', (await db.readSettings())[spendTargetKey] ?? ''),
    ('120000', '120000'),
    verb: 'Save',
  ),
  _Case(
    'propose_shopping',
    (db) async => {'name': 'eggs', 'quantity': '12'},
    (db, _) async => {for (final i in await db.select(db.shoppingItems).get()) i.name},
    {'oat milk', 'eggs'},
  ),
  _Case(
    'propose_work_hours',
    (db) async => {'date': '2026-10-29', 'start': '09:00', 'end': '17:30', 'break_minutes': 30},
    (db, _) async => [for (final w in await db.select(db.workDays).get()) (w.day, w.status, w.hours, w.note)],
    [('2026-10-29', 'work', 8.0, '[09:00-17:30 -30m]')],
    verb: 'Log',
  ),
  _Case('propose_space_date', (db) async => {'space': 'University', 'title': 'Statistics exam', 'date': '2026-11-20'}, (
    db,
    _,
  ) async {
    final cals = {for (final c in await db.select(db.calendars).get()) c.id: c.name};
    return [
      for (final e in await db.select(db.events).get())
        if (e.title == 'Statistics exam') (cals[e.calendarId], e.allDay, e.start, e.end, e.remindMinutes),
    ];
  }, [('Study', true, DateTime(2026, 11, 20), DateTime(2026, 11, 21), 900)]),
  _Case(
    'propose_habit_done',
    (db) async => {'name': 'read', 'date': '2026-10-30'},
    (db, _) async => [for (final c in await db.select(db.habitChecks).get()) c.day],
    ['2026-10-30'],
    verb: 'Done',
  ),
];

/// A provider that asks for one tool, then answers in words; [bodies] keeps every request.
http.Client _oneCall(bool openAi, String tool, Map<String, dynamic> args, List<Map> bodies) => MockClient((r) async {
  bodies.add(jsonDecode(r.body) as Map);
  if (bodies.length == 1) {
    return json(
      openAi
          ? {
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'w1',
                        'type': 'function',
                        'function': {'name': tool, 'arguments': jsonEncode(args)},
                      },
                    ],
                  },
                },
              ],
              'usage': {'prompt_tokens': 800, 'completion_tokens': 20},
            }
          : {
              'content': [
                {'type': 'tool_use', 'id': 'w1', 'name': tool, 'input': args},
              ],
              'stop_reason': 'tool_use',
              'usage': {'input_tokens': 800, 'output_tokens': 20},
            },
    );
  }
  return json(openAi ? openAiOk('Here it is to add.') : anthropicOk('Here it is to add.'));
});

/// What the app sent back to the model as the tool's result.
String _toolResult(bool openAi, Map body) {
  final msgs = body['messages'] as List;
  if (openAi) return msgs.firstWhere((m) => m['role'] == 'tool')['content'] as String;
  final block = (msgs.last['content'] as List).single as Map;
  expect(block['type'], 'tool_result');
  return block['content'] as String;
}

Future<AiSetup> _setup(AppSettings settings, bool openAi, http.Client client) async {
  await settings.setRaw(AiSettings.billing, 'api');
  if (openAi) {
    await settings.setRaw(AiSettings.model, 'openrouter');
    await settings.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
  }
  final keys = MemoryAiKeyStore()..values[openAi ? 'ai-key-openrouter' : 'ai-key-anthropic'] = 'k';
  return AiSetup(settings, keys: keys, httpClient: client);
}

void main() {
  setUpAll(() => AiClient.retryDelays = const [Duration.zero, Duration.zero]);

  for (final openAi in [true, false]) {
    group('${openAi ? 'OpenAI' : 'Anthropic'} tool format: proposal, Add, Undo', () {
      late AppDatabase db;
      late AppSettings settings;
      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        await seedHub(db);
        await _seedMore(db);
        settings = AppSettings(db);
        await settings.load();
      });
      tearDown(() => db.close());

      for (final c in _cases) {
        test(c.tool, () async {
          final args = await c.args(db);
          final bodies = <Map>[];
          final ai = await _setup(settings, openAi, _oneCall(openAi, c.tool, args, bodies));
          final tools = HubTools(db, clock: () => now);
          final before = await c.state(db, settings);
          final reply = await ai.ask(
            const [AiMessage('user', 'Please do it')],
            system: agentToolPrompt(now),
            tools: tools.tools,
            runTool: tools.run,
          );
          // The tool is offered in this provider's shape, and its result reaches the model.
          final offered = bodies.first['tools'] as List;
          expect(offered.map((t) => openAi ? t['function']['name'] : t['name']), contains(c.tool));
          final result = jsonDecode(_toolResult(openAi, bodies.last)) as Map;
          expect(result['proposed'], isTrue, reason: '$result');
          expect(reply.toolsUsed, [c.tool]);

          // A card, and nothing saved yet.
          final card = tools.proposals.single;
          expect(card.verb, c.verb);
          expect(card.destructive, c.verb == 'Delete');
          expect(card.summaryIn('EUR'), isNotEmpty);
          expect(await c.state(db, settings), before, reason: 'nothing changes before Add');

          // Add, then Undo.
          final undo = await card.apply(db, now: now, settings: settings);
          expect(await c.state(db, settings), c.after);
          await undo();
          expect(await c.state(db, settings), before, reason: 'Undo puts it back');

          // The card survives being saved with the chat and read back.
          final again = AgentAction.fromJson(jsonDecode(jsonEncode(card.toJson())));
          expect(again?.summaryIn('EUR'), card.summaryIn('EUR'));
        });
      }
    });
  }

  group('checks before a card is shown', () {
    late AppDatabase db;
    late HubTools tools;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await seedHub(db);
      await _seedMore(db);
      tools = HubTools(db, clock: () => now);
    });
    tearDown(() => db.close());

    Future<Map> call(String name, Map<String, dynamic> args) async => jsonDecode(await tools.run(name, args)) as Map;

    test('unknown ids, read-only calendars and missing names are refused with a reason', () async {
      expect((await call('propose_edit_task', {'id': 999, 'due': '2026-11-01'}))['error'], contains('get_tasks'));
      final open = await _event(db, 'Open day');
      final imported = await call('propose_edit_event', {'id': open, 'start': '2026-11-08'});
      expect(imported['proposed'], isFalse);
      expect(imported['error'], contains('read-only'));
      expect((await call('propose_delete_event', {'id': open}))['proposed'], isFalse);
      expect((await call('propose_savings_deposit', {'goal': 'Car', 'amount': 10}))['proposed'], isFalse);
      expect((await call('propose_habit_done', {'name': 'Swim'}))['proposed'], isFalse);
      expect(
        (await call('propose_space_date', {'space': 'Moon', 'title': 'x', 'date': '2026-11-01'}))['proposed'],
        isFalse,
      );
      expect(
        (await call('propose_edit_task', {'id': await _task(db, 'Hand in report')}))['proposed'],
        isFalse,
        reason: 'an edit that changes nothing',
      );
      expect(tools.proposals, isEmpty);
    });

    test('cards say what changes and what it was', () async {
      final gym = await _event(db, 'Gym');
      final moved = await call('propose_edit_event', {'id': gym, 'start': '2026-11-03T19:30'});
      expect(moved['card'], contains('Reschedule event: Gym'));
      final a = tools.proposals.last;
      expect(a.detailIn('EUR'), allOf(contains('Tue 3 Nov, 19:30'), contains('was Tue 1 Sep, 18:00, repeats weekly')));

      await call('propose_delete_event', {'id': gym});
      final del = tools.proposals.last;
      expect((del.label, del.verb, del.destructive), ('Delete event', 'Delete', true));
      expect(del.detailIn('EUR'), contains('every one goes'));

      final report = await _task(db, 'Hand in report');
      await call('propose_edit_task', {'id': report, 'due': '2026-11-06'});
      expect(tools.proposals.last.label, 'Reschedule task');
      expect(tools.proposals.last.detailIn('EUR'), 'Due Fri 6 Nov · was due Wed 4 Nov');

      final netflix = (await db.select(db.subscriptions).get()).firstWhere((s) => s.name == 'Netflix').id;
      await call('propose_edit_recurring', {'id': netflix, 'amount': 15.99});
      expect(tools.proposals.last.detailIn('EUR'), '€15.99 · was €13.99 monthly');

      await call('propose_work_hours', {'date': '2026-10-29', 'hours': 6});
      expect(tools.proposals.last.summaryIn('EUR'), 'Thu 29 Oct: Worked, 6 h');

      await call('propose_event', {'title': 'Lecture', 'start': '2026-11-02T10:00', 'calendar': 'University'});
      expect(tools.proposals.last.fields['calendar'], 'Study', reason: 'a space name finds its calendar');
    });

    test('the prompt has the time, zone, currency, name, the guide and phone formatting', () {
      final p = agentToolPrompt(now, currency: 'USD', name: 'Georgios');
      expect(p, contains('Friday 30 October 2026, 09:00'));
      expect(p, contains('time zone'));
      expect(p, contains('USD'));
      expect(p, contains('Georgios'));
      expect(p, contains('Job also has a work log'));
      expect(p, contains('read on a phone'));
      final s = agentSystemPrompt(now, name: 'Georgios');
      expect(s, allOf(contains('"type": "work_day"'), contains('"type": "delete_event"'), contains('Georgios')));
      final parsed = parseAgentReply(
        '{"reply":"ok","actions":[{"type":"delete_task","id":3},{"type":"habit","name":"Read"},'
        '{"type":"budget_target","amount":900},{"type":"work_day","date":"2026-10-29","status":"sick"}]}',
      );
      expect(parsed.actions.map((a) => a.verb), ['Delete', 'Done', 'Save', 'Log']);
    });
  });

  group('screens', () {
    late http.Client Function() oldClient;
    late AiKeyStore oldStore;
    setUp(() {
      oldClient = AiSetup.newClient;
      oldStore = AiSetup.store;
    });
    tearDown(() {
      AiSetup.newClient = oldClient;
      AiSetup.store = oldStore;
    });

    testWidgets('Add all, Undo, and a delete that needs its own tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'k';
      var calls = 0;
      int? gymId;
      AiSetup.newClient = () => MockClient((r) async {
        calls++;
        if (calls == 1) {
          Map call(String id, String name, Map args) => {
            'id': id,
            'type': 'function',
            'function': {'name': name, 'arguments': jsonEncode(args)},
          };
          return json({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    call('a', 'propose_shopping', {'name': 'eggs'}),
                    call('b', 'propose_shopping', {'name': 'bread'}),
                    call('c', 'propose_delete_event', {'id': gymId}),
                  ],
                },
              },
            ],
          });
        }
        return json(openAiOk('Eggs and bread for the list, and the gym to delete.'));
      });
      await pumpSeeded(
        tester,
        (s) {
          s.setRaw(AiSettings.billing, 'api');
          s.setRaw(AiSettings.model, 'openrouter');
          s.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
        },
        (db, settings) async {
          gymId = await tester.runAsync(() => _event(db, 'Gym'));
          navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage(agent: true)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField).last, 'eggs and bread, and delete the gym');
          await tester.tap(find.byTooltip('Send'));
          await settle(tester);
          expect(find.text('Delete event'), findsOneWidget);
          expect(find.text('Add all 2'), findsNothing, reason: 'a delete is waiting, so it says "the other"');
          await tester.ensureVisible(find.text('Add the other 2'));
          await tester.tap(find.text('Add the other 2'));
          await settle(tester);
          Future<Set<String>> shopping() async => {
            for (final i in (await tester.runAsync(() => db.select(db.shoppingItems).get()))!) i.name,
          };
          expect(await shopping(), {'oat milk', 'eggs', 'bread'});
          expect(find.text('Added'), findsNWidgets(2));
          expect(find.text('All 2 done'), findsOneWidget);
          expect(
            (await tester.runAsync(() => db.select(db.events).get()))!.where((e) => e.title == 'Gym'),
            hasLength(1),
            reason: 'Add all leaves the delete alone',
          );

          // Undo from the snack bar takes both back, and the cards can be added again.
          await tester.tap(find.text('Undo').last);
          await settle(tester);
          expect(await shopping(), {'oat milk'});
          expect(find.text('Add the other 2'), findsOneWidget);

          // The delete, on its own.
          await tester.ensureVisible(find.text('Delete'));
          await tester.tap(find.text('Delete'));
          await settle(tester);
          expect((await tester.runAsync(() => db.select(db.events).get()))!.where((e) => e.title == 'Gym'), isEmpty);
          expect(find.text('Deleted'), findsOneWidget);
          // And its Undo on the card.
          final cardUndo = find.descendant(of: find.byKey(const ValueKey('ai-card-2')), matching: find.text('Undo'));
          await tester.ensureVisible(cardUndo);
          await tester.tap(cardUndo);
          await settle(tester);
          expect(
            (await tester.runAsync(() => db.select(db.events).get()))!.where((e) => e.title == 'Gym'),
            hasLength(1),
          );
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });

    testWidgets('an app hands the agent a question with openAgentWith', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'k';
      final asked = <String>[];
      AiSetup.newClient = () => MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        asked.add(((body['messages'] as List).last as Map)['content'] as String);
        return json(openAiOk('You spent **€42.50** so far, all on groceries.'));
      });
      await pumpSeeded(
        tester,
        (s) {
          s.setRaw(AiSettings.billing, 'api');
          s.setRaw(AiSettings.model, 'openrouter');
          s.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
        },
        (db, settings) async {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  actions: const [AskAgentButton(label: 'Explain my month', prompt: AgentPrompts.explainMonth)],
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.byTooltip('Explain my month'));
          await tester.pump(const Duration(milliseconds: 400));
          await settle(tester);
          expect(find.byType(AiChatPage), findsOneWidget);
          expect(asked.single, AgentPrompts.explainMonth);
          expect(find.text('You spent €42.50 so far, all on groceries.'), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });
  });

  test('a task edit can clear the due date and Undo brings it back', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedHub(db);
    final id = await _task(db, 'Hand in report');
    final a = AgentAction('edit_task', {'id': id, 'clear_due': true, 'title': 'Hand in final report'});
    expect(a.valid, isTrue);
    final undo = await a.apply(db, now: now);
    var t = (await db.todoById(id))!;
    expect((t.title, t.due), ('Hand in final report', null));
    await undo();
    t = (await db.todoById(id))!;
    expect((t.title, t.due), ('Hand in report', DateTime(2026, 11, 4)));
    // A habit already ticked stays ticked on Undo.
    final habit = await db.saveHabit(HabitsCompanion.insert(name: 'Walk', color: 0, days: const Value('1111111')));
    await db.setHabitDone(habit, DateTime(2026, 10, 30), true);
    final tick = await AgentAction('habit', {'name': 'Walk', 'date': '2026-10-30'}).apply(db, now: now);
    await tick();
    expect((await db.habitChecksSince(DateTime(2026, 10, 30))).where((c) => c.habitId == habit), hasLength(1));
    await db.close();
  });
}
