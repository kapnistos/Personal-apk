import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// The text of an Anthropic `system` or message `content`, which is a string or a list of text blocks.
String textOf(Object? v) => v is List ? v.map((b) => (b as Map)['text'] ?? '').join('\n\n') : '$v';

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

/// The shape of OpenRouter's GET /models answer, trimmed to a few models.
final openRouterList = {
  'data': [
    {
      'id': 'anthropic/claude-haiku-4.5',
      'name': 'Anthropic: Claude Haiku 4.5',
      'created': 1760000000,
      'context_length': 200000,
      'architecture': {
        'input_modalities': ['text', 'image'],
        'output_modalities': ['text'],
      },
      'pricing': {'prompt': '0.000001', 'completion': '0.000005', 'request': '0'},
      'supported_parameters': ['tools', 'max_tokens'],
    },
    {
      'id': 'anthropic/claude-3-haiku',
      'name': 'Anthropic: Claude 3 Haiku',
      'created': 1710000000,
      'context_length': 200000,
      'pricing': {'prompt': '0.00000025', 'completion': '0.00000125'},
    },
    {
      'id': 'anthropic/claude-sonnet-4.5',
      'name': 'Anthropic: Claude Sonnet 4.5',
      'created': 1759000000,
      'context_length': 1000000,
      'pricing': {'prompt': '0.000003', 'completion': '0.000015'},
    },
    {
      'id': 'openai/gpt-5-mini',
      'name': 'OpenAI: GPT-5 Mini',
      'created': 1754000000,
      'context_length': 400000,
      'pricing': {'prompt': '0.00000025', 'completion': '0.000002'},
    },
    {
      'id': 'deepseek/deepseek-chat-v3.1',
      'name': 'DeepSeek: DeepSeek V3.1',
      'created': 1755000000,
      'context_length': 163840,
      'pricing': {'prompt': '0.0000002', 'completion': '0.0000008'},
    },
    {
      'id': 'deepseek/deepseek-chat-v3.1:free',
      'name': 'DeepSeek: DeepSeek V3.1 (free)',
      'created': 1755000001,
      'context_length': 163840,
      'pricing': {'prompt': '0', 'completion': '0'},
    },
    {
      'id': 'meta-llama/llama-3.3-70b-instruct',
      'name': 'Meta: Llama 3.3 70B Instruct',
      'created': 1733000000,
      'context_length': 131072,
      'pricing': {'prompt': '0.00000013', 'completion': '0.0000004'},
    },
    {
      'id': 'openrouter/auto',
      'name': 'Auto Router',
      'context_length': 2000000,
      'pricing': {'prompt': '-1', 'completion': '-1'},
    },
    {
      'id': 'google/gemini-2.5-flash-image',
      'name': 'Google: Nano Banana',
      'architecture': {
        'output_modalities': ['image', 'text'],
      },
      'pricing': {'prompt': '0.0000003', 'completion': '0.0000025'},
    },
    {
      'id': 'openai/gpt-image-1',
      'name': 'OpenAI: Image',
      'architecture': {
        'output_modalities': ['image'],
      },
    },
    {'name': 'no id'},
    'junk',
  ],
};

