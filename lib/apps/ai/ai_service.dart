import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/settings.dart';
import 'claude_code.dart';

/// The companies Hub can call with your own key.
enum AiProvider {
  anthropic('Anthropic'),
  openai('OpenAI'),
  deepseek('DeepSeek'),
  llama('Llama'),

  /// One key for many companies' models, through an OpenAI-style API.
  openrouter('OpenRouter');

  const AiProvider(this.label);
  final String label;

  /// Llama servers you run yourself (Ollama) need no key.
  bool get keyOptional => this == AiProvider.llama;
}

/// One model on offer, with what it is best at and the id sent to the provider.
class AiModel {
  const AiModel(this.id, this.provider, this.name, this.bestFor, this.defaultModelId);
  final String id;
  final AiProvider provider;
  final String name;
  final String bestFor;
  final String defaultModelId;
}

const aiModels = [
  AiModel(
    'anthropic.haiku',
    AiProvider.anthropic,
    'Claude Haiku',
    'Everyday questions and the Hub agent. Fast and cheap.',
    'claude-haiku-5-5',
  ),
  AiModel('anthropic.sonnet', AiProvider.anthropic, 'Claude Sonnet', 'Writing and planning.', 'claude-sonnet-5-5'),
  AiModel(
    'anthropic.opus',
    AiProvider.anthropic,
    'Claude Opus',
    'The hardest problems. Slower and costs more.',
    'claude-opus-5-5',
  ),
  AiModel('openai.mini', AiProvider.openai, 'GPT mini', 'Cheap and quick.', 'gpt-5-mini'),
  AiModel('openai.gpt', AiProvider.openai, 'GPT', 'A strong all-rounder.', 'gpt-5'),
  AiModel('deepseek.chat', AiProvider.deepseek, 'DeepSeek Chat', 'Very low cost.', 'deepseek-chat'),
  AiModel(
    'deepseek.reasoner',
    AiProvider.deepseek,
    'DeepSeek Reasoner',
    'Very low cost, thinks step by step. Slower.',
    'deepseek-reasoner',
  ),
  AiModel(
    'meta.llama',
    AiProvider.llama,
    'Llama',
    'Open model. Can run on your own laptop, so nothing leaves home.',
    'llama-3.3-70b-versatile',
  ),
  AiModel(
    'openrouter',
    AiProvider.openrouter,
    'OpenRouter',
    'Any model on one key: Claude, GPT, DeepSeek, Llama and more.',
    AiSettings.defaultOpenRouterModel,
  ),
];

AiModel aiModelById(String? id) => aiModels.firstWhere((m) => m.id == id, orElse: () => aiModels.first);

/// One turn of a conversation.
class AiMessage {
  const AiMessage(this.role, this.content);
  final String role; // user or assistant
  final String content;
}

/// The model's answer and what it cost in tokens.
class AiReply {
  const AiReply(
    this.text, {
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost,
    this.model,
    this.toolsUsed = const [],
  });
  final String text;
  final int inputTokens;
  final int outputTokens;

  /// What the call cost in US dollars, when the provider says or the price is known.
  final double? cost;

  /// The model that answered, when the provider says (OpenRouter's Auto picks one).
  final String? model;

  /// Names of the tools the model called on the way, in order.
  final List<String> toolsUsed;

  String get usage => '$inputTokens in, $outputTokens out tokens';

  AiReply copyWith({double? cost, String? model}) => AiReply(
    text,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cost: cost ?? this.cost,
    model: model ?? this.model,
    toolsUsed: toolsUsed,
  );
}

/// A function the model may call, described with a JSON schema for its arguments.
class AiTool {
  const AiTool(this.name, this.description, [this.parameters = const {'type': 'object', 'properties': {}}]);
  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> get openAi => {
    'type': 'function',
    'function': {'name': name, 'description': description, 'parameters': parameters},
  };

  Map<String, Object?> get anthropic => {'name': name, 'description': description, 'input_schema': parameters};
}

/// One call the model asked for.
class AiToolCall {
  const AiToolCall(this.id, this.name, this.args);
  final String id;
  final String name;
  final Map<String, dynamic> args;
}

/// Runs one tool call and returns what the model should read back (usually JSON).
typedef AiToolRunner = Future<String> Function(String name, Map<String, dynamic> args);

/// A failed call, with a message fit to show as is.
class AiException implements Exception {
  const AiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// The model or provider cannot call tools; ask again with the data in the prompt instead.
class AiToolsUnsupported extends AiException {
  const AiToolsUnsupported(super.message, {super.status});
}

/// Where API keys live: only the device keystore, never the settings table, so
/// they are never in backups or sync.
abstract class AiKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAiKeyStore implements AiKeyStore {
  const SecureAiKeyStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryAiKeyStore implements AiKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Settings keys. None of them hold a secret.
class AiSettings {
  static const model = 'ai.model';

