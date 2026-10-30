import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/ai/ai_service.dart';
import 'package:hub/apps/ai/claude_code.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/edition.dart';
import 'package:hub/core/settings.dart';
import 'package:hub/core/sync/sync_engine.dart';
import 'package:hub/core/sync/sync_service.dart';
import 'package:hub/main.dart';

import 'widget_test.dart' show pumpWithDb;

String resultJson(String text, {bool error = false, String subtype = 'success', int? status}) => jsonEncode({
  'type': 'result',
  'subtype': subtype,
  'is_error': error,
  'result': text,
  'api_error_status': status,
  'usage': {'input_tokens': 3, 'output_tokens': 2},
});

/// A runner whose `claude` is a fake that records what it was given.
class FakeClaude {
  FakeClaude(this.reply, {this.code = 0, this.stderr = ''});
  String reply;
  int code;
  String stderr;
  String? exe, stdin, system;
  List<String>? args;
  Map<String, String>? env;

  ClaudeCodeRunner runner({String? path = '/fake/claude'}) => ClaudeCodeRunner(
    locate: () async => path,
    run: (e, a, {required stdin, required workingDirectory, required environment, required timeout}) async {
      exe = e;
      args = a;
      this.stdin = stdin;
      env = environment;
      system = File(a[a.indexOf('--system-prompt-file') + 1]).readAsStringSync();
      return ProcessResult(1, code, reply, stderr);
    },
  );
}

