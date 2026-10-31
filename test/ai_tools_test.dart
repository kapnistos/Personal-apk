import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/ai/ai_chat_page.dart';
import 'package:hub/apps/ai/ai_service.dart';
import 'package:hub/apps/ai/ai_usage.dart';
import 'package:hub/apps/ai/chat_history_page.dart';
import 'package:hub/apps/ai/chat_memory.dart';
import 'package:hub/apps/ai/hub_agent.dart';
import 'package:hub/apps/ai/hub_tools.dart';
import 'package:hub/core/backup.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';

import 'ai_test.dart' show anthropicOk, json, openAiOk;

final now = DateTime(2026, 10, 30, 9);

/// The owner's kind of data: recurring payments, all-day events in an imported (hidden) calendar on
/// 1 and 2 Nov, a weekly event, an undated task, spending and a space.
Future<void> seedHub(AppDatabase db) async {
  for (final (name, cents, kind, cat, next, period) in [
    ('Netflix', 1399, EntryKind.subscription, 'Streaming', DateTime(2026, 11, 3), 1),
    ('Rent', 95000, EntryKind.subscription, 'Rent', DateTime(2026, 11, 1), 1),
    ('Car insurance', 36000, EntryKind.subscription, 'Insurance', DateTime(2027, 1, 15), 12),
    ('Salary', 250000, EntryKind.income, 'Salary', DateTime(2026, 11, 25), 1),
  ]) {
    await db.saveSubscription(
      SubscriptionsCompanion.insert(
        name: name,
        amountCents: cents,
        kind: kind,
        category: cat,
        nextDate: next,
        periodMonths: Value(period),
      ),
    );
  }
  final imported = await db.saveCalendar(
    CalendarsCompanion.insert(
      name: 'University timetable',
      color: 0xFF336699,
      icsUrl: const Value('https://example.org/u.ics'),
      visible: const Value(false),
    ),
  );
  await db.saveEvent(
    EventsCompanion.insert(
      calendarId: imported,
      title: 'Open day',
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 2),
      allDay: const Value(true),
    ),
  );
  await db.saveEvent(
    EventsCompanion.insert(
      calendarId: imported,
      title: 'Exam week',
      start: DateTime(2026, 11, 2),
      end: DateTime(2026, 11, 7),
      allDay: const Value(true),
    ),
  );
  final personal = (await db.select(db.calendars).get()).first.id;
  await db.saveEvent(
    EventsCompanion.insert(
      calendarId: personal,
      title: 'Gym',
      start: DateTime(2026, 9, 1, 18),
      end: DateTime(2026, 9, 1, 19),
      repeat: const Value('weekly'),
    ),
  );
  await db.addTodo('Buy birthday gift for mum');
  await db.addTodo('Hand in report', due: DateTime(2026, 11, 4), important: true);
  await db.addEntry(
    EntriesCompanion.insert(
      amountCents: 4250,
      kind: EntryKind.expense,
      category: 'Groceries',
      note: const Value('Albert Heijn'),
      date: DateTime(2026, 10, 28),
    ),
  );
  await db.saveNote(title: 'Boiler', body: 'Model Remeha Tzerra, serviced in March');
  await db.addShoppingItem('oat milk', quantity: '2');
}

