import 'dart:convert';

import '../../core/db/database.dart';
import '../../core/settings.dart';

/// Tokens and cost added up for some stretch of time.
class UsageTotal {
  int inputTokens = 0;
  int outputTokens = 0;
  int calls = 0;

  /// US dollars for the calls whose price is known.
  double cost = 0;

  /// Calls with no known price (Claude Code, direct keys, Auto without a price).
  int unpriced = 0;

  int get tokens => inputTokens + outputTokens;
  bool get priced => calls > unpriced;

  void add(int i, int o, double? c, int n, int u) {
    inputTokens += i;
    outputTokens += o;
    calls += n;
    cost += c ?? 0;
    unpriced += u;
  }
}

/// What every AI answer used, by day and model, in one raw setting so it survives restarts and
/// travels in backups. Shape: {"2026-10-30": {"model id": [in, out, dollars, calls, unpriced calls]}}.
class AiUsage {
  AiUsage(this.settings);
  final AppSettings settings;
  static const key = 'ai.usage';

  Map<String, Map<String, List<num>>> _read() {
    final s = settings.raw(key);
    if (s == null || s.isEmpty) return {};
    try {
      final j = jsonDecode(s);
      if (j is! Map) return {};
      return {
        for (final d in j.entries)
          if (d.value is Map)
            '${d.key}': {
              for (final m in (d.value as Map).entries)
                if (m.value is List && (m.value as List).length >= 5)
                  '${m.key}': [for (final v in m.value as List) v is num ? v : 0],
            },
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> record(String model, int inputTokens, int outputTokens, double? cost, {DateTime? at}) async {
    if (inputTokens == 0 && outputTokens == 0 && cost == null) return;
    final data = _read();
    final day = AppDatabase.dayKey(at ?? DateTime.now());
    final row = (data[day] ??= {})[model] ??= [0, 0, 0, 0, 0];
    row[0] += inputTokens;
    row[1] += outputTokens;
    row[2] += cost ?? 0;
    row[3] += 1;
    if (cost == null) row[4] += 1;
    await settings.setRaw(key, jsonEncode(data), quiet: true);
  }

  /// Totals over days from [from] (inclusive) to [to] (exclusive); all time when both are null.
  UsageTotal total({DateTime? from, DateTime? to}) => _sum(from, to).$1;

  /// The same, split by model, biggest first.
  List<(String, UsageTotal)> byModel({DateTime? from, DateTime? to}) {
    final list = _sum(from, to).$2.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.tokens.compareTo(a.$2.tokens));
    return list;
  }

  (UsageTotal, Map<String, UsageTotal>) _sum(DateTime? from, DateTime? to) {
    final f = from == null ? null : AppDatabase.dayKey(from);
    final t = to == null ? null : AppDatabase.dayKey(to);
    final all = UsageTotal();
    final models = <String, UsageTotal>{};
    for (final d in _read().entries) {
      if (f != null && d.key.compareTo(f) < 0) continue;
      if (t != null && d.key.compareTo(t) >= 0) continue;
      for (final m in d.value.entries) {
        final v = m.value;
        final c = v[2].toDouble();
        all.add(v[0].toInt(), v[1].toInt(), c, v[3].toInt(), v[4].toInt());
        (models[m.key] ??= UsageTotal()).add(v[0].toInt(), v[1].toInt(), c, v[3].toInt(), v[4].toInt());
      }
    }
    return (all, models);
  }

  Future<void> reset() => settings.setRaw(key, '');
}

/// "850", "12.4K", "1.2M".
String formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
  return '${(n / 1000000).toStringAsFixed(n < 10000000 ? 2 : 1)}M';
}

/// "$0.42", "$0.0031", "under $0.0001".
String formatUsd(double v) {
  if (v == 0) return r'$0';
  if (v < 0.0001) return r'under $0.0001';
  if (v < 0.01) return '\$${v.toStringAsFixed(4)}';
  if (v < 100) return '\$${v.toStringAsFixed(2)}';
  return '\$${v.round()}';
}
