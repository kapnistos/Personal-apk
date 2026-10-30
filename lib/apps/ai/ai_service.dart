import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/settings.dart';

/// The companies Hub can call with your own key.
enum AiProvider {
  anthropic('Anthropic'),
  openai('OpenAI'),
  deepseek('DeepSeek'),
  llama('Llama');

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
  const AiReply(this.text, {this.inputTokens = 0, this.outputTokens = 0});
  final String text;
  final int inputTokens;
  final int outputTokens;

  String get usage => '$inputTokens in, $outputTokens out tokens';
}

/// A failed call, with a message fit to show as is.
class AiException implements Exception {
  const AiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
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

  /// 'plan' hands work to the Claude app; 'api' calls the provider on your key.
  static const billing = 'ai.billing';
  static const llamaUrl = 'ai.llama.url';
  static String modelIdKey(String modelId) => 'ai.modelid.$modelId';
  static const defaultLlamaUrl = 'https://api.groq.com/openai/v1';
}

/// Everything needed to call a model, built from settings and the keystore.
class AiSetup {
  AiSetup(this.settings, {AiKeyStore? keys, this.httpClient}) : keys = keys ?? store;

  /// Swapped for a memory store in tests.
  static AiKeyStore store = const SecureAiKeyStore();

  final AppSettings settings;
  final AiKeyStore keys;
  final http.Client? httpClient;
  late final http.Client client = httpClient ?? newClient();

  /// Swapped for a MockClient in tests.
  static http.Client Function() newClient = http.Client.new;

  AiModel get model => aiModelById(settings.raw(AiSettings.model));
  bool get useApi => settings.raw(AiSettings.billing) == 'api';
  String modelIdFor(AiModel m) {
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

  /// True when calls can go straight to the provider: API mode with a key (or a keyless Llama).
  Future<bool> apiReady() async => useApi && (model.provider.keyOptional || (await keyFor(model.provider)).isNotEmpty);

  /// Sends [messages] to the chosen model.
  Future<AiReply> ask(List<AiMessage> messages, {String? system, int maxTokens = 2048}) async {
    final m = model;
    return AiClient(client).chat(
      provider: m.provider,
      apiKey: await keyFor(m.provider),
      model: modelIdFor(m),
      messages: messages,
      system: system,
      baseUrl: m.provider == AiProvider.llama ? llamaUrl : null,
      maxTokens: maxTokens,
    );
  }

  /// A tiny call to check the key works.
  Future<AiReply> testKey(AiProvider p, String key) {
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
}

/// Raw HTTP calls to each provider.
class AiClient {
  AiClient(this.client, {this.timeout = const Duration(seconds: 90)});
  final http.Client client;
  final Duration timeout;

  static Uri endpoint(AiProvider p, {String? baseUrl}) => switch (p) {
    AiProvider.anthropic => Uri.parse('https://api.anthropic.com/v1/messages'),
    AiProvider.openai => Uri.parse('https://api.openai.com/v1/chat/completions'),
    AiProvider.deepseek => Uri.parse('https://api.deepseek.com/chat/completions'),
    AiProvider.llama => Uri.parse(
      '${(baseUrl ?? AiSettings.defaultLlamaUrl).trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    ),
  };

  Future<AiReply> chat({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    String? system,
    String? baseUrl,
    int maxTokens = 2048,
  }) async {
    if (apiKey.isEmpty && !provider.keyOptional) {
      throw AiException('Add your ${provider.label} key first.');
    }
    final anthropic = provider == AiProvider.anthropic;
    final headers = {
      'content-type': 'application/json',
      if (anthropic) ...{'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      if (!anthropic && apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
    };
    final msgs = [
      for (final m in messages) {'role': m.role, 'content': m.content},
    ];
    final body = anthropic
        ? {
            'model': model,
            'max_tokens': maxTokens,
            if (system != null && system.isNotEmpty) 'system': system,
            'messages': msgs,
          }
        : {
            'model': model,
            'messages': [
              if (system != null && system.isNotEmpty) {'role': 'system', 'content': system},
              ...msgs,
            ],
          };
    final Uri url;
    try {
      url = endpoint(provider, baseUrl: baseUrl);
    } on FormatException {
      throw const AiException('That server address does not look right. Check it under Advanced.');
    }
    http.Response res;
    try {
      res = await client.post(url, headers: headers, body: jsonEncode(body)).timeout(timeout);
    } on TimeoutException {
      throw AiException('${provider.label} took too long to answer. Try again.');
    } on http.ClientException {
      throw const AiException('No connection. Check your internet and try again.');
    } catch (e) {
      // SocketException and friends on some platforms.
      throw const AiException('No connection. Check your internet and try again.');
    }
    if (res.statusCode != 200) throw errorFor(provider, res.statusCode, utf8.decode(res.bodyBytes), model);
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('${provider.label} sent an answer Hub could not read.');
    }
    return anthropic ? parseAnthropic(j) : parseOpenAi(j);
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
    return AiReply(
      (msg?['content'] as String? ?? '').trim(),
      inputTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  /// Turns an HTTP error into a plain sentence.
  static AiException errorFor(AiProvider p, int status, String body, String model) {
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
    final msg = switch (status) {
      401 || 403 => '$name did not accept this key. Check it and try again.',
      402 => 'Your $name account has no credit left. Top it up on their site.',
      429 => '$name says too many requests, or your credit has run out. Wait a minute, or check your balance.',
      404 => 'Model "$model" was not found. Check the model id under Advanced.',
      400 => detail.isEmpty ? '$name could not use this request.' : '$name: $detail',
      >= 500 => '$name is busy or down right now. Try again in a minute.',
      _ => detail.isEmpty ? '$name answered with error $status.' : '$name: $detail',
    };
    return AiException(msg, status: status);
  }
}