  /// 'plan' hands work to the Claude app; 'api' calls the provider on your key;
  /// [claudeCode] runs Claude Code on your Claude plan.
  static const billing = 'ai.billing';

  /// 'plan' was already taken by the Claude-app hand-off, so this has its own value.
  static const claudeCode = 'claudecode';

  /// haiku, sonnet or opus for Claude Code. Unset, it follows [model] as before.
  static const claudeCodeModel = 'ai.claudecode.model';
  static const llamaUrl = 'ai.llama.url';
  static String modelIdKey(String modelId) => 'ai.modelid.$modelId';
  static const defaultLlamaUrl = 'https://api.groq.com/openai/v1';

  /// The OpenRouter model id, such as anthropic/claude-haiku-4.5.
  static const openrouterModel = 'ai.openrouter.model';

  /// The fetched OpenRouter model list with the time it was fetched. A cache: left out of backups.
  static const openrouterModels = 'ai.openrouter.models';

  /// OpenRouter picks a model for each question until you choose one.
  static const defaultOpenRouterModel = 'openrouter/auto';
}

/// Which company a pasted key belongs to, from how it starts. Most likely first; empty when it is not
/// a known shape. Plain `sk-` keys can be OpenAI or DeepSeek, so both come back and the key test decides.
List<AiProvider> providersForKey(String key) {
  final k = key.trim();
  if (k.startsWith('sk-or-')) return const [AiProvider.openrouter];
  if (k.startsWith('sk-ant-')) return const [AiProvider.anthropic];
  if (k.startsWith('gsk_')) return const [AiProvider.llama];
  if (RegExp(r'^sk-(proj|svcacct|admin)-').hasMatch(k)) return const [AiProvider.openai];
  // DeepSeek keys are sk- and 32 hex digits; older OpenAI keys are longer and mixed case.
  if (RegExp(r'^sk-[0-9a-f]{32}$').hasMatch(k)) return const [AiProvider.deepseek, AiProvider.openai];
  if (k.startsWith('sk-')) return const [AiProvider.openai, AiProvider.deepseek];
  return const [];
}

/// One model on OpenRouter, from its live list. Prices are US dollars per million tokens.
class OpenRouterModel {
  const OpenRouterModel(
    this.id,
    this.name, {
    this.context = 0,
    this.inPrice,
    this.outPrice,
    this.created = 0,
    this.tools,
  });
  final String id;
  final String name;
  final int context;
  final double? inPrice;
  final double? outPrice;
  final int created;

  /// Whether the model can call tools, from its supported parameters. Null when OpenRouter did not say.
  final bool? tools;

  /// Estimated US dollars for a call, when both prices are known.
  double? costOf(int inputTokens, int outputTokens) {
    if (inPrice == null || outPrice == null) return null;
    return (inputTokens * inPrice! + outputTokens * outPrice!) / 1000000;
  }

  bool get free => inPrice == 0 && outPrice == 0;

  /// "200K context · $1 in, $5 out per million"
  String get details {
    final parts = <String>[];
    if (context > 0) parts.add('${context >= 1000 ? '${(context / 1000).round()}K' : '$context'} context');
    if (free) {
      parts.add('free');
    } else if (inPrice != null && outPrice != null) {
      parts.add('${_usd(inPrice!)} in, ${_usd(outPrice!)} out per million');
    }
    return parts.join(' · ');
  }

