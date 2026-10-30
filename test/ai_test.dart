import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/ai/ai_chat_page.dart';
import 'package:hub/apps/ai/ai_service.dart';
import 'package:hub/apps/ai/hub_agent.dart';
import 'package:hub/apps/claude/claude_bridge.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/main.dart';

import 'widget_test.dart' show pumpWithDb;

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> anthropicOk(String text) => {
  'content': [
    {'type': 'text', 'text': text},
  ],
  'usage': {'input_tokens': 12, 'output_tokens': 5},
};

Map<String, dynamic> openAiOk(String text) => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': text},
    },
  ],
  'usage': {'prompt_tokens': 20, 'completion_tokens': 7},
};

void main() {
  group('providers', () {
    test('Anthropic request and response', () async {
      late http.Request sent;
      final client = MockClient((r) async {
        sent = r;
        return json(anthropicOk('Hello'));
      });
      final reply = await AiClient(client).chat(
        provider: AiProvider.anthropic,
        apiKey: 'sk-ant-test',
        model: 'claude-haiku-5-5',
        system: 'Be brief',
        messages: const [AiMessage('user', 'Hi')],
        maxTokens: 100,
      );
      expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], 'sk-ant-test');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'claude-haiku-5-5');
      expect(body['max_tokens'], 100);
      expect(body['system'], 'Be brief');
      expect(body['messages'], [
        {'role': 'user', 'content': 'Hi'},
      ]);
      expect(reply.text, 'Hello');
      expect(reply.inputTokens, 12);
      expect(reply.outputTokens, 5);
      expect(reply.usage, '12 in, 5 out tokens');
    });

    test('OpenAI request and response', () async {
      late http.Request sent;
      final client = MockClient((r) async {
        sent = r;
        return json(openAiOk('Hey'));
      });
      final reply = await AiClient(client).chat(
        provider: AiProvider.openai,
        apiKey: 'sk-oa',
        model: 'gpt-5-mini',
        system: 'Sys',
        messages: const [AiMessage('user', 'Hi'), AiMessage('assistant', 'Yo'), AiMessage('user', 'Again')],
      );
      expect(sent.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(sent.headers['authorization'], 'Bearer sk-oa');
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'gpt-5-mini');
      expect((body['messages'] as List).first, {'role': 'system', 'content': 'Sys'});
      expect((body['messages'] as List).length, 4);
      expect(reply.text, 'Hey');
      expect(reply.inputTokens, 20);
      expect(reply.outputTokens, 7);
    });

    test('DeepSeek uses its own endpoint', () async {
      late http.Request sent;
      final client = MockClient((r) async {
        sent = r;
        return json(openAiOk('ok'));
      });
      await AiClient(client).chat(
        provider: AiProvider.deepseek,
        apiKey: 'ds',
        model: 'deepseek-chat',
        messages: const [AiMessage('user', 'Hi')],
      );
      expect(sent.url.toString(), 'https://api.deepseek.com/chat/completions');
      expect(sent.headers['authorization'], 'Bearer ds');
    });

    test('Llama uses the base url and works without a key', () async {
      late http.Request sent;
      final client = MockClient((r) async {
        sent = r;
        return json(openAiOk('local'));
      });
      final reply = await AiClient(client).chat(
        provider: AiProvider.llama,
        apiKey: '',
        model: 'llama3.3',
        baseUrl: 'http://192.168.1.20:11434/v1/',
        messages: const [AiMessage('user', 'Hi')],
      );
      expect(sent.url.toString(), 'http://192.168.1.20:11434/v1/chat/completions');
      expect(sent.headers.containsKey('authorization'), isFalse);
      expect(reply.text, 'local');
      expect(AiClient.endpoint(AiProvider.llama).toString(), 'https://api.groq.com/openai/v1/chat/completions');
    });
  });

  group('errors', () {
    Future<AiException> failWith(http.Client client, [AiProvider p = AiProvider.anthropic, String key = 'k']) async {
      try {
        await AiClient(
          client,
          timeout: const Duration(milliseconds: 50),
        ).chat(provider: p, apiKey: key, model: 'm', messages: const [AiMessage('user', 'x')]);
      } on AiException catch (e) {
        return e;
      }
      throw StateError('no error');
    }

    test('401, 429, 404, 500 and others read plainly', () async {
      final e401 = await failWith(
        MockClient(
          (_) async => json({
            'type': 'error',
            'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'},
          }, 401),
        ),
      );
      expect(e401.status, 401);
      expect(e401.message, contains('did not accept this key'));
      final e429 = await failWith(MockClient((_) async => json({}, 429)), AiProvider.openai);
      expect(e429.message, contains('too many requests'));
      expect(e429.message, startsWith('OpenAI'));
      expect((await failWith(MockClient((_) async => json({}, 404)))).message, contains('Model "m" was not found'));
      expect((await failWith(MockClient((_) async => json({}, 529)))).message, contains('busy'));
      final e400 = await failWith(
        MockClient(
          (_) async => json({
            'error': {'message': 'bad thing'},
          }, 400),
        ),
        AiProvider.deepseek,
      );
      expect(e400.message, 'DeepSeek: bad thing');
    });

    test('no network, timeout, missing key, bad body', () async {
      expect(
        (await failWith(MockClient((_) async => throw http.ClientException('Failed host lookup')))).message,
        contains('No connection'),
      );
      expect((await failWith(MockClient((_) => Completer<http.Response>().future))).message, contains('took too long'));
      expect(
        (await failWith(MockClient((_) async => json({})), AiProvider.openai, '')).message,
        'Add your OpenAI key first.',
      );
      expect(
        (await failWith(MockClient((_) async => http.Response('<html>', 200)))).message,
        contains('could not read'),
      );
    });
  });

  group('agent', () {
    test('reads JSON inside code fences', () {
      final r = parseAgentReply('''
Sure!
```json
{"reply": "Added lunch.", "actions": [
  {"type": "expense", "amount": 12, "category": "eating out", "note": "lunch"},
  {"type": "note", "title": "Landlord", "body": "Call the landlord"},
  {"type": "task", "title": "Pay rent", "due": "2026-11-01", "important": true},
  {"type": "event", "title": "Dentist", "start": "2026-10-31T14:00"},
  {"type": "shopping", "name": "milk", "quantity": "2"},
  {"type": "expense", "amount": 0},
  {"type": "rocket", "title": "x"},
  "junk"
]}
```''');
      expect(r.reply, 'Added lunch.');
      expect(r.actions.map((a) => a.type), ['expense', 'note', 'task', 'event', 'shopping']);
      expect(r.actions.first.cents, 1200);
      expect(r.actions.first.category(EntryKind.expense), 'Eating out');
      expect(r.actions.first.summary, '€12.00 on Eating out, lunch');
    });

    test('falls back to plain text', () {
      final r = parseAgentReply('I could not understand that.');
      expect(r.reply, 'I could not understand that.');
      expect(r.actions, isEmpty);
      final broken = parseAgentReply('{"reply": "half');
      expect(broken.reply, '{"reply": "half');
      expect(parseAgentReply('{"actions": [{"type":"task","title":"A"}]}').reply, isNotEmpty);
      expect(
        parseAgentReply('{"reply":"x","actions":[{"type":"expense","amount":"€ 3,50","category":"zzz"}]}')
            .actions
            .single
            .category(EntryKind.expense),
        'Other',
      );
    });

    test('system prompt carries the date', () {
      final s = agentSystemPrompt(DateTime(2026, 10, 30));
      expect(s, contains('Friday 30 October 2026'));
      expect(s, contains('"actions"'));
    });

    test('actions write through the database', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final r = parseAgentReply(
        '{"reply":"ok","actions":['
        '{"type":"expense","amount":12.5,"category":"Groceries","note":"AH","date":"2026-10-29"},'
        '{"type":"income","amount":100,"category":"Gift"},'
        '{"type":"note","title":"Idea","body":"Build a shed"},'
        '{"type":"task","title":"Call mom","due":"2026-11-02"},'
        '{"type":"event","title":"Dentist","start":"2026-10-31T14:00"},'
        '{"type":"shopping","name":"milk","quantity":"2"}]}',
      );
      for (final a in r.actions) {
        await a.apply(db, now: DateTime(2026, 10, 30));
      }
      final entries = await db.select(db.entries).get();
      expect(entries.map((e) => (e.kind, e.amountCents, e.category)), [
        (EntryKind.expense, 1250, 'Groceries'),
        (EntryKind.income, 10000, 'Gift'),
      ]);
      expect(entries.first.date, DateTime(2026, 10, 29));
      expect((await db.select(db.notes).get()).where((n) => n.body == 'Build a shed'), hasLength(1));
      final todo = (await db.select(db.todos).get()).singleWhere((t) => t.title == 'Call mom');
      expect(todo.title, 'Call mom');
      expect(todo.due, DateTime(2026, 11, 2));
      final ev = (await db.select(db.events).get()).singleWhere((e) => e.title == 'Dentist');
      expect(ev.end, DateTime(2026, 10, 31, 15));
      final item = (await db.select(db.shoppingItems).get()).singleWhere((i) => i.name == 'milk');
      expect((item.name, item.quantity), ('milk', '2'));
      await db.close();
    });
  });

  group('setup and keys', () {
    test('keys go to the keystore, never the settings table', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final keys = MemoryAiKeyStore();
      late http.Request sent;
      final ai = AiSetup(
        settings,
        keys: keys,
        httpClient: MockClient((r) async {
          sent = r;
          return json(openAiOk('fine'));
        }),
      );
      await settings.setRaw(AiSettings.billing, 'api');
      await settings.setRaw(AiSettings.model, 'deepseek.reasoner');
      expect(await ai.apiReady(), isFalse);
      await ai.saveKey(AiProvider.deepseek, '  sk-secret-123 ');
      expect(await ai.apiReady(), isTrue);
      expect(keys.values, {'ai-key-deepseek': 'sk-secret-123'});
      await ai.testKey(AiProvider.deepseek, 'sk-secret-123');
      final reply = await ai.ask(const [AiMessage('user', 'hi')]);
      expect(reply.text, 'fine');
      expect((jsonDecode(sent.body) as Map)['model'], 'deepseek-reasoner');
      expect(sent.headers['authorization'], 'Bearer sk-secret-123');

      // A custom model id from Advanced is used.
      await settings.setRaw(AiSettings.modelIdKey('deepseek.reasoner'), 'deepseek-r9');
      await ai.ask(const [AiMessage('user', 'hi')]);
      expect((jsonDecode(sent.body) as Map)['model'], 'deepseek-r9');

      final rows = await db.readSettings();
      expect(rows.values.where((v) => v.contains('sk-secret')), isEmpty);
      expect(rows.keys.where((k) => k.contains('key')), isEmpty);
      await ai.saveKey(AiProvider.deepseek, '');
      expect(keys.values, isEmpty);
      await db.close();
    });

    test('clipboard answer is only offered when it is not the prompt', () {
      expect(claudeAnswerOnClipboard('prompt ', 'prompt'), isNull);
      expect(claudeAnswerOnClipboard('', 'prompt'), isNull);
      expect(claudeAnswerOnClipboard(null, 'prompt'), isNull);
      expect(claudeAnswerOnClipboard(' pasta → Lidl ', 'prompt'), 'pasta → Lidl');
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

    testWidgets('saving a key in the AI tab keeps it out of settings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final keys = MemoryAiKeyStore();
      AiSetup.store = keys;
      await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (db) async {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('AI')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.text('API key'));
        await tester.tap(find.text('API key'));
        await tester.pump(const Duration(milliseconds: 300));
        final field = find.widgetWithText(TextField, 'Anthropic API key');
        await tester.ensureVisible(field);
        await tester.enterText(field, 'sk-ant-widget');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Key saved on this device'), findsOneWidget);
        expect(keys.values['ai-key-anthropic'], 'sk-ant-widget');
        final rows = await tester.runAsync(db.readSettings);
        expect(rows!['ai.billing'], 'api');
        expect(rows.values.where((v) => v.contains('sk-ant')), isEmpty);
      });
    });

    testWidgets('Hub agent proposes, and only Add writes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final keys = MemoryAiKeyStore()..values['ai-key-anthropic'] = 'k';
      AiSetup.store = keys;
      var calls = 0;
      AiSetup.newClient = () => MockClient((r) async {
        calls++;
        expect((jsonDecode(r.body) as Map)['system'], contains('Hub agent'));
        return json(
          anthropicOk(
            '{"reply":"Got it.","actions":[{"type":"expense","amount":12,"category":"Eating out","note":"lunch"},'
            '{"type":"task","title":"Call the landlord"}]}',
          ),
        );
      });
      await pumpWithDb(
        tester,
        (db, s) {
          s.setRaw(AiSettings.billing, 'api');
          return HubApp(db: db, settings: s);
        },
        (db) async {
          navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage(agent: true)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(find.byType(TextField), '12 euro lunch and remind me to call the landlord');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(calls, 1);
          expect(find.text('Got it.'), findsOneWidget);
          expect(find.text('12 in, 5 out tokens'), findsOneWidget);
          expect(find.text('€12.00 on Eating out, lunch'), findsOneWidget);
          expect(await tester.runAsync(() => db.select(db.entries).get()), isEmpty);
          await tester.tap(find.text('Add').first);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Skip'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Added'), findsOneWidget);
          expect(find.text('Skipped'), findsOneWidget);
          final entries = await tester.runAsync(() => db.select(db.entries).get());
          expect(entries!.single.amountCents, 1200);
          final todos = await tester.runAsync(() => db.select(db.todos).get());
          expect(todos!.where((t) => t.title == 'Call the landlord'), isEmpty);
        },
      );
    });
  });
}