/// Lets the database reads behind an answer finish: real time for the queries, then a frame.
Future<void> settle(WidgetTester tester, [int rounds = 60]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Like pumpWithDb, with the Hub data in place before the app starts.
Future<void> pumpSeeded(
  WidgetTester tester,
  void Function(AppSettings) setup,
  Future<void> Function(AppDatabase db, AppSettings settings) body,
) async {
  final db = AppDatabase(NativeDatabase.memory());
  final settings = AppSettings(db);
  await tester.runAsync(() async {
    await settings.load();
    await seedHub(db);
  });
  setup(settings);
  await tester.pumpWidget(HubApp(db: db, settings: settings));
  await tester.pump(const Duration(milliseconds: 50));
  await body(db, settings);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
  await tester.runAsync(db.close);
}

void main() {
  setUpAll(() => AiClient.retryDelays = const [Duration.zero, Duration.zero]);

  group('Hub tools read everything', () {
    late AppDatabase db;
    late HubTools tools;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await seedHub(db);
      tools = HubTools(db, clock: () => now, weather: (_) => Future.error('offline'));
    });
    tearDown(() => db.close());

    Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> args = const {}]) async =>
        jsonDecode(await tools.run(name, args)) as Map<String, dynamic>;

    test('recurring payments and subscriptions', () async {
      final r = await call('get_recurring');
      final names = [for (final i in r['items'] as List) i['name']];
      expect(names, containsAll(['Netflix', 'Rent', 'Car insurance', 'Salary']));
      expect(r['monthlyOut'], '€993.99'); // 13.99 + 950 + 360 / 12
      expect(r['monthlyIn'], '€2,500.00');
      final car = (r['items'] as List).firstWhere((i) => i['name'] == 'Car insurance');
      expect(car['every'], 'Yearly');
      expect(car['perMonth'], '€30.00');
    });

    test('the next days include all-day, imported, hidden and repeating events', () async {
      final r = await call('get_calendar');
      final events = r['events'] as List;
      final open = events.firstWhere((e) => e['title'] == 'Open day');
      expect(open['date'], '2026-11-01');
      expect(open['allDay'], isTrue);
      expect(open['calendar'], 'University timetable');
      expect(open['hiddenCalendar'], isTrue);
      final exam = events.firstWhere((e) => e['title'] == 'Exam week');
      expect((exam['date'], exam['until']), ('2026-11-02', '2026-11-06'));
      // Weekly gym on Tuesdays: 3, 10 Nov inside two weeks.
      expect(events.where((e) => e['title'] == 'Gym').map((e) => e['start']), ['2026-11-03T18:00', '2026-11-10T18:00']);
      // Any range works.
      final later = await call('get_calendar', {'from': '2026-12-01', 'to': '2026-12-31'});
      expect((later['events'] as List).where((e) => e['title'] == 'Gym').length, 5);
      expect((later['events'] as List).where((e) => e['title'] == 'Open day'), isEmpty);
    });

    test('tasks with and without dates, money, notes, shopping and search', () async {
      final t = await call('get_tasks');
      expect([
        for (final x in t['tasks'] as List) x['title'],
      ], containsAll(['Buy birthday gift for mum', 'Hand in report']));
      expect((t['tasks'] as List).firstWhere((x) => x['title'] == 'Buy birthday gift for mum')['due'], isNull);
      final tx = await call('get_transactions', {'from': '2026-10-01', 'to': '2026-10-31'});
      expect(tx['spent'], '€42.50');
      expect(((tx['entries'] as List).single as Map)['note'], 'Albert Heijn');
      final m = await call('get_money_summary');
      expect(m['byCategory'], {'Groceries': '€42.50'});
      expect((m['recurringStillToCome'] as List), isEmpty, reason: 'nothing more is due in October');
      final n = await call('search_notes', {'query': 'boiler'});
      expect(((n['notes'] as List).single as Map)['text'], contains('Remeha'));
      final s = await call('get_shopping_list');
      expect(s['toBuy'], [
        {'name': 'oat milk', 'quantity': '2'},
      ]);
      final found = await call('search_hub', {'query': 'netflix'});
      expect((found['recurring'] as List).single['name'], 'Netflix');
      final w = await call('get_weather');
      expect(w['city'], 'Amsterdam');
      expect(await tools.run('nope', {}), contains('no tool'));
    });

    test('propose tools only collect cards; nothing is written until apply', () async {
      final out = await call('propose_recurring', {'name': 'Spotify', 'amount': 10.99, 'category': 'Streaming'});
      expect(out['proposed'], isTrue);
      final todo = (await db.watchTodos().first).firstWhere((t) => t.title == 'Hand in report');
      await call('propose_complete_task', {'id': todo.id, 'title': 'Hand in report'});
      expect((await call('propose_expense', {}))['proposed'], isFalse);
      expect(tools.proposals.map((a) => a.type), ['recurring', 'complete']);
      expect((await db.watchSubscriptions().first).where((s) => s.name == 'Spotify'), isEmpty);
      expect(tools.proposals.first.summary, 'Spotify, €10.99 a month');
      for (final a in tools.proposals) {
        await a.apply(db, now: now);
      }
      final spotify = (await db.watchSubscriptions().first).singleWhere((s) => s.name == 'Spotify');
      expect((spotify.amountCents, spotify.category, spotify.kind), (1099, 'Streaming', EntryKind.subscription));
      expect((await db.todoById(todo.id))!.done, isTrue);
      // Read-only tools for Chat.
      expect(HubTools(db, writes: false).tools.where((t) => t.name.startsWith('propose_')), isEmpty);
    });

    test('the snapshot for models without tools has the recurring list and the next days', () async {
      final s = await tools.snapshot();
      expect(s, contains('Netflix'));
      expect(s, contains('Car insurance'));
      expect(s, contains('"date":"2026-11-01"'));
      expect(s, contains('Exam week'));
      expect(s, contains('Buy birthday gift for mum'));
      expect(s, contains('Albert Heijn'));
    });
  });

  group('tool calling', () {
    late AppDatabase db;
    late AppSettings settings;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await seedHub(db);
      settings = AppSettings(db);
      await settings.load();
      await settings.setRaw(AiSettings.billing, 'api');
    });
    tearDown(() => db.close());

    test('OpenAI shape: the recurring list and next days reach the model', () async {
      await settings.setRaw(AiSettings.model, 'openrouter');
      await settings.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
      await settings.setRaw(
        AiSettings.openrouterModels,
        OpenRouterModel.encodeCache(const [
          OpenRouterModel('anthropic/claude-haiku-4.5', 'Anthropic: Claude Haiku 4.5', inPrice: 1, outPrice: 5),
        ], now),
      );
      final bodies = <Map>[];
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-k',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map);
          if (bodies.length == 1) {
            return json({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'c1',
                        'type': 'function',
                        'function': {'name': 'get_recurring', 'arguments': '{}'},
                      },
                      {
                        'id': 'c2',
                        'type': 'function',
                        'function': {'name': 'get_calendar', 'arguments': '{"from":"2026-10-31","to":"2026-11-02"}'},
                      },
                    ],
                  },
                },
              ],
              'usage': {'prompt_tokens': 1000, 'completion_tokens': 30},
            });
          }
          return json(openAiOk('Rent, Netflix and car insurance. Sat 1 Nov is the open day.'));
        }),
      );
      final tools = HubTools(db, clock: () => now);
      expect(ai.canUseTools, isTrue);
      final reply = await ai.ask(
        const [AiMessage('user', 'What subscriptions do I have, and what is on the next days?')],
        system: 'sys',
        tools: tools.tools,
        runTool: tools.run,
      );
      expect(bodies.length, 2);
      expect((bodies.first['tools'] as List).map((t) => t['function']['name']), contains('get_recurring'));
      final msgs = bodies.last['messages'] as List;
      expect(msgs[1]['role'], 'user');
      expect(msgs[2]['tool_calls'], hasLength(2));
      final results = msgs.where((m) => m['role'] == 'tool').toList();
      expect(results.map((m) => m['tool_call_id']), ['c1', 'c2']);
      expect(results[0]['content'], allOf(contains('Netflix'), contains('Car insurance'), contains('Rent')));
      expect(results[1]['content'], allOf(contains('Open day'), contains('2026-11-01'), contains('Exam week')));
      expect(reply.text, contains('open day'));
      expect(reply.toolsUsed, ['get_recurring', 'get_calendar']);
      expect((reply.inputTokens, reply.outputTokens), (1020, 37));
      // Priced from the cached list: 1020 in at $1/M and 37 out at $5/M.
      expect(reply.cost, closeTo(0.001205, 1e-9));
      expect(reply.model, 'anthropic/claude-haiku-4.5');
    });

    test('Anthropic shape: tool_use and tool_result blocks', () async {
      final bodies = <Map>[];
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-anthropic'] = 'k',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map);
          if (bodies.length == 1) {
            return json({
              'content': [
                {'type': 'text', 'text': 'Let me look.'},
                {
                  'type': 'tool_use',
                  'id': 'tu1',
                  'name': 'get_calendar',
                  'input': {'from': '2026-11-01', 'to': '2026-11-02'},
                },
              ],
              'stop_reason': 'tool_use',
              'usage': {'input_tokens': 900, 'output_tokens': 20},
            });
          }
          return json(anthropicOk('Open day on Saturday, exam week from Sunday.'));
        }),
      );
      final tools = HubTools(db, clock: () => now);
      final reply = await ai.ask(const [AiMessage('user', 'Next days?')], tools: tools.tools, runTool: tools.run);
      expect((bodies.first['tools'] as List).first['input_schema'], isA<Map>());
      final msgs = bodies.last['messages'] as List;
      expect(msgs[1]['role'], 'assistant');
      expect((msgs[1]['content'] as List).last['type'], 'tool_use');
      final result = (msgs[2]['content'] as List).single as Map;
      expect((result['type'], result['tool_use_id']), ('tool_result', 'tu1'));
      expect(result['content'], contains('Open day'));
      expect(reply.text, 'Open day on Saturday, exam week from Sunday.');
      expect(reply.inputTokens, 912);
      expect(reply.cost, isNull, reason: 'direct keys show tokens only');
    });

    test('Anthropic: tools, fixed system text and the end of the conversation are marked for caching', () async {
      final bodies = <Map>[];
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-anthropic'] = 'k',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map);
          if (bodies.length == 1) {
            return json({
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'tu1',
                  'name': 'get_calendar',
                  'input': {'from': '2026-11-01', 'to': '2026-11-02'},
                },
              ],
              'stop_reason': 'tool_use',
              'usage': {'input_tokens': 900, 'output_tokens': 20},
            });
          }
          return json(anthropicOk('Done.'));
        }),
      );
      final tools = HubTools(db, clock: () => now);
      await ai.ask(
        const [AiMessage('user', 'Next days?')],
        system: 'Fixed',
        systemTail: 'Now: noon',
        tools: tools.tools,
        runTool: tools.run,
      );
      expect(bodies, hasLength(2));
      for (final b in bodies) {
        final system = b['system'] as List;
        expect(system.first, {'type': 'text', 'text': 'Fixed', 'cache_control': {'type': 'ephemeral'}});
        expect(system.last, {'type': 'text', 'text': 'Now: noon'}, reason: 'the changing part is never cached');
        final t = b['tools'] as List;
        expect(t.last['cache_control'], {'type': 'ephemeral'});
        expect(t.where((x) => x['cache_control'] != null), hasLength(1));
        final msgs = b['messages'] as List;
        final lastBlocks = msgs.last['content'] as List;
        expect(lastBlocks.last['cache_control'], {'type': 'ephemeral'});
        expect(msgs.take(msgs.length - 1).where((m) => m['content'] is List && (m['content'] as List).any((x) => x is Map && x['cache_control'] != null)), isEmpty);
      }
    });

    test('other providers get the fixed and changing system text as one message', () async {
      final bodies = <Map>[];
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-k',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map);
          return json(openAiOk('ok'));
        }),
      );
      await settings.setRaw(AiSettings.model, 'openrouter');
      await ai.ask(const [AiMessage('user', 'hi')], system: 'Fixed', systemTail: 'Now: noon');
      expect((bodies.single['messages'] as List).first, {'role': 'system', 'content': 'Fixed\n\nNow: noon'});
    });

    test('a model without tools is remembered and the next ask goes without them', () async {
      await settings.setRaw(AiSettings.model, 'openrouter');
      await settings.setRaw(AiSettings.openrouterModel, 'some/old-model');
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-openrouter'] = 'k',
        httpClient: MockClient(
          (_) async => json({
            'error': {'code': 404, 'message': 'No endpoints found that support tool use.'},
          }, 404),
        ),
      );
      final tools = HubTools(db, clock: () => now);
      await expectLater(
        ai.ask(const [AiMessage('user', 'x')], tools: tools.tools, runTool: tools.run),
        throwsA(isA<AiToolsUnsupported>()),
      );
      await ai.markNoTools();
      expect(ai.canUseTools, isFalse);
      // The OpenRouter list can say so up front.
      final list = OpenRouterModel.parseList({
        'data': [
          {
            'id': 'a/b',
            'supported_parameters': ['max_tokens'],
          },
          {
            'id': 'c/d',
            'supported_parameters': ['tools'],
          },
        ],
      });
      expect(list.map((m) => m.tools), [false, true]);
      expect(OpenRouterModel.fromJson(list.first.toJson())!.tools, isFalse);
      // Claude Code and the Claude app get the data in the prompt instead.
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      expect(AiSetup(settings).canUseTools, isFalse);
    });

    test('OpenRouter cost from the response wins over the estimate', () {
      final r = AiClient.parseOpenAi({
        'model': 'openai/gpt-5-mini',
        'choices': [
          {
            'message': {'content': 'hi'},
          },
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 2, 'cost': 0.00042},
      });
      expect((r.cost, r.model), (0.00042, 'openai/gpt-5-mini'));
    });
  });

  group('conversations', () {
    late AppDatabase db;
    late AppSettings settings;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      settings = AppSettings(db);
      await settings.load();
    });
    tearDown(() => db.close());

    test('the old single chat becomes the first saved conversation', () async {
      await settings.setRaw(
        ChatMemory.legacyKey(false),
        ChatMemory.encode(const [SavedTurn('user', 'plan my weekend'), SavedTurn('assistant', 'Sure.')]),
      );
      final m = ChatMemory(settings);
      await m.migrate(now: now);
      final list = m.list(agent: false);
      expect(list.single.name, 'Plan my weekend');
      expect(m.load(false).map((t) => t.text), ['plan my weekend', 'Sure.']);
      expect(settings.raw(ChatMemory.legacyKey(false)), '');
      await m.migrate(now: now);
      expect(m.list(), hasLength(1), reason: 'migrating twice adds nothing');
    });

    test('save, list newest first, rename, delete and undo; turns keep usage and cards', () async {
      final m = ChatMemory(settings);
      Conversation c(String id, bool agent, int day, String q) => Conversation(
        id: id,
        agent: agent,
        created: DateTime(2026, 10, day),
        updated: DateTime(2026, 10, day),
        turns: [
          SavedTurn('user', q),
          SavedTurn(
            'assistant',
            'ok',
            inputTokens: 100,
            outputTokens: 20,
            cost: 0.001,
            tools: const ['get_calendar'],
            actions: const [
              {'type': 'task', 'title': 'Call mom'},
            ],
            done: const {0: 'added'},
          ),
        ],
      );
      await m.save(c('a', false, 1, 'first'));
      await m.save(c('b', false, 3, 'second'));
      await m.save(c('x', true, 2, 'agent one'));
      await m.save(Conversation(id: 'empty', agent: false, created: now, updated: now));
      expect(m.list(agent: false).map((s) => s.name), ['Second', 'First']);
      expect(m.list().length, 3);
      final s = m.list(agent: true).single;
      expect((s.messages, s.tokens, s.cost), (2, 120, 0.001));
      final back = m.open('x')!.turns.last;
      expect(back.inputTokens, 100);
      expect(back.tools, ['get_calendar']);
      expect(back.actions.single['title'], 'Call mom');
      expect(back.done[0], 'added');
      await m.rename('a', 'Trip ideas');
      expect(m.list(agent: false).last.name, 'Trip ideas');
      await m.setCurrent(false, 'b');
      final gone = await m.delete('b');
      expect(m.list(agent: false).map((s) => s.id), ['a']);
      expect(m.currentId(false), isNull);
      await m.restore(gone!);
      expect(m.list(agent: false).map((s) => s.id), ['b', 'a']);
      expect(m.open('b')!.turns.length, 2);
    });

    test('conversations travel in backups, and an old backup still restores its chat', () async {
      final m = ChatMemory(settings);
      await m.save(
        Conversation(id: 'k', agent: true, created: now, updated: now, turns: const [SavedTurn('user', 'hello')]),
      );
      final json = await backupJson(db);
      final db2 = AppDatabase(NativeDatabase.memory());
      await restoreBackup(db2, json);
      final s2 = AppSettings(db2);
      await s2.load();
      expect(ChatMemory(s2).list().single.name, 'Hello');

      // A backup from before the list: one chat under the old key.
      final old = jsonDecode(json) as Map<String, dynamic>;
      (old['tables'] as Map)['settings'] = [
        {
          'key': 'ai.history.agent',
          'value': ChatMemory.encode(const [SavedTurn('user', 'old question')]),
        },
      ];
      final db3 = AppDatabase(NativeDatabase.memory());
      await restoreBackup(db3, jsonEncode(old));
      final s3 = AppSettings(db3);
      await s3.load();
      final m3 = ChatMemory(s3);
      await m3.migrate();
      expect(m3.list(agent: true).single.name, 'Old question');
      expect(m3.load(true).single.text, 'old question');
      await db2.close();
      await db3.close();
    });
  });

  test('usage totals by day, month, all time and model', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
    await settings.load();
    final u = AiUsage(settings);
    await u.record('anthropic/claude-haiku-4.5', 1000, 100, 0.0015, at: DateTime(2026, 10, 30, 9));
    await u.record('anthropic/claude-haiku-4.5', 500, 50, 0.0007, at: DateTime(2026, 10, 30, 11));
    await u.record('claude-code/sonnet', 4000, 300, null, at: DateTime(2026, 10, 2));
    await u.record('deepseek-chat', 200, 20, null, at: DateTime(2026, 9, 12));
    final today = u.total(from: DateTime(2026, 10, 30), to: DateTime(2026, 10, 31));
    expect((today.inputTokens, today.outputTokens, today.calls), (1500, 150, 2));
    expect(today.cost, closeTo(0.0022, 1e-9));
    final month = u.total(from: DateTime(2026, 10));
    expect((month.tokens, month.unpriced, month.priced), (5950, 1, true));
    expect(u.total().tokens, 6170);
    expect(u.byModel().map((e) => e.$1), ['claude-code/sonnet', 'anthropic/claude-haiku-4.5', 'deepseek-chat']);
    expect(u.total(from: DateTime(2026, 9), to: DateTime(2026, 10)).priced, isFalse);
    expect(formatTokens(950), '950');
    expect(formatTokens(12400), '12K');
    expect(formatTokens(1250), '1.3K');
    expect(formatUsd(0.0022), r'$0.0022');
    expect(formatUsd(1.234), r'$1.23');
    await db.close();
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

    testWidgets('the agent looks things up, proposes, and the chat lands in History', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-k';
      final bodies = <Map>[];
      AiSetup.newClient = () => MockClient((r) async {
        bodies.add(jsonDecode(r.body) as Map);
        if (bodies.length == 1) {
          return json({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'r1',
                      'type': 'function',
                      'function': {'name': 'get_recurring', 'arguments': '{}'},
                    },
                    {
                      'id': 'p1',
                      'type': 'function',
                      'function': {'name': 'propose_task', 'arguments': '{"title":"Cancel Netflix"}'},
                    },
                  ],
                },
              },
            ],
            'usage': {'prompt_tokens': 3000, 'completion_tokens': 40, 'cost': 0.0031},
          });
        }
        return json({
          ...openAiOk('You pay for **Netflix** and **Rent**. Here is a reminder to cancel Netflix.'),
          'usage': {'prompt_tokens': 3200, 'completion_tokens': 60, 'cost': 0.0035},
        });
      });
      await pumpSeeded(
        tester,
        (s) {
          s.setRaw(AiSettings.billing, 'api');
          s.setRaw(AiSettings.model, 'openrouter');
          s.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
        },
        (db, settings) async {
          navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage(agent: true)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField).last, 'what subscriptions do I have?');
          await tester.tap(find.byTooltip('Send'));
          await settle(tester);
          expect(bodies.length, 2);
          // The agent got today at a glance and read the recurring list itself.
          expect((bodies.first['messages'] as List).first['content'], contains('get_recurring'));
          final toolMsg = (bodies.last['messages'] as List).firstWhere((m) => m['role'] == 'tool');
          expect(toolMsg['content'], contains('Netflix'));
          expect(find.text('You pay for Netflix and Rent. Here is a reminder to cancel Netflix.'), findsOneWidget);
          expect(find.text('Looked at recurring payments'), findsOneWidget);
          expect(find.text('6200 in, 100 out tokens · \$0.0066'), findsOneWidget);
          expect(find.text('Cancel Netflix'), findsOneWidget);
          expect(await tester.runAsync(() => db.select(db.todos).get()), hasLength(2));
          await tester.tap(find.text('Add'));
          await settle(tester);
          final todos = await tester.runAsync(() => db.select(db.todos).get());
          expect(todos!.where((t) => t.title == 'Cancel Netflix'), hasLength(1));

          // Saved with its totals, and counted in usage.
          final saved = ChatMemory(settings).list(agent: true).single;
          expect((saved.name, saved.tokens), ('What subscriptions do I have?', 6300));
          expect(saved.cost, closeTo(0.0066, 1e-9));
          expect(ChatMemory(settings).load(true).last.done, {0: 'added'});
          expect(AiUsage(settings).total().tokens, 6300);

          // History: rename it, then open it again from the list.
          await tester.tap(find.byTooltip('New chat'));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byTooltip('History'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(ChatHistoryPage), findsOneWidget);
          Finder inHistory(Finder f) => find.descendant(of: find.byType(ChatHistoryPage), matching: f);
          expect(inHistory(find.text('What subscriptions do I have?')), findsOneWidget);
          await tester.tap(inHistory(find.byTooltip('More')));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Rename'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField).last, 'Subscriptions');
          await tester.tap(find.text('Save'));
          await settle(tester);
          expect(inHistory(find.text('Subscriptions')), findsOneWidget);
          await tester.tap(inHistory(find.text('Subscriptions')));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 1200));
          expect(find.byType(ChatHistoryPage), findsNothing);
          expect(find.text('Cancel Netflix'), findsOneWidget);
          expect(find.text('Added'), findsOneWidget, reason: 'an added card stays added after reopening');
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });

    testWidgets('a model without tools gets the next days and recurring list in the prompt', (tester) async {
      // The same path Claude Code and the Claude app take: the data comes in the system prompt.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'k';
      final systems = <String>[];
      AiSetup.newClient = () => MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        if (body.containsKey('tools')) {
          return json({
            'error': {'code': 404, 'message': 'No endpoints found that support tool use.'},
          }, 404);
        }
        systems.add((body['messages'] as List).first['content'] as String);
        return json(openAiOk('{"reply":"Rent and Netflix.","actions":[]}'));
      });
      await pumpSeeded(
        tester,
        (s) {
          s.setRaw(AiSettings.billing, 'api');
          s.setRaw(AiSettings.model, 'openrouter');
          s.setRaw(AiSettings.openrouterModel, 'old/model');
        },
        (db, settings) async {
          navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage(agent: true)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField).last, 'subscriptions?');
          await tester.tap(find.byTooltip('Send'));
          await settle(tester);
          expect(systems.single, allOf(contains('Netflix'), contains('Car insurance'), contains('Open day')));
          expect(find.text('Rent and Netflix.'), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });
  });

  test('agent prompts mention the tools and the new actions', () {
    expect(agentToolPrompt(now), contains('get_recurring'));
    expect(agentSystemPrompt(now), contains('"type": "recurring"'));
    final r = parseAgentReply(
      '{"reply":"ok","actions":[{"type":"complete","id":3},{"type":"recurring","name":"Gym",'
      '"amount":"29,99","period":1}]}',
    );
    expect(r.actions.map((a) => a.label), ['Mark done', 'Recurring payment']);
    expect(r.actions.first.verb, 'Done');
  });
}