  static String _usd(double v) {
    if (v == 0) return r'$0';
    if (v >= 10) return '\$${v.round()}';
    final s = v.toStringAsFixed(v < 0.1 ? 3 : 2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '\$$s';
  }

  Map<String, Object?> toJson() => {
    'i': id,
    'n': name,
    'c': context,
    'p': inPrice,
    'o': outPrice,
    't': created,
    if (tools != null) 'tl': tools,
  };

  static OpenRouterModel? fromJson(Object? j) {
    if (j is! Map || j['i'] is! String) return null;
    return OpenRouterModel(
      j['i'] as String,
      (j['n'] as String?) ?? j['i'] as String,
      context: (j['c'] as num?)?.toInt() ?? 0,
      inPrice: (j['p'] as num?)?.toDouble(),
      outPrice: (j['o'] as num?)?.toDouble(),
      created: (j['t'] as num?)?.toInt() ?? 0,
      tools: j['tl'] is bool ? j['tl'] as bool : null,
    );
  }

  /// Reads OpenRouter's GET /models answer: {"data": [{"id", "name", "context_length", "pricing": {...}}]}.
  /// Models that cannot answer in text are left out.
  static List<OpenRouterModel> parseList(Object? body) {
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    double? perMillion(Object? v) {
      final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
      if (d == null || d < 0) return null; // -1 means the price varies (openrouter/auto)
      return double.parse((d * 1000000).toStringAsFixed(4));
    }

    final out = <OpenRouterModel>[];
    for (final m in data) {
      if (m is! Map) continue;
      final id = m['id'];
      if (id is! String || id.isEmpty) continue;
      final arch = m['architecture'];
      final outputs = arch is Map ? arch['output_modalities'] : null;
      if (outputs is List && !outputs.contains('text')) continue;
      final pricing = m['pricing'] is Map ? m['pricing'] as Map : const {};
      final name = m['name'];
      final params = m['supported_parameters'];
      out.add(
        OpenRouterModel(
          id,
          name is String && name.trim().isNotEmpty ? name.trim() : id,
          context: (m['context_length'] as num?)?.toInt() ?? 0,
          inPrice: perMillion(pricing['prompt']),
          outPrice: perMillion(pricing['completion']),
          created: (m['created'] as num?)?.toInt() ?? 0,
          tools: params is List ? params.contains('tools') : null,
        ),
      );
    }
    return out;
  }

  /// A few good starting points, found in [all] by id so only models OpenRouter offers today are shown:
  /// the newest Claude Haiku, a small GPT, DeepSeek's chat model, a Llama and Claude Sonnet.
  static List<OpenRouterModel> suggested(List<OpenRouterModel> all) {
    final picks = <OpenRouterModel>[];
    for (final pattern in [
      RegExp(r'^anthropic/claude-.*haiku'),
      RegExp(r'^openai/gpt-[\d.o]+-?mini$'),
      RegExp(r'^deepseek/deepseek-(chat|v\d)[^:]*$'),
      RegExp(r'^meta-llama/llama-[^:]*instruct$'),
      RegExp(r'^anthropic/claude-.*sonnet'),
    ]) {
      final hits = all.where((m) => pattern.hasMatch(m.id) && !m.id.contains(':') && !picks.contains(m)).toList()
        ..sort((a, b) => b.created.compareTo(a.created));
      if (hits.isNotEmpty) picks.add(hits.first);
    }
    return picks;
  }

  /// The cached list as stored in settings, with when it was fetched.
  static String encodeCache(List<OpenRouterModel> models, DateTime at) => jsonEncode({
    'at': at.toIso8601String(),
    'models': [for (final m in models) m.toJson()],
  });

  static (DateTime, List<OpenRouterModel>)? decodeCache(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      final at = DateTime.tryParse('${j['at']}');
      final list = j['models'];
      if (at == null || list is! List) return null;
      return (at, [for (final m in list) ?OpenRouterModel.fromJson(m)]);
    } catch (_) {
      return null;
    }
  }
}

/// Everything needed to call a model, built from settings and the keystore.
class AiSetup {
  AiSetup(this.settings, {AiKeyStore? keys, this.httpClient}) : keys = keys ?? store;

  /// Swapped for a memory store in tests.
  static AiKeyStore store = const SecureAiKeyStore();

  final AppSettings settings;
  final AiKeyStore keys;
  final http.Client? httpClient;
  http.Client? _own;
  http.Client get client => httpClient ?? (_own ??= newClient());

  /// Swapped for a MockClient in tests.
  static http.Client Function() newClient = http.Client.new;

  /// Ends any request still running; its caller gets an [AiException] and should ignore it.
  void close() {
    _own?.close();
    _own = null;
  }

  AiModel get model => aiModelById(settings.raw(AiSettings.model));
  bool get useApi => settings.raw(AiSettings.billing) == 'api';

  /// Your Claude plan through Claude Code.
  bool get usePlan => settings.raw(AiSettings.billing) == AiSettings.claudeCode;

  /// Answers come back into Hub (API key or Claude Code) rather than the Claude app.
  bool get inApp => useApi || usePlan;

  /// 'api', 'claudecode' or 'plan' (the Claude app), after the edition rules.
  String get billing => usePlan
      ? AiSettings.claudeCode
      : useApi
      ? 'api'
      : 'plan';

  /// The Claude Code model: haiku, sonnet or opus.
  String get planAlias {
    final a = settings.raw(AiSettings.claudeCodeModel);
    return ClaudeCodeRunner.aliases.contains(a) ? a! : ClaudeCodeRunner.aliasFor(model);
  }

  /// The OpenRouter model id in use.
  String get openRouterModel {
    final m = settings.raw(AiSettings.openrouterModel)?.trim() ?? '';
    return m.isEmpty ? AiSettings.defaultOpenRouterModel : m;
  }

