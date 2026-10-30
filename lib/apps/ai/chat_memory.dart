import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../calendar/calendar_model.dart' show Occurrence, expand;
import '../wallet/wallet_model.dart';

/// One saved line of a conversation. API keys never pass through here.
class SavedTurn {
  const SavedTurn(
    this.role,
    this.text, {
    this.raw,
    this.error = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost,
    this.model,
    this.tools = const [],
    this.actions = const [],
    this.done = const {},
    this.at,
  });
  final String role; // user, assistant or note
  final String text;

  /// What the model actually sent, when it differs from [text] (agent JSON).
  final String? raw;
  final bool error;
  final int inputTokens;
  final int outputTokens;

  /// US dollars, when known.
  final double? cost;
  final String? model;

  /// What the model looked at on the way (tool names).
  final List<String> tools;

  /// Proposed changes, as their JSON, and which were added or skipped (index to 'added' or 'skipped').
  final List<Map<String, dynamic>> actions;
  final Map<int, String> done;
  final DateTime? at;

  int get tokens => inputTokens + outputTokens;

  Map<String, dynamic> toJson() => {
    'r': role,
    't': text,
    if (raw != null && raw != text) 'x': raw,
    if (error) 'e': true,
    if (inputTokens > 0) 'i': inputTokens,
    if (outputTokens > 0) 'o': outputTokens,
    if (cost != null) 'c': cost,
    if (model != null) 'm': model,
    if (tools.isNotEmpty) 'k': tools,
    if (actions.isNotEmpty) 'a': actions,
    if (done.isNotEmpty) 'd': {for (final e in done.entries) '${e.key}': e.value},
    if (at != null) 'at': at!.toIso8601String(),
  };

  static SavedTurn? fromJson(Object? j) {
    if (j is! Map) return null;
    final role = j['r'], text = j['t'];
    if (role is! String || text is! String) return null;
    final raw = j['x'];
    final d = j['d'];
    return SavedTurn(
      role,
      text,
      raw: raw is String ? raw : null,
      error: j['e'] == true,
      inputTokens: (j['i'] as num?)?.toInt() ?? 0,
      outputTokens: (j['o'] as num?)?.toInt() ?? 0,
      cost: (j['c'] as num?)?.toDouble(),
      model: j['m'] is String ? j['m'] as String : null,
      tools: [for (final k in (j['k'] is List ? j['k'] as List : const [])) ?(k is String ? k : null)],
      actions: [
        for (final a in (j['a'] is List ? j['a'] as List : const []))
          if (a is Map) a.cast<String, dynamic>(),
      ],
      done: {
        if (d is Map)
          for (final e in d.entries)
            if (int.tryParse('${e.key}') != null && e.value is String) int.parse('${e.key}'): e.value as String,
      },
      at: DateTime.tryParse('${j['at'] ?? ''}'),
    );
  }
}

/// One saved conversation in Chat or the Hub agent.
class Conversation {
  Conversation({
    required this.id,
    required this.agent,
    this.title = '',
    required this.created,
    required this.updated,
    List<SavedTurn>? turns,
  }) : turns = turns ?? [];

  final String id;
  final bool agent;

  /// Set by the user; empty means it is named after its first question.
  String title;
  final DateTime created;
  DateTime updated;
  List<SavedTurn> turns;

  String get name => title.trim().isNotEmpty ? title.trim() : autoTitle(turns);

  int get inputTokens => turns.fold(0, (a, t) => a + t.inputTokens);
  int get outputTokens => turns.fold(0, (a, t) => a + t.outputTokens);
  double? get cost {
    final priced = turns.where((t) => t.cost != null);
    return priced.isEmpty ? null : priced.fold<double>(0, (a, t) => a + t.cost!);
  }

  /// The first question, cut to a title.
  static String autoTitle(List<SavedTurn> turns) {
    final first = turns.where((t) => t.role == 'user').firstOrNull?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (first == null || first.isEmpty) return 'New chat';
    if (first.length <= 48) return first[0].toUpperCase() + first.substring(1);
    final cut = first.substring(0, 48);
    final space = cut.lastIndexOf(' ');
    return '${first[0].toUpperCase()}${cut.substring(1, space > 24 ? space : 48)}…';
  }

