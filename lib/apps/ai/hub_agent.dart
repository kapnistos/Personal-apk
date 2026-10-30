import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../shopping/shopping_model.dart';
import '../wallet/wallet_model.dart';

String _categories() {
  String names(EntryKind k) => categoriesByKind[k]!.map((c) => c.name).join(', ');
  return 'Expense categories: ${names(EntryKind.expense)}.\n'
      'Income categories: ${names(EntryKind.income)}.\n'
      'Recurring payment categories: ${names(EntryKind.subscription)}.';
}

/// How the agent talks: plain, short, like a friend who keeps your diary, not a chatbot.
const _voice =
    'Write like a capable friend: short, warm and plain. No headings, no "As an AI", no filler. '
    'Use a short list only when it really helps (a schedule, a few amounts). Use the user\'s own words '
    'for things, and real dates ("Sat 1 Nov") rather than offsets.';

/// What the Hub agent is told when it can call tools to read the app and propose changes.
String agentToolPrompt(DateTime now, {String currency = 'EUR'}) {
  final day = DateFormat('EEEE d MMMM y, HH:mm').format(now);
  return '''
You are the Hub agent inside the user's personal app. It holds their calendar (including imported calendars, repeating and all-day events), to-dos, notes, wallet (accounts, every transaction, recurring payments and subscriptions, budgets, savings, investments), habits, shopping list, spaces (university, job, research) with their important dates and work log, internship applications, and weather.
Now: $day. Money is in $currency unless the user says otherwise.

You can read all of it with the get_ and search_ tools. Always look before you answer a question about the user's data, and never say something is empty without checking with a tool first. For "the next days" or "this week" read the calendar for that whole range. For subscriptions or bills read get_recurring.

To change something, call a propose_ tool for each change. Each becomes a card, and nothing is saved until the user taps Add, so say "here it is to add" rather than "done". Only propose what the user asked for.
${_categories()}

$_voice''';
}

/// What the Hub agent is told when its model cannot call tools: the data comes in the prompt and
/// changes come back as JSON.
String agentSystemPrompt(DateTime now) {
  final day = DateFormat('EEEE d MMMM y').format(now);
  final iso = DateFormat('yyyy-MM-dd').format(now);
  return '''
You are the Hub agent inside a personal app with money, notes, tasks, a calendar, habits, spaces and a shopping list.
Today is $day ($iso). Amounts are in euro unless the user says otherwise.

Reply with JSON only, no other text, in this shape:
{"reply": "short answer for the user", "actions": [ ... ]}

Each action is one of:
{"type": "expense", "amount": 12.5, "category": "Eating out", "note": "lunch", "date": "$iso"}
{"type": "income", "amount": 100, "category": "Freelance", "note": "", "date": "$iso"}
{"type": "note", "title": "Landlord", "body": "Call the landlord"}
{"type": "task", "title": "Call the landlord", "due": "$iso", "important": false}
{"type": "complete", "id": 12, "title": "Call the landlord"}
{"type": "event", "title": "Dentist", "start": "${iso}T14:00", "end": "${iso}T15:00", "allDay": false, "location": ""}
{"type": "shopping", "name": "milk", "quantity": "2"}
{"type": "recurring", "name": "Netflix", "amount": 13.99, "kind": "payment", "category": "Streaming", "period": 1, "next": "$iso"}

${_categories()}
Only add actions the user asked for. Leave "actions" empty when the user only asks a question.
Dates are YYYY-MM-DD, times are 24 hour. "due" and "date" may be left out.
The user's data is below, when they share it. Answer from it; if something is not there, say so plainly.
In "reply": $_voice''';
}

/// One change the agent proposes. Nothing is saved until the user taps Add.
class AgentAction {
  AgentAction(this.type, this.fields);
  final String type;
  final Map<String, dynamic> fields;

  static const types = {'expense', 'income', 'note', 'task', 'event', 'shopping', 'recurring', 'complete'};