  /// The model that actually answers: Claude Code runs Claude models only.
  String get modelName {
    if (usePlan) return aiModelById('anthropic.$planAlias').name;
    if (model.provider == AiProvider.openrouter) return openRouterName(openRouterModel);
    return model.name;
  }

  /// A readable name for an OpenRouter id, from the cached list when it is there.
  String openRouterName(String id) {
    if (id == AiSettings.defaultOpenRouterModel) return 'Auto';
    final m = openRouterInfo(id);
    if (m != null) return m.name.replaceFirst(RegExp(r'^[^:]{1,24}: '), '');
    return id.split('/').last;
  }

  /// An OpenRouter model from the cached list, with its prices.
  OpenRouterModel? openRouterInfo(String? id) {
    if (id == null) return null;
    final cached = OpenRouterModel.decodeCache(settings.raw(AiSettings.openrouterModels));
    for (final m in cached?.$2 ?? const <OpenRouterModel>[]) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The model id for usage totals: what is sent to the provider, or "claude-code/haiku" on the plan.
  String get modelId => usePlan ? 'claude-code/$planAlias' : modelIdFor(model);

  /// Models that refused tools before, one id a line, so they get the data in the prompt straight away.
  static const noToolsKey = 'ai.notools';
  Set<String> get _noTools => {...(settings.raw(noToolsKey) ?? '').split('\n').where((s) => s.trim().isNotEmpty)};

  /// Whether this setup can let the model look things up itself. API keys can; Claude Code and the
  /// Claude app get the data written into the prompt instead.
  bool get canUseTools {
    if (!useApi) return false;
    final id = modelIdFor(model);
    if (_noTools.contains(id)) return false;
    if (model.provider == AiProvider.openrouter && openRouterInfo(id)?.tools == false) return false;
    return true;
  }

  /// Remembers that the current model cannot call tools.
  Future<void> markNoTools() => settings.setRaw(noToolsKey, {..._noTools, modelIdFor(model)}.join('\n'), quiet: true);

  /// What answers, in a few words for the header chip: "Claude Haiku · Claude Code".
  String get label => switch (billing) {
    AiSettings.claudeCode => '$modelName · Claude Code',
    'api' => model.provider == AiProvider.openrouter ? '$modelName · OpenRouter' : modelName,
    _ => 'Claude app',
  };

  String modelIdFor(AiModel m) {
    if (m.provider == AiProvider.openrouter) return openRouterModel;
    final custom = settings.raw(AiSettings.modelIdKey(m.id))?.trim() ?? '';
    return custom.isEmpty ? m.defaultModelId : custom;
  }

  String get llamaUrl {
    final u = settings.raw(AiSettings.llamaUrl)?.trim() ?? '';
    return u.isEmpty ? AiSettings.defaultLlamaUrl : u;
  }

  static String keyName(AiProvider p) => 'ai-key-${p.name}';
  Future<String> keyFor(AiProvider p) async => (await keys.read(keyName(p)))?.trim() ?? '';
  Future<void> saveKey(AiProvider p, String key) =>
      key.trim().isEmpty ? keys.delete(keyName(p)) : keys.write(keyName(p), key.trim());

  /// True when calls are answered inside Hub: API mode with a key (or a keyless Llama), or
  /// the Claude plan, which throws [ClaudePlanUnavailable] from [ask] when it cannot answer.
  Future<bool> apiReady() async =>
      usePlan || (useApi && (model.provider.keyOptional || (await keyFor(model.provider)).isNotEmpty));

  /// Sends [messages] to the chosen model. This is the one place every AI request goes through.
  /// With [tools] and [runTool] (API keys only, see [canUseTools]) the model may look things up first.
  /// The reply says which model answered and, on OpenRouter, roughly what it cost.
  ///
  /// [systemTail] is the part of the system prompt that changes between calls (the time, today's data). It
  /// goes after [system] so the fixed start stays identical and the provider can cache it.
  Future<AiReply> ask(
    List<AiMessage> messages, {
    String? system,
    String? systemTail,
    int maxTokens = 2048,
    List<AiTool> tools = const [],
    AiToolRunner? runTool,
  }) async {
    final m = model;
    if (usePlan) {
      final r = await ClaudePlan.ask(
        settings,
        messages,
        system: _joinSystem(system, systemTail),
        model: planAlias,
        client: httpClient,
      );
      return r.copyWith(model: modelId);
    }
    final id = modelIdFor(m);
    final r = await AiClient(client).chat(
      provider: m.provider,
      apiKey: await keyFor(m.provider),
      model: id,
      messages: messages,
      system: system,
      systemTail: systemTail,
      baseUrl: m.provider == AiProvider.llama ? llamaUrl : null,
      maxTokens: maxTokens,
      tools: tools,
      runTool: runTool,
    );
    // Auto says which model it picked; otherwise keep the id as chosen, so totals group neatly.
    final used = id == AiSettings.defaultOpenRouterModel && r.model != null ? r.model! : id;
    final cost = m.provider != AiProvider.openrouter
        ? null
        : r.cost ?? openRouterInfo(used)?.costOf(r.inputTokens, r.outputTokens);
    return AiReply(
      r.text,
      inputTokens: r.inputTokens,
      outputTokens: r.outputTokens,
      cost: cost,
      model: used,
      toolsUsed: r.toolsUsed,
    );
  }

  /// A tiny call to check the key works. OpenRouter's is free: it reads the key's own details.
  Future<AiReply> testKey(AiProvider p, String key) async {
    if (p == AiProvider.openrouter) {
      try {
        await AiClient(client).openRouterKeyInfo(key.trim());
        return const AiReply('ok');
      } on AiException catch (e) {
        if (e.status != 404) rethrow;
        // An older OpenRouter without /key: ask the model instead.
      }
    }
    final m = aiModels.firstWhere((m) => m.provider == p);
    final chosen = model.provider == p ? model : m;
    return AiClient(client).chat(
      provider: p,
      apiKey: key.trim(),
      model: modelIdFor(chosen),
      messages: const [AiMessage('user', 'Say ok.')],
      baseUrl: p == AiProvider.llama ? llamaUrl : null,
      maxTokens: 16,
    );
  }

  /// The paste-and-go flow: works out whose key it is (or uses [as]), checks it, saves it in the
  /// keystore and switches Hub to it. Returns the provider. Throws [AiException] with a plain message
  /// when the key is refused or cannot be checked; the key is still saved, so a later retry works.
  Future<AiProvider> connect(String raw, {AiProvider? as}) async {
    final key = raw.trim();
    if (key.isEmpty) throw const AiException('Paste a key first.');
    var options = as != null ? [as] : providersForKey(key);
    if (options.isEmpty) options = [model.provider];
    AiException? firstError;
    for (final p in options) {
      try {
        await testKey(p, key);
        await _use(p, key);
        return p;
      } on AiException catch (e) {
        firstError ??= e;
        final refused = e.status == 401 || e.status == 403;
        if (!refused) {
          // Not a wrong key (no connection, no credit): keep it with the best guess.
          await _use(p, key);
          rethrow;
        }
      }
    }
    await _use(options.first, key);
    throw firstError!;
  }

  Future<void> _use(AiProvider p, String key) async {
    await saveKey(p, key);
    if (model.provider != p) await settings.setRaw(AiSettings.model, aiModels.firstWhere((m) => m.provider == p).id);
    await settings.setRaw(AiSettings.billing, 'api');
  }

  /// OpenRouter's models, from a cache under a day old unless [refresh]. Falls back to the cache when
  /// the network fails, and throws [AiException] only when there is nothing to show.
  Future<List<OpenRouterModel>> openRouterModels({bool refresh = false, DateTime? now}) async {
    final n = now ?? DateTime.now();
    final cached = OpenRouterModel.decodeCache(settings.raw(AiSettings.openrouterModels));
    if (!refresh && cached != null && cached.$2.isNotEmpty && n.difference(cached.$1) < const Duration(hours: 24)) {
      return cached.$2;
    }
    try {
      final list = await AiClient(client).openRouterModels(await keyFor(AiProvider.openrouter));
      if (list.isEmpty) throw const AiException('OpenRouter sent an empty model list. Try again later.');
      await settings.setRaw(AiSettings.openrouterModels, OpenRouterModel.encodeCache(list, n), quiet: true);
      return list;
    } on AiException {
      if (cached != null && cached.$2.isNotEmpty) return cached.$2;
      rethrow;
    }
  }
}

/// Raw HTTP calls to each provider.
class AiClient {
  AiClient(this.client, {this.timeout = const Duration(seconds: 90)});
  final http.Client client;
  final Duration timeout;

