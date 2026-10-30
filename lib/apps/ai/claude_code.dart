import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/settings.dart';
import '../../core/sync/sync_service.dart' show SyncService;
import 'ai_service.dart';

// Your own Claude plan through Claude Code's headless mode (`claude -p`).
//
// Hub never touches the Claude login itself; the user signs in by running
// `claude` once on their own computer, and Claude Code does the rest.

/// Runs one program with [stdin] and returns its output, or throws
/// [TimeoutException] after [timeout]. Swapped for a fake in tests.
typedef ProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> args, {
  required String stdin,
  required String workingDirectory,
  required Map<String, String> environment,
  required Duration timeout,
});

/// Why Claude Code could not answer.
enum ClaudeCodeFailure { notInstalled, notSignedIn, limit, timeout, busy, tooLong, other }

class ClaudeCodeException extends AiException {
  const ClaudeCodeException(super.message, this.kind);
  final ClaudeCodeFailure kind;

  /// Not set up (missing or signed out): the Claude app is the better place to ask.
  bool get notReady => kind == ClaudeCodeFailure.notInstalled || kind == ClaudeCodeFailure.notSignedIn;
}

/// The plan path cannot be used right now, so the caller hands the request to
/// the Claude app instead. [note] is one line for the chat; [message] says why.
class ClaudePlanUnavailable extends AiException {
  const ClaudePlanUnavailable(super.message, {required this.note});
  final String note;
}

/// Runs `claude -p` on this computer.
class ClaudeCodeRunner {
  ClaudeCodeRunner({ProcessRun? run, Future<String?> Function()? locate, this.timeout = const Duration(seconds: 90)})
    : run = run ?? runProcess,
      locate = locate ?? findClaude;

  final ProcessRun run;
  final Future<String?> Function() locate;
  final Duration timeout;

  /// Longest question (system prompt plus conversation), in characters.
  static const maxPromptChars = 100000;

  static const notInstalledMessage =
      'Install Claude Code on this computer and run `claude` once to sign in with your plan.';
  static const notSignedInMessage =
      'Claude Code is not signed in. Run `claude` once on this computer and sign in with your Claude plan.';
  static const limitMessage = "Your plan's usage limit is reached; it resets later.";
  static const defaultSystem = 'You are a helpful assistant inside Hub, a personal app. Answer plainly and briefly.';

  /// Only desktops can run Claude Code.
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// The Claude Code model alias for a Hub model. Other providers' models use Haiku.
  static String aliasFor(AiModel m) => switch (m.id) {
    'anthropic.sonnet' => 'sonnet',
    'anthropic.opus' => 'opus',
    _ => 'haiku',
  };

  /// Only these aliases reach the command line.
  static const aliases = {'haiku', 'sonnet', 'opus'};
  static String cleanAlias(String? a) => aliases.contains(a) ? a! : 'haiku';

  /// The one place the command line is built. Text only: every tool is off and
  /// one turn is allowed. The question goes on stdin and the system prompt in a
  /// file, so nothing the user typed is ever on the command line.
  static List<String> buildArgs({required String model, required String systemFile}) => [
    '-p',
    '--output-format',
    'json',
    '--model',
    cleanAlias(model),
    '--max-turns',
    '1',
    '--tools',
    '',
    '--no-session-persistence',
    '--strict-mcp-config',
    '--system-prompt-file',
    systemFile,
  ];

  /// One prompt from a conversation: earlier turns as a transcript, then the last message.
  static String promptFrom(List<AiMessage> messages) {
    if (messages.isEmpty) return '';
    if (messages.length == 1) return messages.single.content;
    final earlier = messages.sublist(0, messages.length - 1);
    final b = StringBuffer('Earlier in this conversation:\n\n');
    for (final m in earlier) {
      b.write('${m.role == 'assistant' ? 'Assistant' : 'User'}: ${m.content}\n\n');
    }
    b.write('Now answer this message from the user:\n\n${messages.last.content}');
    return b.toString();
  }

  /// The environment for Claude Code: an API key in the environment would be
  /// used instead of the plan, so it is left out.
  static Map<String, String> environment(Map<String, String> parent) =>
      Map.of(parent)
        ..removeWhere((k, _) => const {'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN'}.contains(k.toUpperCase()));