  /// The last thing said, for the list.
  String get preview {
    final t = turns.lastWhere((t) => t.role != 'note' && t.text.isNotEmpty, orElse: () => const SavedTurn('', ''));
    return t.text.replaceAll(RegExp(r'[*_#`>]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Map<String, dynamic> meta() => {
    'id': id,
    'a': agent,
    if (title.isNotEmpty) 't': title,
    'c': created.toIso8601String(),
    'u': updated.toIso8601String(),
    'n': turns.where((t) => t.role != 'note').length,
    'p': preview.length > 120 ? preview.substring(0, 120) : preview,
    'q': name,
    'i': inputTokens,
    'o': outputTokens,
    if (cost != null) r'$': cost,
  };
}

/// What the history list shows for one conversation, without loading its turns.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.agent,
    required this.name,
    required this.preview,
    required this.created,
    required this.updated,
    this.messages = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost,
    this.customTitle = '',
  });
  final String id;
  final bool agent;
  final String name;
  final String preview;
  final DateTime created;
  final DateTime updated;
  final int messages;
  final int inputTokens;
  final int outputTokens;
  final double? cost;
  final String customTitle;

  int get tokens => inputTokens + outputTokens;

  static ChatSummary? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final created = DateTime.tryParse('${j['c']}') ?? DateTime.now();
    return ChatSummary(
      id: j['id'] as String,
      agent: j['a'] == true,
      name: (j['q'] as String?) ?? (j['t'] as String?) ?? 'New chat',
      customTitle: (j['t'] as String?) ?? '',
      preview: (j['p'] as String?) ?? '',
      created: created,
      updated: DateTime.tryParse('${j['u']}') ?? created,
      messages: (j['n'] as num?)?.toInt() ?? 0,
      inputTokens: (j['i'] as num?)?.toInt() ?? 0,
      outputTokens: (j['o'] as num?)?.toInt() ?? 0,
      cost: (j[r'$'] as num?)?.toDouble(),
    );
  }
}

/// Saved conversations for both modes, kept in raw settings so they survive restarts and travel in
/// backups: an index under [indexKey] and each conversation's turns under [turnsKey].
///
/// Before there was a list, each mode kept one chat under [legacyKey]; that chat (also from an old
/// backup put back later) becomes a conversation in the list the next time the list is read.
class ChatMemory {
  ChatMemory(this.settings);
  final AppSettings settings;

  /// Turns kept per conversation.
  static const limit = 200;

  /// Conversations kept per mode; the oldest go first.
  static const maxConversations = 150;

  static const indexKey = 'ai.chats';
  static String turnsKey(String id) => 'ai.chat.$id';
  static String currentKey(bool agent) => agent ? 'ai.chat.current.agent' : 'ai.chat.current.chat';
  static String legacyKey(bool agent) => agent ? 'ai.history.agent' : 'ai.history.chat';

  /// Whether Chat may read the user's Hub (the Hub agent always can).
  static const contextKey = 'ai.context';
  bool get shareContext => settings.raw(contextKey) == 'on';
  Future<void> setShareContext(bool on) => settings.setRaw(contextKey, on ? 'on' : 'off');

  static String encode(List<SavedTurn> turns) {
    final keep = turns.length > limit ? turns.sublist(turns.length - limit) : turns;
    return jsonEncode([for (final t in keep) t.toJson()]);
  }