  /// Waits before trying again after a 429 or a server error. Emptied in tests.
  static List<Duration> retryDelays = const [Duration(seconds: 1), Duration(seconds: 3)];

  /// Tells OpenRouter which app is calling, as they ask.
  static const openRouterHeaders = {'HTTP-Referer': 'https://github.com/hub-app', 'X-Title': 'Hub'};
  static const openRouterBase = 'https://openrouter.ai/api/v1';

  static Uri endpoint(AiProvider p, {String? baseUrl}) => switch (p) {
    AiProvider.anthropic => Uri.parse('https://api.anthropic.com/v1/messages'),
    AiProvider.openai => Uri.parse('https://api.openai.com/v1/chat/completions'),
    AiProvider.deepseek => Uri.parse('https://api.deepseek.com/chat/completions'),
    AiProvider.llama => Uri.parse(
      '${(baseUrl ?? AiSettings.defaultLlamaUrl).trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    ),
    AiProvider.openrouter => Uri.parse('$openRouterBase/chat/completions'),
  };

  static bool _retryable(int status) => status == 408 || status == 429 || status >= 500;

  /// One request with the shared error handling: plain messages for no connection and timeouts,
  /// and a retry or two on 429 and 5xx.
  Future<http.Response> _send(AiProvider provider, Future<http.Response> Function() call) async {
    for (var attempt = 0; ; attempt++) {
      http.Response res;
      try {
        res = await call().timeout(timeout);
      } on TimeoutException {
        throw AiException('${provider.label} took too long to answer. Try again.');
      } catch (e) {
        // ClientException, SocketException and friends.
        throw const AiException('No connection. Check your internet and try again.');
      }
      if (_retryable(res.statusCode) && attempt < retryDelays.length) {
        await Future<void>.delayed(retryDelays[attempt]);
        continue;
      }
      return res;
    }
  }

  /// Anthropic prompt caching: a cached prefix is read at a tenth of the input price.
  static const _ephemeral = {'type': 'ephemeral'};

  /// [system] and [tail] as one prompt, for providers that take a single string.
  static String? _joinSystem(String? system, String? tail) {
    final t = tail == null || tail.isEmpty ? null : tail;
    if (system == null || system.isEmpty) return t;
    return t == null ? system : '$system\n\n$t';
  }

  /// [msgs] with a cache mark on the last block of the last message, leaving [msgs] itself untouched.
  static List<Map<String, Object?>> _cacheLast(List<Map<String, Object?>> msgs) {
    if (msgs.isEmpty) return msgs;
    final last = msgs.last;
    final c = last['content'];
    final List<Object?> blocks;
    if (c is String) {
      if (c.isEmpty) return msgs;
      blocks = [
        {'type': 'text', 'text': c},
      ];
    } else if (c is List && c.isNotEmpty && c.last is Map) {
      blocks = [...c];
    } else {
      return msgs;
    }
    blocks[blocks.length - 1] = {...Map<String, Object?>.from(blocks.last! as Map), 'cache_control': _ephemeral};
    return [...msgs.take(msgs.length - 1), {...last, 'content': blocks}];
  }

  /// Most tool rounds in one answer; the last round asks for words only.
  static const maxToolRounds = 8;

  /// Sends [messages] and returns the answer. With [tools] and [runTool], the model may call tools: each
  /// call is run, its result sent back, and the loop goes on until the model answers in words.
  /// Throws [AiToolsUnsupported] when the model or provider refuses tools.
  Future<AiReply> chat({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? system,
    String? systemTail,
    String? baseUrl,
    int maxTokens = 2048,
    List<AiTool> tools = const [],
    AiToolRunner? runTool,
  }) async {
    if (apiKey.isEmpty && !provider.keyOptional) {
      throw AiException('Add your ${provider.label} key first.');
    }
    final anthropic = provider == AiProvider.anthropic;
    final openrouter = provider == AiProvider.openrouter;
    final withTools = tools.isNotEmpty && runTool != null;
    final headers = {
      'content-type': 'application/json',
      if (anthropic) ...{'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      if (!anthropic && apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
      if (openrouter) ...openRouterHeaders,
    };
    final joined = _joinSystem(system, systemTail);
    final msgs = <Map<String, Object?>>[
      if (!anthropic && joined != null && joined.isNotEmpty) {'role': 'system', 'content': joined},
      for (final m in messages) {'role': m.role, 'content': m.content},
    ];
    final Uri url;
    try {
      url = endpoint(provider, baseUrl: baseUrl);
    } on FormatException {
      throw const AiException('That server address does not look right. Check it in AI settings.');
    }
    var inTokens = 0, outTokens = 0;
    double? cost;
    String? answeredBy;
    final used = <String>[];
    for (var round = 0; ; round++) {
      final last = round >= maxToolRounds;
      final body = anthropic
          ? {
              'model': model,
              'max_tokens': maxTokens,
              if (withTools && system != null && system.isNotEmpty)
                // Tools, then this fixed block, then the changing tail: each cached up to its mark.
                'system': [
                  {'type': 'text', 'text': system, 'cache_control': _ephemeral},
                  if (systemTail != null && systemTail.isNotEmpty) {'type': 'text', 'text': systemTail},
                ]
              else if (joined != null && joined.isNotEmpty)
                'system': joined,
              // A tool answer resends everything before it, so the end of the conversation is marked too.
              'messages': withTools ? _cacheLast(msgs) : msgs,
              if (withTools)
                'tools': [
                  for (var i = 0; i < tools.length; i++)
                    i == tools.length - 1 ? {...tools[i].anthropic, 'cache_control': _ephemeral} : tools[i].anthropic,
                ],
              if (withTools && last) 'tool_choice': {'type': 'none'},
            }
          : {
              'model': model,
              'messages': msgs,
              // OpenRouter holds credit for the longest possible answer, so ask for no more than needed.
              if (openrouter) 'max_tokens': maxTokens,
              if (openrouter) 'usage': {'include': true},
              if (withTools) 'tools': [for (final t in tools) t.openAi],
              if (withTools && last) 'tool_choice': 'none',
            };
      final res = await _send(provider, () => client.post(url, headers: headers, body: jsonEncode(body)));
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode != 200) {
        if (withTools && _refusesTools(res.statusCode, text)) {
          throw AiToolsUnsupported('$model cannot use tools.', status: res.statusCode);
        }
        throw errorFor(provider, res.statusCode, text, model);
      }
      final Map<String, dynamic> j;
      try {
        j = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        throw AiException('${provider.label} sent an answer Hub could not read.');
      }
      if (!anthropic) {
        // OpenRouter can answer 200 and still carry an error from the model's company.
        final err = j['error'] ?? ((j['choices'] as List?)?.firstOrNull as Map?)?['error'];
        if (err is Map) {
          final code = (err['code'] as num?)?.toInt() ?? 502;
          final raw = jsonEncode({'error': err});
          if (withTools && _refusesTools(code, raw)) throw AiToolsUnsupported('$model cannot use tools.', status: code);
          throw errorFor(provider, code, raw, model);
        }
        if (openrouter && (j['choices'] as List? ?? const []).isEmpty) {
          throw const AiException('OpenRouter sent no answer. Try again, or pick another model in AI settings.');
        }
      }
      final reply = anthropic ? parseAnthropic(j) : parseOpenAi(j);
      inTokens += reply.inputTokens;
      outTokens += reply.outputTokens;
      if (reply.cost != null) cost = (cost ?? 0) + reply.cost!;
      answeredBy ??= reply.model;
      final calls = withTools && !last ? toolCalls(j, anthropic: anthropic) : const <AiToolCall>[];
      if (calls.isEmpty) {
        return AiReply(
          reply.text,
          inputTokens: inTokens,
          outputTokens: outTokens,
          cost: cost,
          model: answeredBy,
          toolsUsed: used,
        );
      }
      final results = <(AiToolCall, String)>[];
      for (final c in calls) {
        used.add(c.name);
        String out;
        try {
          out = await runTool!(c.name, c.args);
        } catch (e) {
          out = jsonEncode({'error': 'The tool failed: $e'});
        }
        results.add((c, out));
      }
      if (anthropic) {
        msgs.add({'role': 'assistant', 'content': j['content']});
        msgs.add({
          'role': 'user',
          'content': [
            for (final (c, out) in results) {'type': 'tool_result', 'tool_use_id': c.id, 'content': out},
          ],
        });
      } else {
        final message = (((j['choices'] as List).first as Map)['message'] as Map? ?? const {}).cast<String, Object?>();
        msgs.add({
          'role': 'assistant',
          'content': message['content'],
          'tool_calls': message['tool_calls'],
          // DeepSeek's thinking models want their reasoning back with the calls.
          if (message['reasoning_content'] != null) 'reasoning_content': message['reasoning_content'],
        });
        for (final (c, out) in results) {
          msgs.add({'role': 'tool', 'tool_call_id': c.id, 'content': out});
        }
      }
    }
  }

  /// An error that means "this model cannot call tools", not a broken request.
  static bool _refusesTools(int status, String body) =>
      (status == 400 || status == 404 || status == 422) &&
      RegExp(r'tool|function', caseSensitive: false).hasMatch(body);

  /// The tool calls in one answer, for either API shape.
  static List<AiToolCall> toolCalls(Map<String, dynamic> j, {required bool anthropic}) {
    final out = <AiToolCall>[];
    if (anthropic) {
      for (final b in (j['content'] as List? ?? const [])) {
        if (b is Map && b['type'] == 'tool_use' && b['name'] is String) {
          final input = b['input'];
          out.add(
            AiToolCall('${b['id']}', b['name'] as String, input is Map ? input.cast<String, dynamic>() : const {}),
          );
        }
      }
      return out;
    }
    final choices = j['choices'] as List? ?? const [];
    final msg = choices.isEmpty ? null : (choices.first as Map)['message'] as Map?;
    for (final c in (msg?['tool_calls'] as List? ?? const [])) {
      if (c is! Map || c['function'] is! Map) continue;
      final f = c['function'] as Map;
      if (f['name'] is! String) continue;
      Map<String, dynamic> args = const {};
      final raw = f['arguments'];
      if (raw is Map) {
        args = raw.cast<String, dynamic>();
      } else if (raw is String && raw.trim().isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map) args = d.cast<String, dynamic>();
        } catch (_) {}
      }
      out.add(AiToolCall('${c['id'] ?? f['name']}', f['name'] as String, args));
    }
    return out;
  }

