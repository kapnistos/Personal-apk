import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../shopping/shopping_model.dart';
import '../wallet/wallet_model.dart';

/// What the Hub agent asks the model to do.
String agentSystemPrompt(DateTime now) {
  final day = DateFormat('EEEE d MMMM y').format(now);
  final iso = DateFormat('yyyy-MM-dd').format(now);
  final expense = categoriesByKind[EntryKind.expense]!.map((c) => c.name).join(', ');
  final income = categoriesByKind[EntryKind.income]!.map((c) => c.name).join(', ');
  return '''
You are the Hub agent inside a personal app with money, notes, tasks, a calendar and a shopping list.
Today is $day ($iso). Amounts are in euro unless the user says otherwise.

Reply with JSON only, no other text, in this shape:
{"reply": "short answer for the user", "actions": [ ... ]}

Each action is one of:
{"type": "expense", "amount": 12.5, "category": "Eating out", "note": "lunch", "date": "$iso"}
{"type": "income", "amount": 100, "category": "Freelance", "note": "", "date": "$iso"}
{"type": "note", "title": "Landlord", "body": "Call the landlord"}
{"type": "task", "title": "Call the landlord", "due": "$iso", "important": false}
{"type": "event", "title": "Dentist", "start": "${iso}T14:00", "end": "${iso}T15:00", "allDay": false, "location": ""}
{"type": "shopping", "name": "milk", "quantity": "2"}

Expense categories: $expense.
Income categories: $income.
Only add actions the user asked for. Leave "actions" empty when the user only asks a question.
Dates are YYYY-MM-DD, times are 24 hour. "due" and "date" may be left out.''';
}

/// One change the agent proposes. Nothing is saved until the user taps Add.
class AgentAction {
  AgentAction(this.type, this.fields);
  final String type;
  final Map<String, dynamic> fields;

  static const types = {'expense', 'income', 'note', 'task', 'event', 'shopping'};

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

  /// Actions missing what they need are dropped.
  bool get valid => switch (type) {
    'expense' || 'income' => cents > 0,
    'note' => title.isNotEmpty || _s('body').isNotEmpty,
    'task' => title.isNotEmpty,
    'event' => title.isNotEmpty && date('start') != null,
    'shopping' => name.isNotEmpty,
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
      'event' =>
        '$title, ${DateFormat(fields['allDay'] == true ? 'EEE d MMM' : 'EEE d MMM HH:mm').format(date('start')!)}',
      'shopping' => _s('quantity').isEmpty ? name : '$name (${_s('quantity')})',
      _ => type,
    };
  }

  String get label => switch (type) {
    'expense' => 'Expense',
    'income' => 'Income',
    'note' => 'Note',
    'task' => 'Task',
    'event' => 'Event',
    'shopping' => 'Shopping',
    _ => type,
  };

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
            date: Value(date('date') ?? today),
          ),
        );
      case 'note':
        final body = _s('body');
        await db.saveNote(title: title, body: body.isEmpty ? title : body);
      case 'task':
        await db.addTodo(title, due: date('due'), important: fields['important'] == true);
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
            if (a is! Map) continue;
            final type = (a['type'] ?? '').toString().toLowerCase();
            if (!AgentAction.types.contains(type)) continue;
            final action = AgentAction(type, a.cast<String, dynamic>());
            if (action.valid) actions.add(action);
          }
        }
        final reply = (j['reply'] ?? '').toString().trim();
        return AgentReply(reply.isEmpty && actions.isNotEmpty ? 'Here is what I can add:' : reply, actions);
      }
    } catch (_) {}
  }
  return AgentReply(text, const []);
}