  String _s(String k) => (fields[k] ?? '').toString().trim();
  double? get amount {
    final v = fields['amount'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '.') ?? '');
  }

  int get cents => ((amount ?? 0).abs() * 100).round();
  String get title => _s('title');
  String get name => _s('name');
  DateTime? date(String k) => DateTime.tryParse(_s(k));
  int? get taskId => fields['id'] is num ? (fields['id'] as num).toInt() : int.tryParse(_s('id'));
  int get period {
    final v = fields['period'];
    final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return n == null || n < 1 ? 1 : n;
  }

  EntryKind get recurringKind => _s('kind').toLowerCase() == 'income' ? EntryKind.income : EntryKind.subscription;

  /// Actions missing what they need are dropped.
  bool get valid => switch (type) {
    'expense' || 'income' => cents > 0,
    'note' => title.isNotEmpty || _s('body').isNotEmpty,
    'task' => title.isNotEmpty,
    'complete' => taskId != null || title.isNotEmpty,
    'event' => title.isNotEmpty && date('start') != null,
    'shopping' => name.isNotEmpty,
    'recurring' => name.isNotEmpty && cents > 0,
    _ => false,
  };

  String category(EntryKind kind) {
    final want = _s('category').toLowerCase();
    final cats = categoriesByKind[kind]!;
    return cats.firstWhere((c) => c.name.toLowerCase() == want, orElse: () => cats.last).name;
  }

  /// A short line for the card.
  String get summary {
    String money() => '€${(cents / 100).toStringAsFixed(2)}';
    final note = _s('note');
    return switch (type) {
      'expense' => '${money()} on ${category(EntryKind.expense)}${note.isEmpty ? '' : ', $note'}',
      'income' => '${money()} in, ${category(EntryKind.income)}${note.isEmpty ? '' : ', $note'}',
      'note' => title.isEmpty ? _s('body') : title,
      'task' => '$title${date('due') == null ? '' : ', due ${DateFormat('d MMM').format(date('due')!)}'}',
      'complete' => title.isEmpty ? 'Task $taskId' : title,
      'event' =>
        '$title, ${DateFormat(fields['allDay'] == true ? 'EEE d MMM' : 'EEE d MMM HH:mm').format(date('start')!)}',
      'shopping' => _s('quantity').isEmpty ? name : '$name (${_s('quantity')})',
      'recurring' =>
        '$name, ${money()} ${period == 1 ? 'a month' : 'every $period months'}'
            '${date('next') == null ? '' : ', next ${DateFormat('d MMM').format(date('next')!)}'}',
      _ => type,
    };
  }

  String get label => switch (type) {
    'expense' => 'Expense',
    'income' => 'Income',
    'note' => 'Note',
    'task' => 'Task',
    'complete' => 'Mark done',
    'event' => 'Event',
    'shopping' => 'Shopping',
    'recurring' => recurringKind == EntryKind.income ? 'Recurring income' : 'Recurring payment',
    _ => type,
  };

  /// What the confirm button says.
  String get verb => type == 'complete' ? 'Done' : 'Add';

  Map<String, dynamic> toJson() => {'type': type, ...fields};

  static AgentAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = (j['type'] ?? '').toString().toLowerCase();
    if (!types.contains(type)) return null;
    final a = AgentAction(type, Map<String, dynamic>.from(j)..remove('type'));
    return a.valid ? a : null;
  }

  /// Writes the action with the app's own database methods.
  Future<void> apply(AppDatabase db, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    switch (type) {
      case 'expense' || 'income':
        final kind = type == 'expense' ? EntryKind.expense : EntryKind.income;
        await db.addEntry(
          EntriesCompanion(
            amountCents: Value(cents),
            kind: Value(kind),
            category: Value(category(kind)),
            note: Value(_s('note')),
            account: Value(_s('account')),
            date: Value(date('date') ?? today),
          ),
        );
      case 'note':
        final body = _s('body');
        await db.saveNote(title: title, body: body.isEmpty ? title : body);
      case 'task':
        await db.addTodo(title, due: date('due'), important: fields['important'] == true);
      case 'complete':
        var id = taskId;
        if (id == null || await db.todoById(id) == null) {
          final want = title.toLowerCase();
          final open = (await db.watchTodos().first).where((t) => !t.done && t.title.toLowerCase() == want);
          id = open.firstOrNull?.id;
        }
        if (id == null) throw StateError('No such task');
        await db.setTodoDone(id, true);
      case 'event':
        final start = date('start')!;
        final allDay = fields['allDay'] == true;
        var end = date('end');
        if (end == null || !end.isAfter(start)) {
          end = allDay ? DateTime(start.year, start.month, start.day + 1) : start.add(const Duration(hours: 1));
        }
        final cal = (await db.watchCalendars().first).first;
        await db.saveEvent(
          EventsCompanion(
            calendarId: Value(cal.id),
            title: Value(title),
            location: Value(_s('location')),
            start: Value(allDay ? DateTime(start.year, start.month, start.day) : start),
            end: Value(end),
            allDay: Value(allDay),
          ),
        );
      case 'shopping':
        await db.addShoppingItem(name, quantity: _s('quantity'), category: categorize(name));
      case 'recurring':
        final kind = recurringKind;
        var next = date('next') ?? dateOnly(today);
        if (next.isBefore(dateOnly(today))) next = dateOnly(today);
        await db.saveSubscription(
          SubscriptionsCompanion.insert(
            name: name,
            amountCents: cents,
            kind: kind,
            category: category(kind),
            account: Value(_s('account')),
            periodMonths: Value(period),
            nextDate: next,
          ),
        );
    }
  }
}

class AgentReply {
  const AgentReply(this.reply, this.actions);
  final String reply;
  final List<AgentAction> actions;
}

/// Reads the model's answer. Code fences and text around the JSON are ignored;
/// if there is no JSON at all, the whole answer is shown as the reply.
AgentReply parseAgentReply(String raw) {
  final text = raw.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final j = jsonDecode(text.substring(start, end + 1));
      if (j is Map) {
        final actions = <AgentAction>[];
        final list = j['actions'];
        if (list is List) {
          for (final a in list) {
            final action = AgentAction.fromJson(a);
            if (action != null) actions.add(action);
          }
        }
        final reply = (j['reply'] ?? '').toString().trim();
        return AgentReply(reply.isEmpty && actions.isNotEmpty ? 'Here is what I can add:' : reply, actions);
      }
    } catch (_) {}
  }
  return AgentReply(text, const []);
}