  /// GET /key: details of an OpenRouter key. Free, so it is the key test.
  Future<Map<String, dynamic>> openRouterKeyInfo(String apiKey) async {
    if (apiKey.isEmpty) throw const AiException('Add your OpenRouter key first.');
    final res = await _send(
      AiProvider.openrouter,
      () => client.get(
        Uri.parse('$openRouterBase/key'),
        headers: {'authorization': 'Bearer $apiKey', ...openRouterHeaders},
      ),
    );
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode != 200) throw errorFor(AiProvider.openrouter, res.statusCode, text, '', keyCheck: true);
    try {
      final j = jsonDecode(text);
      return j is Map<String, dynamic> && j['data'] is Map<String, dynamic> ? j['data'] as Map<String, dynamic> : {};
    } catch (_) {
      return {};
    }
  }

  /// GET /models: every model OpenRouter offers. The key is sent when there is one.
  Future<List<OpenRouterModel>> openRouterModels(String apiKey) async {
    final res = await _send(
      AiProvider.openrouter,
      () => client.get(
        Uri.parse('$openRouterBase/models'),
        headers: {if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey', ...openRouterHeaders},
      ),
    );
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode != 200) throw errorFor(AiProvider.openrouter, res.statusCode, text, '', keyCheck: true);
    try {
      return OpenRouterModel.parseList(jsonDecode(text));
    } catch (_) {
      throw const AiException('OpenRouter sent a model list Hub could not read.');
    }
  }