void main() {
  group('Claude Code runner', () {
    test('builds a text-only one-turn command', () {
      final args = ClaudeCodeRunner.buildArgs(model: 'sonnet', systemFile: '/tmp/s.txt');
      expect(args.take(2), ['-p', '--output-format']);
      expect(args[args.indexOf('--output-format') + 1], 'json');
      expect(args[args.indexOf('--model') + 1], 'sonnet');
      expect(args[args.indexOf('--max-turns') + 1], '1');
      expect(args[args.indexOf('--tools') + 1], '');
      expect(args[args.indexOf('--system-prompt-file') + 1], '/tmp/s.txt');
      // Anything but a known alias becomes haiku, so nothing odd reaches the command line.
      final odd = ClaudeCodeRunner.buildArgs(model: 'opus; rm -rf /', systemFile: 'x');
      expect(odd[odd.indexOf('--model') + 1], 'haiku');
    });

    test('maps Hub models to Claude Code aliases', () {
      expect(ClaudeCodeRunner.aliasFor(aiModelById('anthropic.haiku')), 'haiku');
      expect(ClaudeCodeRunner.aliasFor(aiModelById('anthropic.sonnet')), 'sonnet');
      expect(ClaudeCodeRunner.aliasFor(aiModelById('anthropic.opus')), 'opus');
      expect(ClaudeCodeRunner.aliasFor(aiModelById('openai.gpt')), 'haiku');
    });

    test('turns a conversation into one prompt', () {
      expect(ClaudeCodeRunner.promptFrom(const [AiMessage('user', 'hi')]), 'hi');
      final p = ClaudeCodeRunner.promptFrom(const [
        AiMessage('user', 'a'),
        AiMessage('assistant', 'b'),
        AiMessage('user', 'c'),
      ]);
      expect(p, contains('User: a'));
      expect(p, contains('Assistant: b'));
      expect(p.trim().endsWith('c'), isTrue);
    });

    test('reads the JSON result', () {
      final r = ClaudeCodeRunner.parseOutput(0, resultJson('  ok  '), '');
      expect(r.text, 'ok');
      expect(r.inputTokens, 3);
      expect(r.outputTokens, 2);
      // Extra lines before the result are skipped.
      expect(ClaudeCodeRunner.parseOutput(0, 'warning: x\n${resultJson('fine')}\n', '').text, 'fine');
    });

    test('maps errors to plain messages', () {
      ClaudeCodeException err(String out, [String stderr = '', int code = 1]) {
        try {
          ClaudeCodeRunner.parseOutput(code, out, stderr);
        } on ClaudeCodeException catch (e) {
          return e;
        }
        fail('no error');
      }

      final auth = err(resultJson('Not logged in · Please run /login', error: true));
      expect(auth.kind, ClaudeCodeFailure.notSignedIn);
      expect(auth.notReady, isTrue);
      expect(err(resultJson('Invalid API key', error: true)).kind, ClaudeCodeFailure.notSignedIn);
      final limit = err(resultJson('Claude AI usage limit reached|1793390000', error: true));
      expect(limit.kind, ClaudeCodeFailure.limit);
      expect(limit.message, "Your plan's usage limit is reached; it resets later.");
      expect(err(resultJson("You've hit your limit · resets 5pm", error: true)).kind, ClaudeCodeFailure.limit);
      expect(
        err(resultJson('x', error: true, subtype: 'error_during_execution', status: 429)).kind,
        ClaudeCodeFailure.limit,
      );
      final other = err('', 'boom happened\nmore');
      expect(other.kind, ClaudeCodeFailure.other);
      expect(other.message, 'Claude Code: boom happened');
      expect(err('', 'Please run /login').kind, ClaudeCodeFailure.notSignedIn);
    });

    test('runs claude with the prompt on stdin and the system prompt in a file', () async {
      final fake = FakeClaude(resultJson('Hello'));
      final r = await fake.runner().ask(const [AiMessage('user', 'Say hi')], system: 'Be brief.', model: 'opus');
      expect(r.text, 'Hello');
      expect(fake.exe, '/fake/claude');
      expect(fake.stdin, 'Say hi');
      expect(fake.system, 'Be brief.');
      expect(fake.args![fake.args!.indexOf('--model') + 1], 'opus');
      expect(fake.env!.keys.map((k) => k.toUpperCase()), isNot(contains('ANTHROPIC_API_KEY')));
    });

    test('leaves API keys out of the environment so the plan is used', () {
      final env = ClaudeCodeRunner.environment({
        'PATH': '/bin',
        'ANTHROPIC_API_KEY': 'sk',
        'anthropic_auth_token': 't',
      });
      expect(env, {'PATH': '/bin'});
    });

    test('not installed, timeout and too long', () async {
      final missing = FakeClaude('').runner(path: null);
      await expectLater(
        missing.ask(const [AiMessage('user', 'x')]),
        throwsA(
          isA<ClaudeCodeException>()
              .having((e) => e.kind, 'kind', ClaudeCodeFailure.notInstalled)
              .having((e) => e.message, 'message', contains('run `claude` once')),
        ),
      );
      final slow = ClaudeCodeRunner(
        locate: () async => '/fake/claude',
        run: (e, a, {required stdin, required workingDirectory, required environment, required timeout}) =>
            throw TimeoutException('slow'),
      );
      await expectLater(
        slow.ask(const [AiMessage('user', 'x')]),
        throwsA(isA<ClaudeCodeException>().having((e) => e.message, 'message', contains('90 s'))),
      );
      await expectLater(
        FakeClaude('').runner().ask([AiMessage('user', 'x' * (ClaudeCodeRunner.maxPromptChars + 1))]),
        throwsA(isA<ClaudeCodeException>().having((e) => e.kind, 'kind', ClaudeCodeFailure.tooLong)),
      );
    });

    test('looks for claude in PATH and the usual install folders', () {
      final win = ClaudeCodeRunner.candidates(
        windows: true,
        env: {'Path': r'C:\bin;C:\tools\', 'USERPROFILE': r'C:\Users\me', 'APPDATA': r'C:\Users\me\AppData\Roaming'},
      );
      expect(win, contains(r'C:\bin\claude.exe'));
      expect(win, contains(r'C:\tools\claude.cmd'));
      expect(win, contains(r'C:\Users\me\.local\bin\claude.exe'));
      expect(win, contains(r'C:\Users\me\AppData\Roaming\npm\claude.cmd'));
      final mac = ClaudeCodeRunner.candidates(windows: false, env: {'PATH': '/usr/bin', 'HOME': '/Users/me'});
      expect(mac.first, '/usr/bin/claude');
      expect(mac, contains('/Users/me/.local/bin/claude'));
    });
  });

  group('laptop endpoint /ai', () {
    late AppDatabase db;
    late HttpServer server;
    late ClaudeCodeRunner oldLocal;
    late FakeClaude fake;
    final client = http.Client();

    setUp(() async {
      oldLocal = ClaudePlan.local;
      fake = FakeClaude(resultJson('From the laptop'));
      ClaudePlan.local = fake.runner();
      db = AppDatabase(NativeDatabase.memory());
      final engine = SyncEngine(db);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => SyncService.instance.handle(req, engine, 'secret'));
    });

    tearDown(() async {
      ClaudePlan.local = oldLocal;
      personalEdition = true;
      await server.close(force: true);
      await db.close();
    });

    Future<http.Response> post(Object body, {String? token = 'secret'}) => client.post(
      Uri.parse('http://127.0.0.1:${server.port}/ai'),
      headers: {'authorization': ?(token == null ? null : 'Bearer $token'), 'content-type': 'application/json'},
      body: body is String ? body : jsonEncode(body),
    );

    test('refuses requests without the sync key', () async {
      final none = await post({'prompt': 'hi'}, token: null);
      expect(none.statusCode, 401);
      final wrong = await post({'prompt': 'hi'}, token: 'nope');
      expect(wrong.statusCode, 401);
      expect(fake.stdin, isNull);
    });

    test('answers with Claude Code on the laptop', () async {
      final res = await post({
        'system': 'Be kind.',
        'model': 'sonnet',
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
      });
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['text'], 'From the laptop');
      expect(fake.stdin, 'Hello');
      expect(fake.system, 'Be kind.');
      expect(fake.args![fake.args!.indexOf('--model') + 1], 'sonnet');
    });

    test('passes errors on with their kind, and caps the size', () async {
      fake.reply = resultJson('Not logged in · Please run /login', error: true);
      final res = await post({'prompt': 'hi'});
      expect(jsonDecode(res.body), {'error': ClaudeCodeRunner.notSignedInMessage, 'kind': 'notSignedIn'});
      final big = await post({'prompt': 'x' * (ClaudeCodeRunner.maxPromptChars + 1)});
      expect(big.statusCode, 413);
      final huge = await post('"${'x' * (ClaudeCodeRunner.maxPromptChars * 5)}"');
      expect(huge.statusCode, 413);
    });

    test('works in the public build too', () async {
      personalEdition = false;
      final res = await post({'prompt': 'hi'});
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['text'], 'From the laptop');
      expect(fake.stdin, 'hi');
    });
  });

  group('plan routing', () {
    late AppDatabase db;
    late AppSettings settings;
    late ClaudeCodeRunner oldLocal;

    setUp(() async {
      oldLocal = ClaudePlan.local;
      db = AppDatabase(NativeDatabase.memory());
      settings = AppSettings(db);
      await settings.load();
    });

    tearDown(() async {
      ClaudePlan.local = oldLocal;
      personalEdition = true;
      await db.close();
    });

    test('the plan option counts in both builds', () async {
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      expect(AiSetup(settings).usePlan, isTrue);
      expect(AiSetup(settings).inApp, isTrue);
      personalEdition = false;
      expect(AiSetup(settings).usePlan, isTrue);
      expect(AiSetup(settings).inApp, isTrue);
      expect(await AiSetup(settings).apiReady(), isTrue);
    });

    test('the Claude Code model has its own setting, and falls back to the old model choice', () async {
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      await settings.setRaw(AiSettings.model, 'anthropic.opus');
      expect(AiSetup(settings).planAlias, 'opus');
      expect(AiSetup(settings).label, 'Claude Opus · Claude Code');
      await settings.setRaw(AiSettings.claudeCodeModel, 'haiku');
      expect(AiSetup(settings).planAlias, 'haiku');
      await settings.setRaw(AiSettings.claudeCodeModel, 'rm -rf');
      expect(AiSetup(settings).planAlias, 'opus');
    });

    test('runs locally when Claude Code is installed', () async {
      final fake = FakeClaude(resultJson('local answer'));
      ClaudePlan.local = fake.runner();
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      await settings.setRaw(AiSettings.model, 'anthropic.opus');
      final r = await AiSetup(settings).ask(const [AiMessage('user', 'q')], system: 'sys');
      expect(r.text, 'local answer');
      expect(fake.args![fake.args!.indexOf('--model') + 1], 'opus');
    });

    test('falls back to the Claude app when nothing can answer', () async {
      ClaudePlan.local = FakeClaude('').runner(path: null);
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      await expectLater(
        AiSetup(settings).ask(const [AiMessage('user', 'q')]),
        throwsA(isA<ClaudePlanUnavailable>().having((e) => e.note, 'note', contains('opened the Claude app'))),
      );
    });

    test('asks the laptop when this device is a sync client', () async {
      ClaudePlan.local = FakeClaude('').runner(path: null);
      await settings.setRaw(AiSettings.billing, AiSettings.claudeCode);
      await settings.setRaw(AiSettings.model, 'anthropic.sonnet');
      // setSync would start the real client; set the fields directly.
      settings
        ..syncMode = 'client'
        ..syncUrl = '100.64.0.1'
        ..syncToken = 'tok';
      late http.Request sent;
      final ai = AiSetup(
        settings,
        httpClient: MockClient((r) async {
          sent = r;
          return http.Response(jsonEncode({'text': 'remote answer', 'input_tokens': 1, 'output_tokens': 1}), 200);
        }),
      );
      final r = await ai.ask(const [AiMessage('user', 'q')], system: 's');
      expect(r.text, 'remote answer');
      expect(sent.url.toString(), 'http://100.64.0.1:8787/ai');
      expect(sent.headers['authorization'], 'Bearer tok');
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'sonnet');
      expect(body['system'], 's');
    });

    test('laptop errors: unreachable and not signed in fall back, the usage limit is shown', () async {
      Future<Object> remote(MockClient c) async {
        try {
          await ClaudePlan.askRemote('laptop', 'tok', const [AiMessage('user', 'q')], client: c);
        } catch (e) {
          return e;
        }
        fail('no error');
      }

      final down = await remote(MockClient((_) => throw http.ClientException('refused')));
      expect(
        down,
        isA<ClaudePlanUnavailable>().having((e) => e.note, 'note', 'Laptop not reachable, opened the Claude app'),
      );
      final signedOut = await remote(
        MockClient((_) async => http.Response(jsonEncode({'error': 'x', 'kind': 'notSignedIn'}), 502)),
      );
      expect(signedOut, isA<ClaudePlanUnavailable>());
      final refused = await remote(MockClient((_) async => http.Response('{"error":"wrong token"}', 401)));
      expect(refused, isA<ClaudePlanUnavailable>());
      final limit = await remote(
        MockClient(
          (_) async => http.Response(jsonEncode({'error': ClaudeCodeRunner.limitMessage, 'kind': 'limit'}), 502),
        ),
      );
      expect(limit, isNot(isA<ClaudePlanUnavailable>()));
      expect((limit as AiException).message, ClaudeCodeRunner.limitMessage);
    });
  });

  group('AI tab', () {
    tearDown(() => personalEdition = true);

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('AI')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('AI settings'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final personal in [true, false]) {
      testWidgets('offers Claude Code in the ${personal ? 'personal' : 'public'} build', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        personalEdition = personal;
        await pumpWithDb(tester, (db, s) => HubApp(db: db, settings: s), (db) async {
          await openSettings(tester);
          expect(find.text('Claude app (my plan)'), findsOneWidget);
          await tester.tap(find.text('Claude Code (my plan)'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Test'), findsOneWidget);
          await tester.tap(find.text('Sonnet'));
          await tester.pump(const Duration(milliseconds: 300));
          final rows = await tester.runAsync(db.readSettings);
          expect(rows![AiSettings.billing], AiSettings.claudeCode);
          expect(rows[AiSettings.claudeCodeModel], 'sonnet');
          expect(find.text('Claude Sonnet · Claude Code'), findsOneWidget);
        });
      });
    }
  });
}
