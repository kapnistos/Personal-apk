import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../calendar/calendar_model.dart' show Occurrence, expand;
import '../wallet/wallet_model.dart';

/// One saved line of a conversation. API keys never pass through here.
class SavedTurn {
  const SavedTurn(this.role, this.text, {this.raw, this.error = false});
  final String role; // user, assistant or note
  final String text;

  /// What the model actually sent, when it differs from [text] (agent JSON).
  final String? raw;
  final bool error;

  Map<String, dynamic> toJson() => {
    'r': role,
    't': text,
    if (raw != null && raw != text) 'x': raw,
    if (error) 'e': true,
  };

  static SavedTurn? fromJson(Object? j) {
    if (j is! Map) return null;
    final role = j['r'], text = j['t'];
    if (role is! String || text is! String) return null;
    final raw = j['x'];
    return SavedTurn(role, text, raw: raw is String ? raw : null, error: j['e'] == true);
  }
}

/// Keeps the last [limit] turns of each chat mode in a raw setting, so a chat
/// is still there when you come back.
class ChatMemory {
  ChatMemory(this.settings);
  final AppSettings settings;
  static const limit = 50;

  static String keyFor(bool agent) => agent ? 'ai.history.agent' : 'ai.history.chat';

  /// Whether the chat may see a short summary of today (tasks, events, spending).
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

  List<SavedTurn> load(bool agent) => decode(settings.raw(keyFor(agent)));
  Future<void> save(bool agent, List<SavedTurn> turns) => settings.setRaw(keyFor(agent), encode(turns), quiet: true);
  Future<void> clear(bool agent) => settings.setRaw(keyFor(agent), '', quiet: true);
}

/// Ready-made questions shown on an empty chat.
const chatSuggestions = ['Plan my day', 'What did I spend this week?', 'Summarise my notes'];
const agentSuggestions = ['12 euro lunch', 'Dentist Friday at 2', 'Buy milk and eggs'];

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