  static AiReply parseAnthropic(Map<String, dynamic> j) {
    final text = [
      for (final b in (j['content'] as List? ?? const []))
        if (b is Map && b['type'] == 'text') b['text'] as String? ?? '',
    ].join();
    final u = j['usage'] as Map? ?? const {};
    return AiReply(
      text.trim(),
      inputTokens: (u['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (u['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  static AiReply parseOpenAi(Map<String, dynamic> j) {
    final choices = j['choices'] as List? ?? const [];
    final msg = choices.isEmpty ? null : (choices.first as Map)['message'] as Map?;
    final u = j['usage'] as Map? ?? const {};
    final content = msg?['content'];
    return AiReply(
      (content is String
              ? content
              : content is List
              // Some models send content as parts: [{"type": "text", "text": "..."}].
              ? content.map((p) => p is Map && p['text'] is String ? p['text'] as String : '').join()
              : '')
          .trim(),
      inputTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
      // OpenRouter reports what the call cost, in dollars.
      cost: (u['cost'] as num?)?.toDouble(),
      model: j['model'] is String ? j['model'] as String : null,
    );
  }

  static bool _modelMissing(String detail) => RegExp(
    r'not a valid model|no endpoints found|model.{0,40}(not (found|exist|available)|does not exist)',
    caseSensitive: false,
  ).hasMatch(detail);

  /// Turns an HTTP error into a plain sentence. [keyCheck] is for calls that send no model.
  static AiException errorFor(AiProvider p, int status, String body, String model, {bool keyCheck = false}) {
    String detail = '';
    try {
      final j = jsonDecode(body);
      final e = j is Map ? j['error'] : null;
      detail =
          (e is Map
                  ? e['message']
                  : e is String
                  ? e
                  : null)
              ?.toString() ??
          '';
    } catch (_) {}
    final name = p.label;
    if (!keyCheck && (status == 400 || status == 404) && (status == 404 || _modelMissing(detail))) {
      return AiException('Model "$model" is not available on $name. Pick another one in AI settings.', status: 404);
    }
    final msg = switch (status) {
      401 => '$name did not accept this key. Check it and paste it again.',
      403 when p == AiProvider.openrouter && detail.isNotEmpty => '$name: $detail',
      403 => '$name did not accept this key. Check it and paste it again.',
      402 => 'Your $name account has no credit left. Top it up on their site.',
      408 => '$name took too long to answer. Try again.',
      429 => '$name says too many requests, or your credit has run out. Wait a minute, or check your balance.',
      404 => '$name could not find that. Try again later.',
      400 => detail.isEmpty ? '$name could not use this request.' : '$name: $detail',
      >= 500 => '$name is busy or down right now. Try again in a minute.',
      _ => detail.isEmpty ? '$name answered with error $status.' : '$name: $detail',
    };
    return AiException(msg, status: status);
  }
}