/// Lets database work started from the UI finish: real time for the queries, then a frame.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Retries on 429 and 5xx happen at once in tests.
  setUpAll(() => AiClient.retryDelays = const [Duration.zero, Duration.zero]);

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
      expect((await failWith(MockClient((_) async => json({}, 404)))).message, contains('Model "m" is not available'));
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

  group('OpenRouter', () {
    test('key prefixes pick the company', () {
      expect(providersForKey('sk-or-v1-0123abcd'), [AiProvider.openrouter]);
      expect(providersForKey(' sk-ant-api03-xyz '), [AiProvider.anthropic]);
      expect(providersForKey('sk-proj-abcDEF123'), [AiProvider.openai]);
      expect(providersForKey('sk-svcacct-abc'), [AiProvider.openai]);
      expect(providersForKey('gsk_abc123'), [AiProvider.llama]);
      // DeepSeek's shape: sk- and 32 hex digits. Still checked against OpenAI if DeepSeek refuses it.
      expect(providersForKey('sk-0123456789abcdef0123456789abcdef'), [AiProvider.deepseek, AiProvider.openai]);
      expect(providersForKey('sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGhIjKl'), [
        AiProvider.openai,
        AiProvider.deepseek,
      ]);
      expect(providersForKey('hello'), isEmpty);
      expect(providersForKey(''), isEmpty);
    });

    test('chat request shape', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      late http.Request sent;
      final keys = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-key';
      final ai = AiSetup(
        settings,
        keys: keys,
        httpClient: MockClient((r) async {
          sent = r;
          return json(openAiOk('Hi from Haiku'));
        }),
      );
      await settings.setRaw(AiSettings.billing, 'api');
      await settings.setRaw(AiSettings.model, 'openrouter');
      expect(ai.modelIdFor(ai.model), 'openrouter/auto');
      expect(ai.label, 'Auto · OpenRouter');
      await settings.setRaw(AiSettings.openrouterModel, 'anthropic/claude-haiku-4.5');
      expect(await ai.apiReady(), isTrue);
      final reply = await ai.ask(const [AiMessage('user', 'Hi')], system: 'Sys', maxTokens: 300);
      expect(reply.text, 'Hi from Haiku');
      expect(reply.inputTokens, 20);
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(sent.headers['authorization'], 'Bearer sk-or-v1-key');
      expect(sent.headers['HTTP-Referer'], 'https://github.com/hub-app');
      expect(sent.headers['X-Title'], 'Hub');
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'anthropic/claude-haiku-4.5');
      expect(body['max_tokens'], 300);
      expect(body['messages'], [
        {'role': 'system', 'content': 'Sys'},
        {'role': 'user', 'content': 'Hi'},
      ]);
      expect(ai.label, 'claude-haiku-4.5 · OpenRouter');
      // With the list cached, the chip uses its name, without the company prefix.
      await settings.setRaw(
        AiSettings.openrouterModels,
        OpenRouterModel.encodeCache(OpenRouterModel.parseList(openRouterList), DateTime.now()),
      );
      expect(ai.label, 'Claude Haiku 4.5 · OpenRouter');
      await db.close();
    });

    test('content sent as parts is joined', () {
      final r = AiClient.parseOpenAi({
        'choices': [
          {
            'message': {
              'content': [
                {'type': 'text', 'text': 'a'},
                {'type': 'text', 'text': 'b'},
              ],
            },
          },
        ],
      });
      expect(r.text, 'ab');
    });

    Future<AiException> orFail(http.Client client, {String model = 'x/y'}) async {
      try {
        await AiClient(client, timeout: const Duration(milliseconds: 50)).chat(
          provider: AiProvider.openrouter,
          apiKey: 'sk-or-v1-k',
          model: model,
          messages: const [AiMessage('user', 'x')],
        );
      } on AiException catch (e) {
        return e;
      }
      throw StateError('no error');
    }

    Map<String, dynamic> orError(int code, String message) => {
      'error': {'code': code, 'message': message},
    };

    test('every error reads plainly', () async {
      expect(
        (await orFail(MockClient((_) async => json(orError(401, 'No auth credentials found'), 401)))).message,
        'OpenRouter did not accept this key. Check it and paste it again.',
      );
      expect(
        (await orFail(MockClient((_) async => json(orError(402, 'Insufficient credits'), 402)))).message,
        'Your OpenRouter account has no credit left. Top it up on their site.',
      );
      var calls = 0;
      final e429 = await orFail(
        MockClient((_) async {
          calls++;
          return json(orError(429, 'Rate limit exceeded'), 429);
        }),
      );
      expect(calls, 3, reason: 'two retries, then give up');
      expect(e429.message, contains('too many requests'));
      expect(
        (await orFail(
          MockClient((_) async => json(orError(400, 'nope/nothing is not a valid model ID'), 400)),
          model: 'nope/nothing',
        )).message,
        'Model "nope/nothing" is not available on OpenRouter. Pick another one in AI settings.',
      );
      expect(
        (await orFail(MockClient((_) async => json(orError(404, 'No endpoints found for x/y.'), 404)))).message,
        contains('is not available on OpenRouter'),
      );
      expect(
        (await orFail(MockClient((_) async => json(orError(400, 'messages: too long'), 400)))).message,
        'OpenRouter: messages: too long',
      );
      expect(
        (await orFail(MockClient((_) async => throw http.ClientException('Failed host lookup')))).message,
        'No connection. Check your internet and try again.',
      );
      expect(
        (await orFail(MockClient((_) => Completer<http.Response>().future))).message,
        'OpenRouter took too long to answer. Try again.',
      );
      // A 200 that carries the model company's error.
      expect(
        (await orFail(MockClient((_) async => json(orError(502, 'Provider returned error'))))).message,
        contains('busy or down'),
      );
      expect((await orFail(MockClient((_) async => json({'choices': []})))).message, contains('sent no answer'));
    });

    test('a 502 is retried and then answers', () async {
      var calls = 0;
      final reply = await AiClient(
        MockClient((_) async => ++calls == 1 ? json(orError(502, 'bad gateway'), 502) : json(openAiOk('fine'))),
      ).chat(provider: AiProvider.openrouter, apiKey: 'k', model: 'm', messages: const [AiMessage('user', 'x')]);
      expect(calls, 2);
      expect(reply.text, 'fine');
    });

    test('model list parsing, prices and suggestions', () {
      final list = OpenRouterModel.parseList(openRouterList);
      expect(list.map((m) => m.id), isNot(contains('openai/gpt-image-1')));
      expect(list.map((m) => m.id), contains('google/gemini-2.5-flash-image'));
      expect(list.length, 9);
      final haiku = list.first;
      expect(
        (haiku.name, haiku.context, haiku.inPrice, haiku.outPrice),
        ('Anthropic: Claude Haiku 4.5', 200000, 1.0, 5.0),
      );
      expect(haiku.details, r'200K context · $1 in, $5 out per million');
      expect(list.firstWhere((m) => m.id.endsWith(':free')).details, '164K context · free');
      final auto = list.firstWhere((m) => m.id == 'openrouter/auto');
      expect((auto.inPrice, auto.outPrice), (null, null));
      expect(list.firstWhere((m) => m.id == 'openai/gpt-5-mini').details, contains(r'$0.25 in, $2 out'));
      expect(OpenRouterModel.suggested(list).map((m) => m.id), [
        'anthropic/claude-haiku-4.5',
        'openai/gpt-5-mini',
        'deepseek/deepseek-chat-v3.1',
        'meta-llama/llama-3.3-70b-instruct',
        'anthropic/claude-sonnet-4.5',
      ]);
      expect(OpenRouterModel.suggested(const []), isEmpty);
      expect(OpenRouterModel.parseList({'data': 'x'}), isEmpty);
      expect(OpenRouterModel.parseList(null), isEmpty);
      final at = DateTime(2026, 10, 30, 12);
      final back = OpenRouterModel.decodeCache(OpenRouterModel.encodeCache(list, at))!;
      expect(back.$1, at);
      expect(back.$2.map((m) => m.details), list.map((m) => m.details));
      expect(OpenRouterModel.decodeCache('{bad'), isNull);
    });

    test('the model list is cached for a day and survives a network failure', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      var calls = 0;
      var down = false;
      http.Request? sent;
      final ai = AiSetup(
        settings,
        keys: MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-k',
        httpClient: MockClient((r) async {
          calls++;
          sent = r;
          if (down) throw http.ClientException('down');
          return json(openRouterList);
        }),
      );
      final now = DateTime(2026, 10, 30, 9);
      expect((await ai.openRouterModels(now: now)).length, 9);
      expect(sent!.method, 'GET');
      expect(sent!.url.toString(), 'https://openrouter.ai/api/v1/models');
      expect(sent!.headers['authorization'], 'Bearer sk-or-v1-k');
      await ai.openRouterModels(now: now.add(const Duration(hours: 5)));
      expect(calls, 1);
      await ai.openRouterModels(now: now.add(const Duration(hours: 25)));
      expect(calls, 2);
      down = true;
      expect((await ai.openRouterModels(refresh: true, now: now)).length, 9);
      await settings.setRaw(AiSettings.openrouterModels, '');
      await expectLater(ai.openRouterModels(now: now), throwsA(isA<AiException>()));
      await db.close();
    });

    test('pasting a key: detected, checked, saved only in the keystore', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final keys = MemoryAiKeyStore();
      final seen = <String>[];
      var openAiStatus = 401;
      var networkDown = false;
      final ai = AiSetup(
        settings,
        keys: keys,
        httpClient: MockClient((r) async {
          if (networkDown) throw http.ClientException('down');
          seen.add('${r.method} ${r.url}');
          if (r.url.host == 'openrouter.ai') {
            return r.headers['authorization'] == 'Bearer sk-or-v1-good'
                ? json({
                    'data': {'label': 'x', 'usage': 0},
                  })
                : json(orError(401, 'No auth credentials found'), 401);
          }
          if (r.url.host == 'api.openai.com') return json(orError(openAiStatus, 'Incorrect API key'), openAiStatus);
          return json(openAiOk('ok'));
        }),
      );

      expect(await ai.connect(' sk-or-v1-good '), AiProvider.openrouter);
      expect(seen.single, 'GET https://openrouter.ai/api/v1/key');
      expect(keys.values, {'ai-key-openrouter': 'sk-or-v1-good'});
      expect(settings.raw(AiSettings.billing), 'api');
      expect(ai.model.provider, AiProvider.openrouter);

      // A plain sk- key: OpenAI refuses it, DeepSeek takes it.
      seen.clear();
      const plain = 'sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGhIjKl';
      expect(await ai.connect(plain), AiProvider.deepseek);
      expect(seen, [
        'POST https://api.openai.com/v1/chat/completions',
        'POST https://api.deepseek.com/chat/completions',
      ]);
      expect(ai.model.id, 'deepseek.chat');
      expect(keys.values['ai-key-deepseek'], plain);

      // A refused key is kept, so fixing the account is enough, and the message says what happened.
      await expectLater(
        ai.connect('sk-or-v1-bad'),
        throwsA(isA<AiException>().having((e) => e.message, 'message', contains('did not accept'))),
      );
      expect(keys.values['ai-key-openrouter'], 'sk-or-v1-bad');

      // The company picked by hand wins over the guess.
      openAiStatus = 200;
      networkDown = true;
      await expectLater(
        ai.connect('sk-whatever', as: AiProvider.openai),
        throwsA(isA<AiException>().having((e) => e.message, 'message', contains('No connection'))),
      );
      expect(keys.values['ai-key-openai'], 'sk-whatever');
      expect(ai.model.provider, AiProvider.openai);
      await expectLater(ai.connect('  '), throwsA(isA<AiException>()));

      final rows = await db.readSettings();
      expect(
        rows.values.where((v) => v.contains('sk-or-v1') || v.contains(plain) || v.contains('sk-whatever')),
        isEmpty,
      );
      expect(rows.keys.where((k) => k.contains('key')), isEmpty);
      await db.close();
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

    testWidgets('pasting a key in AI settings connects it and keeps it out of settings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final keys = MemoryAiKeyStore();
      AiSetup.store = keys;
      final urls = <String>[];
      AiSetup.newClient = () => MockClient((r) async {
        urls.add(r.url.toString());
        if (r.url.path.endsWith('/key')) {
          return json({
            'data': {'label': 'sk-or-v1-abc...'},
          });
        }
        if (r.url.path.endsWith('/models')) return json(openRouterList);
        return json(openAiOk('ok'));
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': '  sk-or-v1-widget  '};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (db) async {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('AI')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Claude app'), findsOneWidget);
        await tester.tap(find.byTooltip('AI settings'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('API key'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Paste'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Connected to OpenRouter'), findsOneWidget);
        expect(keys.values, {'ai-key-openrouter': 'sk-or-v1-widget'});
        expect(urls.first, 'https://openrouter.ai/api/v1/key');
        // A starter model was picked from the live list.
        expect(find.text('Claude Haiku 4.5'), findsWidgets);
        final rows = await tester.runAsync(db.readSettings);
        expect(rows!['ai.billing'], 'api');
        expect(rows[AiSettings.model], 'openrouter');
        expect(rows[AiSettings.openrouterModel], 'anthropic/claude-haiku-4.5');
        expect(rows.values.where((v) => v.contains('sk-or-v1-widget')), isEmpty);

        // The list sheet: suggestions on top, search narrows it.
        await tester.tap(find.text('Change'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Suggested'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Search, e.g. claude, gpt, llama'), 'deepseek');
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Anthropic: Claude Haiku 4.5'), findsNothing);
        await tester.tap(find.text('DeepSeek: DeepSeek V3.1'));
        await tester.pump(const Duration(milliseconds: 400));
        final after = await tester.runAsync(db.readSettings);
        expect(after![AiSettings.openrouterModel], 'deepseek/deepseek-chat-v3.1');
      });
    });

    for (final openrouter in [false, true]) {
      testWidgets('Hub agent proposes, and only Add writes${openrouter ? ' (OpenRouter)' : ''}', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        final keys = MemoryAiKeyStore()
          ..values['ai-key-anthropic'] = 'k'
          ..values['ai-key-openrouter'] = 'sk-or-v1-k';
        AiSetup.store = keys;
        var calls = 0;
        const agentJson =
            '{"reply":"Got it.","actions":[{"type":"expense","amount":12,"category":"Eating out","note":"lunch"},'
            '{"type":"task","title":"Call the landlord"}]}';
        AiSetup.newClient = () => MockClient((r) async {
          calls++;
          final body = jsonDecode(r.body) as Map;
          if (openrouter) {
            expect(r.url.host, 'openrouter.ai');
            expect(body['model'], 'deepseek/deepseek-chat-v3.1');
            expect((body['messages'] as List).first['content'], contains('Hub agent'));
            // Models on OpenRouter often wrap the JSON in a fence with a line before it.
            return json(openAiOk('Sure:\n```json\n$agentJson\n```'));
          }
          expect(textOf(body['system']), contains('Hub agent'));
          return json(anthropicOk(agentJson));
        });
        await pumpWithDb(
          tester,
          (db, s) {
            s.setRaw(AiSettings.billing, 'api');
            if (openrouter) {
              s.setRaw(AiSettings.model, 'openrouter');
              s.setRaw(AiSettings.openrouterModel, 'deepseek/deepseek-chat-v3.1');
            }
            return HubApp(db: db, settings: s);
          },
          (db) async {
            navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const AiChatPage(agent: true)));
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            // Home's quick-ask field sits under the chat; type into the chat's own.
            await tester.enterText(find.byType(TextField).last, '12 euro lunch and remind me to call the landlord');
            await tester.tap(find.byTooltip('Send'));
            await settle(tester);
            expect(calls, 1);
            expect(find.text('Got it.'), findsOneWidget);
            expect(find.text(openrouter ? '20 in, 7 out tokens' : '12 in, 5 out tokens'), findsOneWidget);
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
            await tester.pump(const Duration(seconds: 5));
          },
        );
      });
    }

    testWidgets('Stop drops a slow answer, and the AI tab opens on the last mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-openrouter'] = 'sk-or-v1-k';
      final slow = Completer<http.Response>();
      var calls = 0;
      AiSetup.newClient = () => MockClient((r) {
        calls++;
        return calls == 1 ? slow.future : Future.value(json(openAiOk('Quick answer')));
      });
      await pumpWithDb(
        tester,
        (db, s) {
          s.setRaw(AiSettings.billing, 'api');
          s.setRaw(AiSettings.model, 'openrouter');
          return HubApp(db: db, settings: s);
        },
        (db) async {
          await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('AI')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Auto · OpenRouter'), findsOneWidget);
          expect(find.text('Ask anything'), findsWidgets);
          await tester.tap(find.text('Plan my day'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Thinking…'), findsOneWidget);
          await tester.tap(find.byTooltip('Stop'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Stopped.'), findsOneWidget);
          slow.complete(json(openAiOk('Too late')));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Too late'), findsNothing);
          // The chat works again straight away, and the answer can be copied.
          await tester.enterText(find.byType(TextField).last, 'Again');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Quick answer'), findsOneWidget);
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
            return null;
          });
          addTearDown(
            () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.tap(find.byTooltip('Copy'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(copied, 'Quick answer');

          // Switch to the agent; the tab remembers it.
          await tester.tap(find.text('Hub agent'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Ask your Hub'), findsOneWidget);
          final rows = await tester.runAsync(db.readSettings);
          expect(rows![AiChatPage.modeKey], 'agent');
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });

    testWidgets('a quick ask from Home is sent as soon as the chat opens', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      AiSetup.store = MemoryAiKeyStore()..values['ai-key-anthropic'] = 'k';
      final asked = <String>[];
      AiSetup.newClient = () => MockClient((r) async {
        asked.add(textOf(((jsonDecode(r.body) as Map)['messages'] as List).last['content']));
        return json(anthropicOk('{"reply":"Added to your list.","actions":[{"type":"shopping","name":"milk"}]}'));
      });
      await pumpWithDb(
        tester,
        (db, s) {
          s.setRaw(AiSettings.billing, 'api');
          return HubApp(db: db, settings: s);
        },
        (db) async {
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const AiChatPage(agent: true, initialText: 'buy milk')),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await settle(tester);
          expect(asked, ['buy milk']);
          expect(find.text('Added to your list.'), findsOneWidget);
          expect(find.descendant(of: find.byType(AiChatPage), matching: find.text('Add')), findsOneWidget);
          expect(find.byTooltip('Back'), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
        },
      );
    });
  });
}