  Future<AiReply> ask(List<AiMessage> messages, {String? system, String model = 'haiku'}) async {
    final prompt = promptFrom(messages);
    final sys = (system == null || system.trim().isEmpty) ? defaultSystem : system;
    if (prompt.length + sys.length > maxPromptChars) {
      throw const ClaudeCodeException('That question is too long for Claude Code.', ClaudeCodeFailure.tooLong);
    }
    final exe = await locate();
    if (exe == null) throw const ClaudeCodeException(notInstalledMessage, ClaudeCodeFailure.notInstalled);
    // A fresh empty folder, so no project instructions are picked up.
    final dir = await Directory.systemTemp.createTemp('hub-claude-');
    try {
      final sysFile = File('${dir.path}${Platform.pathSeparator}system.txt');
      await sysFile.writeAsString(sys);
      final ProcessResult r;
      try {
        r = await run(
          exe,
          buildArgs(model: model, systemFile: sysFile.path),
          stdin: prompt,
          workingDirectory: dir.path,
          environment: environment(Platform.environment),
          timeout: timeout,
        );
      } on TimeoutException {
        throw ClaudeCodeException(
          'Claude Code took too long to answer (${timeout.inSeconds} s). Try again.',
          ClaudeCodeFailure.timeout,
        );
      } on ProcessException {
        throw const ClaudeCodeException(notInstalledMessage, ClaudeCodeFailure.notInstalled);
      }
      return parseOutput(r.exitCode, '${r.stdout}', '${r.stderr}');
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Reads `--output-format json` output, or explains what went wrong.
  static AiReply parseOutput(int exitCode, String stdout, String stderr) {
    final j = _resultJson(stdout);
    if (j != null) {
      final text = (j['result'] as String? ?? '').trim();
      final ok = j['is_error'] != true && (j['subtype'] == null || j['subtype'] == 'success');
      if (ok && text.isNotEmpty) {
        final u = j['usage'] as Map? ?? const {};
        return AiReply(
          text,
          inputTokens: (u['input_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (u['output_tokens'] as num?)?.toInt() ?? 0,
        );
      }
      final status = (j['api_error_status'] as num?)?.toInt();
      final errors = j['errors'] is List ? (j['errors'] as List).join(' ') : '';
      final detail = [text, errors, stderr].where((s) => s.trim().isNotEmpty).join(' ').trim();
      if (j['subtype'] == 'error_max_turns') {
        throw const ClaudeCodeException('Claude Code stopped before answering. Try again.', ClaudeCodeFailure.other);
      }
      throw classify(detail, status: status);
    }
    throw classify('$stderr $stdout'.trim(), exitCode: exitCode);
  }

  static Map<String, dynamic>? _resultJson(String stdout) {
    Map<String, dynamic>? tryMap(String s) {
      try {
        final v = jsonDecode(s);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final whole = tryMap(stdout.trim());
    if (whole != null) return whole;
    for (final line in const LineSplitter().convert(stdout).reversed) {
      final m = line.trimLeft().startsWith('{') ? tryMap(line.trim()) : null;
      if (m != null && m['type'] == 'result') return m;
    }
    return null;
  }

  static final _auth = RegExp(
    r'not logged in|/login|log ?in again|invalid api key|authenticat|oauth|unauthori[sz]ed|\b401\b',
    caseSensitive: false,
  );
  static final _limit = RegExp(
    r'usage limit|limit reached|hit your limit|limit will reset|\bresets? (at|in)\b|rate.?limit|\b429\b',
    caseSensitive: false,
  );

  /// Turns Claude Code's own words into one of the plain messages above.
  static ClaudeCodeException classify(String detail, {int? status, int? exitCode}) {
    if (status == 401 || status == 403 || _auth.hasMatch(detail)) {
      return const ClaudeCodeException(notSignedInMessage, ClaudeCodeFailure.notSignedIn);
    }
    if (status == 429 || _limit.hasMatch(detail)) {
      return const ClaudeCodeException(limitMessage, ClaudeCodeFailure.limit);
    }
    final first = detail.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    final short = first.length > 200 ? '${first.substring(0, 200)}…' : first;
    return ClaudeCodeException(
      short.isEmpty
          ? 'Claude Code did not answer${exitCode == null ? '' : ' (exit $exitCode)'}.'
          : 'Claude Code: $short',
      ClaudeCodeFailure.other,
    );
  }

  /// Where Claude Code may be installed, in the order they are tried.
  static List<String> candidates({required bool windows, required Map<String, String> env}) {
    String? get(String k) => env.entries.where((e) => e.key.toUpperCase() == k).map((e) => e.value).firstOrNull;
    final sep = windows ? '\\' : '/';
    final dirs = (get('PATH') ?? '').split(windows ? ';' : ':').where((d) => d.trim().isNotEmpty);
    final names = windows ? const ['claude.exe', 'claude.cmd'] : const ['claude'];
    final home = get(windows ? 'USERPROFILE' : 'HOME');
    final appData = get('APPDATA');
    return [
      for (final d in dirs)
        for (final n in names) '${d.endsWith(sep) ? d.substring(0, d.length - 1) : d}$sep$n',
      if (windows) ...[
        if (home != null) '$home\\.local\\bin\\claude.exe',
        if (appData != null) '$appData\\npm\\claude.cmd',
      ] else ...[
        // Apps started from the dock do not get the shell's PATH.
        if (home != null) ...['$home/.local/bin/claude', '$home/.claude/local/claude'],
        '/opt/homebrew/bin/claude',
        '/usr/local/bin/claude',
      ],
    ];
  }

  static String? _found;

  /// The installed `claude`, or null. A hit is remembered; a miss is looked up
  /// again next time, so installing it later just works.
  static Future<String?> findClaude() async {
    if (!supported) return null;
    if (_found != null && File(_found!).existsSync()) return _found;
    for (final c in candidates(windows: Platform.isWindows, env: Platform.environment)) {
      if (File(c).existsSync()) return _found = c;
    }
    return null;
  }

  /// Starts the program, writes [stdin], and kills it after [timeout].
  static Future<ProcessResult> runProcess(
    String executable,
    List<String> args, {
    required String stdin,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    final p = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      // npm installs a .cmd wrapper, which needs cmd.exe.
      runInShell: Platform.isWindows && RegExp(r'\.(cmd|bat)$', caseSensitive: false).hasMatch(executable),
    );
    const decoder = Utf8Decoder(allowMalformed: true);
    final out = p.stdout.transform(decoder).join();
    final err = p.stderr.transform(decoder).join();
    try {
      p.stdin.add(utf8.encode(stdin));
      await p.stdin.flush();
      await p.stdin.close();
    } catch (_) {
      // It exited early; its output says why.
    }
    try {
      final code = await p.exitCode.timeout(timeout);
      return ProcessResult(p.pid, code, await out, await err);
    } on TimeoutException {
      p.kill();
      rethrow;
    }
  }
}

/// Picks where a plan request runs: Claude Code on this computer, or on the
/// laptop running Hub in Server mode (POST /ai). When neither can answer, it
/// throws [ClaudePlanUnavailable] so the caller hands off to the Claude app.
class ClaudePlan {
  /// Swapped for a runner with a fake process in tests.
  static ClaudeCodeRunner local = ClaudeCodeRunner();

  /// Gives up on an unreachable laptop after 5 seconds.
  static http.Client Function() newRemoteClient = () =>
      IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 5));

  static const setupHelp =
      'To use your Claude plan, install Claude Code on this computer and run `claude` once to sign in. '
      'On a phone, connect to the laptop in Me → Sync and keep Hub running there in Server mode.';

  static Future<AiReply> ask(
    AppSettings settings,
    List<AiMessage> messages, {
    String? system,
    String model = 'haiku',
    http.Client? client,
  }) async {
    final remote = settings.syncMode == 'client' && settings.syncUrl.isNotEmpty && settings.syncToken.isNotEmpty;
    if (ClaudeCodeRunner.supported && await local.locate() != null) {
      try {
        return await local.ask(messages, system: system, model: model);
      } on ClaudeCodeException catch (e) {
        if (!e.notReady) rethrow;
        if (!remote) {
          throw ClaudePlanUnavailable(e.message, note: 'Claude Code is not ready here, opened the Claude app');
        }
      }
    }
    if (remote) {
      final c = client ?? newRemoteClient();
      try {
        return await askRemote(settings.syncUrl, settings.syncToken, messages, system: system, model: model, client: c);
      } finally {
        if (client == null) c.close();
      }
    }
    throw const ClaudePlanUnavailable(setupHelp, note: 'Claude Code is not set up, opened the Claude app');
  }

  /// Asks the laptop's Hub, which runs Claude Code there.
  static Future<AiReply> askRemote(
    String url,
    String token,
    List<AiMessage> messages, {
    String? system,
    String model = 'haiku',
    required http.Client client,
    Duration timeout = const Duration(seconds: 100),
  }) async {
    const unreachable = ClaudePlanUnavailable(
      'Could not reach the laptop. Is it on, with Hub in Server mode and Tailscale connected?',
      note: 'Laptop not reachable, opened the Claude app',
    );
    http.Response res;
    try {
      res = await client
          .post(
            SyncService.endpoint(url, '/ai'),
            headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
            body: jsonEncode({
              'system': ?system,
              'model': ClaudeCodeRunner.cleanAlias(model),
              'messages': [
                for (final m in messages) {'role': m.role, 'content': m.content},
              ],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ClaudeCodeException('The laptop took too long to answer. Try again.', ClaudeCodeFailure.timeout);
    } on FormatException {
      throw unreachable;
    } catch (_) {
      // SocketException, ClientException and the connect timeout.
      throw unreachable;
    }
    if (res.statusCode == 401) {
      throw const ClaudePlanUnavailable(
        'The laptop refused the sync key. Check it in Me → Sync.',
        note: 'The laptop refused the sync key, opened the Claude app',
      );
    }
    if (res.statusCode == 404) {
      throw const ClaudePlanUnavailable(
        "The laptop's Hub does not offer your Claude plan yet. Update Hub there and keep it in Server mode.",
        note: "The laptop's Hub cannot use your plan yet, opened the Claude app",
      );
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('The laptop answered with error ${res.statusCode}.');
    }
    final error = j['error'] as String?;
    if (error != null) {
      final kind = ClaudeCodeFailure.values.asNameMap()[j['kind']] ?? ClaudeCodeFailure.other;
      final e = ClaudeCodeException(error, kind);
      if (e.notReady) {
        throw ClaudePlanUnavailable(
          'On the laptop: $error',
          note: 'Claude Code on the laptop is not ready, opened the Claude app',
        );
      }
      throw e;
    }
    return AiReply(
      (j['text'] as String? ?? '').trim(),
      inputTokens: (j['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (j['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  static bool _serving = false;

  /// The server side of POST /ai: answers with Claude Code on this computer.
  /// One request at a time; returns the HTTP status and JSON body.
  static Future<(int, Map<String, Object?>)> serve(Object? body) async {
    if (body is! Map) return (HttpStatus.badRequest, <String, Object?>{'error': 'Send a JSON object.'});
    final system = body['system'] is String ? body['system'] as String : null;
    final messages = <AiMessage>[
      if (body['messages'] is List)
        for (final m in body['messages'] as List)
          if (m is Map && m['content'] is String)
            AiMessage(m['role'] == 'assistant' ? 'assistant' : 'user', m['content'] as String),
      if (body['messages'] is! List && body['prompt'] is String) AiMessage('user', body['prompt'] as String),
    ];
    if (messages.isEmpty) return (HttpStatus.badRequest, <String, Object?>{'error': 'Nothing to ask.'});
    final size = (system?.length ?? 0) + messages.fold<int>(0, (n, m) => n + m.content.length);
    if (size > ClaudeCodeRunner.maxPromptChars) {
      return (
        HttpStatus.requestEntityTooLarge,
        <String, Object?>{
          'error': 'That question is too long for Claude Code.',
          'kind': ClaudeCodeFailure.tooLong.name,
        },
      );
    }
    if (_serving) {
      return (
        HttpStatus.tooManyRequests,
        <String, Object?>{
          'error': 'The laptop is answering another question. Try again in a moment.',
          'kind': ClaudeCodeFailure.busy.name,
        },
      );
    }
    _serving = true;
    try {
      final r = await local.ask(messages, system: system, model: ClaudeCodeRunner.cleanAlias(body['model'] as String?));
      return (
        HttpStatus.ok,
        <String, Object?>{'text': r.text, 'input_tokens': r.inputTokens, 'output_tokens': r.outputTokens},
      );
    } on ClaudeCodeException catch (e) {
      return (HttpStatus.badGateway, <String, Object?>{'error': e.message, 'kind': e.kind.name});
    } on AiException catch (e) {
      return (HttpStatus.badGateway, <String, Object?>{'error': e.message, 'kind': ClaudeCodeFailure.other.name});
    } finally {
      _serving = false;
    }
  }
}