  static List<SavedTurn> decode(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      final j = jsonDecode(s);
      if (j is! List) return [];
      return [for (final x in j) ?SavedTurn.fromJson(x)];
    } catch (_) {
      return [];
    }
  }

  static final _rand = math.Random();
  static String newId(DateTime at) =>
      '${at.microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  List<Map<String, dynamic>> _index() {
    final s = settings.raw(indexKey);
    if (s == null || s.isEmpty) return [];
    try {
      final j = jsonDecode(s);
      return j is List
          ? [
              for (final x in j)
                if (x is Map && x['id'] is String) x.cast<String, dynamic>(),
            ]
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Map<String, dynamic>> rows) => settings.setRaw(indexKey, jsonEncode(rows));

  /// Turns the single chat kept by older versions (or an old backup) into a conversation in the list.
  Future<void> migrate({DateTime? now}) async {
    final pending = <Future<void>>[];
    for (final agent in [false, true]) {
      final old = settings.raw(legacyKey(agent));
      if (old == null || old.isEmpty) continue;
      final turns = decode(old);
      if (turns.isNotEmpty) {
        final at = now ?? DateTime.now();
        final c = Conversation(id: newId(at), agent: agent, created: at, updated: at, turns: turns);
        pending.add(save(c));
        if (currentId(agent) == null) pending.add(setCurrent(agent, c.id));
      }
      pending.add(settings.setRaw(legacyKey(agent), '', quiet: true));
    }
    await Future.wait(pending);
  }

  /// Saved conversations, newest first. Both modes unless [agent] is given.
  List<ChatSummary> list({bool? agent}) {
    final out = [for (final r in _index()) ?ChatSummary.fromJson(r)]
      ..retainWhere((c) => agent == null || c.agent == agent)
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  Conversation? open(String id) {
    final meta = _index().where((r) => r['id'] == id).firstOrNull;
    final s = meta == null ? null : ChatSummary.fromJson(meta);
    if (s == null) return null;
    return Conversation(
      id: id,
      agent: s.agent,
      title: s.customTitle,
      created: s.created,
      updated: s.updated,
      turns: decode(settings.raw(turnsKey(id))),
    );
  }

  /// The conversation each mode shows when it opens; null for a fresh one.
  String? currentId(bool agent) {
    final id = settings.raw(currentKey(agent));
    if (id == null || id.isEmpty) return null;
    return _index().any((r) => r['id'] == id) ? id : null;
  }

  Future<void> setCurrent(bool agent, String? id) => settings.setRaw(currentKey(agent), id ?? '', quiet: true);

  Conversation? current(bool agent) {
    final id = currentId(agent);
    return id == null ? null : open(id);
  }

  /// The current conversation's turns; empty for a fresh chat.
  List<SavedTurn> load(bool agent) => current(agent)?.turns ?? [];

  /// Starts a fresh chat in [agent]'s mode. The old one stays in the list.
  Future<void> clear(bool agent) => setCurrent(agent, null);

  /// Saves a conversation and puts it at the top of the list. An empty one is not listed.
  Future<void> save(Conversation c) async {
    final pending = <Future<void>>[];
    final rows = _index()..removeWhere((r) => r['id'] == c.id);
    if (c.turns.isEmpty) {
      pending.add(settings.setRaw(turnsKey(c.id), '', quiet: true));
      pending.add(_writeIndex(rows));
      await Future.wait(pending);
      return;
    }
    pending.add(settings.setRaw(turnsKey(c.id), encode(c.turns), quiet: true));
    rows.insert(0, c.meta());
    // Keep the newest per mode.
    final mine = rows.where((r) => (r['a'] == true) == c.agent).toList();
    if (mine.length > maxConversations) {
      mine.sort((a, b) => '${b['u']}'.compareTo('${a['u']}'));
      for (final old in mine.skip(maxConversations)) {
        rows.remove(old);
        pending.add(settings.setRaw(turnsKey(old['id'] as String), '', quiet: true));
      }
    }
    pending.add(_writeIndex(rows));
    await Future.wait(pending);
  }

  Future<void> rename(String id, String title) async {
    final c = open(id);
    if (c == null) return;
    c.title = title.trim();
    final rows = _index();
    final i = rows.indexWhere((r) => r['id'] == id);
    if (i < 0) return;
    rows[i] = c.meta();
    await _writeIndex(rows);
  }

  /// Deletes a conversation and returns it, so the caller can offer Undo with [restore].
  Future<Conversation?> delete(String id) async {
    final pending = <Future<void>>[];
    final c = open(id);
    final rows = _index()..removeWhere((r) => r['id'] == id);
    pending.add(settings.setRaw(turnsKey(id), '', quiet: true));
    pending.add(_writeIndex(rows));
    for (final agent in [false, true]) {
      if (settings.raw(currentKey(agent)) == id) pending.add(setCurrent(agent, null));
    }
    await Future.wait(pending);
    return c;
  }

  Future<void> restore(Conversation c) async {
    final pending = <Future<void>>[];
    final rows = _index()..removeWhere((r) => r['id'] == c.id);
    pending.add(settings.setRaw(turnsKey(c.id), encode(c.turns), quiet: true));
    rows.add(c.meta());
    pending.add(_writeIndex(rows));
    await Future.wait(pending);
  }
}

/// Ready-made questions shown on an empty chat.
const chatSuggestions = ['Plan my day', 'What did I spend this week?', 'Summarise my notes'];
const agentSuggestions = ['What\'s on the next few days?', 'My subscriptions', '12 euro lunch', 'Buy milk and eggs'];

/// A compact picture of today from your own data, for the model to answer with.
Future<String> hubContext(AppDatabase db, {DateTime? now, String currency = 'EUR'}) async {
  final n = now ?? DateTime.now();
  final today = dateOnly(n);
  final tomorrow = addDays(today, 1);
  String eur(int c) => money(c, currency);
  final lines = <String>['Today is ${DateFormat('EEEE d MMMM y, HH:mm').format(n)}.'];

  final todos = (await db.watchTodos().first).where((t) => !t.done).toList();
  final dueToday = todos.where((t) => t.due != null && dateOnly(t.due!) == today).toList();
  final overdue = todos.where((t) => t.due != null && t.due!.isBefore(today)).toList();
  final undated = todos.where((t) => t.due == null).take(5).toList();
  String titles(List<Todo> l) => l.take(8).map((t) => t.important ? '${t.title} (important)' : t.title).join('; ');
  if (dueToday.isNotEmpty) lines.add('Tasks due today: ${titles(dueToday)}.');
  if (overdue.isNotEmpty) lines.add('Overdue tasks: ${titles(overdue)}.');
  if (undated.isNotEmpty) lines.add('Other open tasks: ${titles(undated)}.');
  if (todos.isEmpty) lines.add('No open tasks.');

  final cals = {for (final c in await db.watchCalendars().first) c.id: c};
  final events = expand(await db.watchEventsBetween(today, addDays(today, 2)).first, cals, today, addDays(today, 2))
    ..sort((a, b) => a.start.compareTo(b.start));
  String ev(Occurrence o) =>
      o.allDay ? '${o.event.title} (all day)' : '${DateFormat.Hm().format(o.start)} ${o.event.title}';
  final todayEvents = events.where((o) => o.touches(today)).toList();
  final tomorrowEvents = events.where((o) => o.touches(tomorrow) && !o.touches(today)).toList();
  lines.add(todayEvents.isEmpty ? 'No events today.' : 'Events today: ${todayEvents.take(10).map(ev).join('; ')}.');
  if (tomorrowEvents.isNotEmpty) lines.add('Tomorrow: ${tomorrowEvents.take(6).map(ev).join('; ')}.');

  final monthStart = DateTime(n.year, n.month);
  final weekStart = addDays(today, 1 - today.weekday);
  final entries = (await db.watchEntries(monthStart.isBefore(weekStart) ? monthStart : weekStart, tomorrow).first)
      .where((e) => !e.date.isAfter(n))
      .toList();
  final month = MonthSummary(entries.where((e) => !e.date.isBefore(monthStart)).toList());
  final week = MonthSummary(entries.where((e) => !e.date.isBefore(weekStart)).toList());
  final top = month.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  lines.add(
    'Spent this week (since Monday): ${eur(week.out)}. Spent this month: ${eur(month.out)}, income ${eur(month.income)}'
    '${top.isEmpty ? '' : '. Top: ${top.take(4).map((e) => '${e.key} ${eur(e.value)}').join(', ')}'}.',
  );

  final notes =
      await (db.select(db.notes)
            ..orderBy([(x) => OrderingTerm.desc(x.updatedAt)])
            ..limit(8))
          .get();
  if (notes.isNotEmpty) {
    String one(Note x) {
      final body = x.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final head = x.title.isEmpty ? '' : '${x.title}: ';
      return '- $head${body.length > 160 ? '${body.substring(0, 160)}...' : body}';
    }

    lines.add('Recent notes:\n${notes.take(8).map(one).join('\n')}');
  }
  return lines.join('\n');
}
