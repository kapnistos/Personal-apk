import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../shopping/shopping_model.dart';
import '../spaces/space_model.dart' show allWorkStatuses, workStatusLabels;
import '../spaces/work_hours.dart' show DayTimes, formatHours;
import '../wallet/insights.dart' show spendTargetKey;
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
    'Use the user\'s own words for things, and real dates ("Sat 1 Nov") rather than offsets.';

/// Answers are read on a phone, in a narrow column.
const phoneStyle =
    'Your answer is read on a phone. Lead with the answer in a sentence or two, then stop. Keep it under about '
    '120 words unless the user asks for more. Use a short bulleted list (at most 6 lines, one line each) only for '
    'a schedule, a few amounts or a few steps. Bold only the key number, time or name. No tables, no headings, '
    'no code blocks, no long paragraphs.';

/// A short map of the app, so the model knows where things live and what it can change.
const hubGuide = '''
What is in Hub:
- Calendar: several calendars (Personal, Work, Study and any the user made); imported calendars from a link are read-only. Events can be all day, repeat, and have a reminder.
- To-do: tasks with an optional due date, a star for important, repeats; some belong to a space.
- Notes: free text notes with a title.
- Wallet: every expense and income, accounts, recurring payments and subscriptions (Wallet > Recurring payments), a monthly spending budget (Wallet > Monthly budget), category budgets, savings goals with deposits, and investments.
- Habits: things to do on set weekdays, ticked off per day, with streaks.
- Shopping list.
- Spaces: University, Job, Lab research and the user's own. Each has its own calendar for important dates (exams, deadlines, shifts) and meetings, saved notes and links, and tasks. Job also has a work log: hours per day against a contract schedule.
- Internship applications and weather.''';

/// The time zone as the model should read it: "CET, UTC+01:00".
String timeZoneLabel(DateTime now) {
  final o = now.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final h = o.inHours.abs().toString().padLeft(2, '0');
  final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final offset = 'UTC$sign$h:$m';
  final name = now.timeZoneName;
  // Some platforms name the zone only by its offset ("+01"); then the offset says it all.
  final named = name.isNotEmpty && !name.startsWith('+') && !name.startsWith('-') && name != 'UTC';
  return named ? '$name, $offset' : offset;
}

/// Who the model is talking to and when: shared by both agent prompts and Chat.
String hubWhen(DateTime now, {String currency = 'EUR', String name = ''}) {
  final day = DateFormat('EEEE d MMMM y, HH:mm').format(now);
  final who = name.trim().isEmpty ? '' : ' The user is ${name.trim()}; use their first name only now and then.';
  return 'Now: $day (${HubDates.iso(now)}), time zone ${timeZoneLabel(now)}. '
      'Money is in $currency unless the user says otherwise.$who';
}

/// What the Hub agent is told when it can call tools to read the app and propose changes.
String agentToolPrompt(DateTime now, {String currency = 'EUR', String name = ''}) =>
    '''
You are the Hub agent inside the user's personal app, Hub.
${hubWhen(now, currency: currency, name: name)}

$hubGuide

Read with the get_ and search_ tools. Always look before you answer a question about the user's data, and never say something is empty without checking with a tool first. For "the next days" or "this week" read the calendar for that whole range. For subscriptions or bills read get_recurring.

To change something, call a propose_ tool for each change: add, edit, reschedule or delete events and tasks, tick tasks off, add or edit notes, log money, add or edit recurring payments, add savings deposits, set the monthly budget, add shopping items, log Job hours, add important dates to a space and tick habits. Each becomes a card, and nothing is saved until the user taps it, so say "here it is to add" rather than "done". Find the id with a read tool before editing, completing or deleting anything. Only propose what the user asked for, or clearly agreed to; when planning, suggest first and propose once they say yes, unless they asked you to add it. Deleting is never a guess: if two things could match, ask.
${_categories()}

$_voice
$phoneStyle''';

/// What the Hub agent is told when its model cannot call tools: the data comes in the prompt and
/// changes come back as JSON.
String agentSystemPrompt(DateTime now, {String currency = 'EUR', String name = ''}) {
  final day = DateFormat('EEEE d MMMM y').format(now);
  final iso = HubDates.iso(now);
  return '''
You are the Hub agent inside a personal app with money, notes, tasks, a calendar, habits, spaces and a shopping list.
Today is $day ($iso). ${hubWhen(now, currency: currency, name: name)}

$hubGuide

Reply with JSON only, no other text, in this shape:
{"reply": "short answer for the user", "actions": [ ... ]}

Each action is one of:
{"type": "expense", "amount": 12.5, "category": "Eating out", "note": "lunch", "date": "$iso"}
{"type": "income", "amount": 100, "category": "Freelance", "note": "", "date": "$iso"}
{"type": "note", "title": "Landlord", "body": "Call the landlord"}
{"type": "edit_note", "id": 4, "append": "Also ask about the boiler"}
{"type": "task", "title": "Call the landlord", "due": "$iso", "important": false}
{"type": "edit_task", "id": 12, "due": "$iso", "important": true}
{"type": "complete", "id": 12, "title": "Call the landlord"}
{"type": "delete_task", "id": 12}
{"type": "event", "title": "Dentist", "start": "${iso}T14:00", "end": "${iso}T15:00", "allDay": false, "location": "", "calendar": "Personal"}
{"type": "edit_event", "id": 7, "start": "${iso}T16:00"}
{"type": "delete_event", "id": 7}
{"type": "shopping", "name": "milk", "quantity": "2"}
{"type": "recurring", "name": "Netflix", "amount": 13.99, "kind": "payment", "category": "Streaming", "period": 1, "next": "$iso"}
{"type": "edit_recurring", "id": 3, "amount": 15.99}
{"type": "saving", "goal": "Holiday", "amount": 50}
{"type": "budget_target", "amount": 1200}
{"type": "work_day", "date": "$iso", "status": "work", "start": "09:00", "end": "17:30", "break_minutes": 30}
{"type": "space_date", "space": "University", "title": "Statistics exam", "date": "$iso"}
{"type": "habit", "name": "Read", "date": "$iso"}

${_categories()}
Use the ids shown in the data. Only add actions the user asked for. Leave "actions" empty when the user only asks a question.
Dates are YYYY-MM-DD, times are 24 hour. "due" and "date" may be left out.
The user's data is below, when they share it. Answer from it; if something is not there, say so plainly.
In "reply": $_voice $phoneStyle''';
}

/// Date helpers shared by the prompts and the cards.
abstract final class HubDates {
  static String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String short(DateTime d) => DateFormat('EEE d MMM').format(d);
  static String withTime(DateTime d) => DateFormat('EEE d MMM, HH:mm').format(d);
}

/// Takes back what an Add did.
typedef Undo = Future<void> Function();

/// One change the agent proposes. Nothing is saved until the user taps Add (or Save, Done, Delete).
class AgentAction {
  AgentAction(this.type, this.fields);
  final String type;
  final Map<String, dynamic> fields;

  static const types = {
    'expense',
    'income',
    'note',
    'edit_note',
    'task',
    'edit_task',
    'complete',
    'delete_task',
    'event',
    'edit_event',
    'delete_event',
    'shopping',
    'recurring',
    'edit_recurring',
    'saving',
    'budget_target',
    'work_day',
    'space_date',
    'habit',
  };

  String _s(String k) => (fields[k] ?? '').toString().trim();
  bool _has(String k) => fields[k] != null && fields[k].toString().trim().isNotEmpty;
  bool? _bool(String k) {
    final v = fields[k];
    if (v is bool) return v;
    if (v == null) return null;
    final t = v.toString().toLowerCase();
    return t == 'true' || t == 'yes' || t == '1' ? true : (t == 'false' || t == 'no' || t == '0' ? false : null);
  }

  int? _int(String k) {
    final v = fields[k];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
  }

  double? get amount {
    final v = fields['amount'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '.') ?? '');
  }

  int get cents => ((amount ?? 0).abs() * 100).round();
  String get title => _s('title');
  String get name => _s('name');
  DateTime? date(String k) => DateTime.tryParse(_s(k).replaceFirst(' ', 'T'));
  int? get taskId => _int('id');
  int? get id => _int('id');
  int get period {
    final n = _int('period');
    return n == null || n < 1 ? 1 : n;
  }

  EntryKind get recurringKind => _s('kind').toLowerCase() == 'income' ? EntryKind.income : EntryKind.subscription;

  /// What this card changes, filled in by [resolve] so the card can say "was …".
  String get was => _s('was');

  /// A delete: shown in red, never part of "Add all".
  bool get destructive => type.startsWith('delete_');

  /// "HH:MM" as minutes after midnight.
  int? _clock(String k) {
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(_s(k));
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    return h > 24 || min > 59 ? null : h * 60 + min;
  }

  String get _status {
    final s = _s('status').toLowerCase();
    if (s.isEmpty) return 'work';
    return switch (s) {
      'home' || 'from home' || 'wfh' => 'remote',
      'worked' => 'work',
      'public holiday' => 'public',
      _ => s,
    };
  }

  bool get _editsSomething => switch (type) {
    'edit_note' => _has('title') || _has('body') || _has('append'),
    'edit_task' =>
      _has('title') || _has('due') || _bool('clear_due') == true || _bool('important') != null || _has('details'),
    'edit_event' =>
      _has('title') || _has('start') || _has('end') || _bool('allDay') != null || _has('location') || _has('calendar'),
    'edit_recurring' =>
      _has('name') ||
          amount != null ||
          _has('period') ||
          _has('next') ||
          _has('category') ||
          _has('account') ||
          _bool('active') != null,
    _ => true,
  };

  /// Actions missing what they need are dropped.
  bool get valid => switch (type) {
    'expense' || 'income' => cents > 0,
    'note' => title.isNotEmpty || _s('body').isNotEmpty,
    'task' => title.isNotEmpty,
    'complete' => taskId != null || title.isNotEmpty,
    'event' => title.isNotEmpty && date('start') != null,
    'shopping' => name.isNotEmpty,
    'recurring' => name.isNotEmpty && cents > 0,
    'edit_note' || 'edit_task' || 'edit_event' || 'edit_recurring' => id != null && _editsSomething,
    'delete_task' || 'delete_event' => id != null,
    'saving' => cents > 0,
    'budget_target' => amount != null && amount! >= 0,
    'work_day' => date('date') != null && allWorkStatuses.contains(_status),
    'space_date' => _has('space') && title.isNotEmpty && date('date') != null,
    'habit' => id != null || name.isNotEmpty,
    _ => false,
  };

  String category(EntryKind kind) {
    final want = _s('category').toLowerCase();
    final cats = categoriesByKind[kind]!;
    return cats.firstWhere((c) => c.name.toLowerCase() == want, orElse: () => cats.last).name;
  }

  DateTime _start() => date('start')!;
  bool get _allDay => _bool('allDay') == true || (_has('start') && !_s('start').contains(RegExp('[T ]')));

  /// The bold line on the card, with amounts in [currency].
  String summaryIn(String currency) {
    String m() => money(cents, currency);
    final note = _s('note');
    return switch (type) {
      'expense' => '${m()} on ${category(EntryKind.expense)}${note.isEmpty ? '' : ', $note'}',
      'income' => '${m()} in, ${category(EntryKind.income)}${note.isEmpty ? '' : ', $note'}',
      'note' => title.isEmpty ? _s('body') : title,
      'edit_note' => _s('target').isNotEmpty ? _s('target') : (title.isNotEmpty ? title : 'Note $id'),
      'task' => '$title${date('due') == null ? '' : ', due ${DateFormat('d MMM').format(date('due')!)}'}',
      'edit_task' || 'delete_task' => _s('target').isNotEmpty ? _s('target') : (title.isNotEmpty ? title : 'Task $id'),
      'complete' => title.isEmpty ? (_s('target').isEmpty ? 'Task $taskId' : _s('target')) : title,
      'event' => '$title, ${_allDay ? HubDates.short(_start()) : HubDates.withTime(_start())}',
      'edit_event' ||
      'delete_event' => _s('target').isNotEmpty ? _s('target') : (title.isNotEmpty ? title : 'Event $id'),
      'shopping' => _s('quantity').isEmpty ? name : '$name (${_s('quantity')})',
      'recurring' =>
        '$name, ${m()} ${period == 1 ? 'a month' : 'every $period months'}'
            '${date('next') == null ? '' : ', next ${DateFormat('d MMM').format(date('next')!)}'}',
      'edit_recurring' => _s('target').isNotEmpty ? _s('target') : (name.isNotEmpty ? name : 'Recurring payment $id'),
      'saving' => '${m()} ${_bool('withdraw') == true ? 'from' : 'to'} ${_s('goal').isEmpty ? 'savings' : _s('goal')}',
      'budget_target' => cents == 0 ? 'No monthly budget' : '${m()} a month',
      'work_day' => () {
        final d = date('date')!;
        final label = workStatusLabels[_status] ?? _status;
        final h = _hours;
        return '${HubDates.short(d)}: $label${h == null ? '' : ', ${formatHours(h)} h'}';
      }(),
      'space_date' => '$title, ${_has('time') ? HubDates.withTime(_spaceStart) : HubDates.short(date('date')!)}',
      'habit' => '${name.isNotEmpty ? name : _s('target')}, ${_habitDayWords()}',
      _ => type,
    };
  }

  String get summary => summaryIn('EUR');

  /// The muted line under it: what changes, what it was, where it goes. Null when the summary says it all.
  String? detailIn(String currency) {
    final parts = <String>[];
    switch (type) {
      case 'edit_note':
        if (_has('title') && title != _s('target')) parts.add('Title: $title');
        if (_has('append')) parts.add('Adds: ${_clip(_s('append'), 120)}');
        if (_has('body')) parts.add('New text: ${_clip(_s('body'), 120)}');
      case 'edit_task':
        if (_has('title') && title != _s('target')) parts.add('Rename to $title');
        if (_bool('clear_due') == true || _s('due').toLowerCase() == 'none') {
          parts.add('No due date');
        } else if (date('due') != null) {
          parts.add('Due ${HubDates.short(date('due')!)}');
        }
        if (_bool('important') == true) parts.add('Starred');
        if (_bool('important') == false) parts.add('Not starred');
        if (_has('details')) parts.add('Details: ${_clip(_s('details'), 80)}');
      case 'edit_event':
        if (_has('title') && title != _s('target')) parts.add('Rename to $title');
        if (date('start') != null) {
          final s = date('start')!;
          final e = date('end');
          parts.add(
            _allDay
                ? HubDates.short(s)
                : '${HubDates.withTime(s)}${e != null && dateOnly(e) == dateOnly(s) ? '–${DateFormat.Hm().format(e)}' : ''}',
          );
        } else if (date('end') != null) {
          parts.add('Ends ${DateFormat.Hm().format(date('end')!)}');
        }
        if (_has('location')) parts.add('at ${_s('location')}');
        if (_has('calendar')) parts.add('in ${_s('calendar')}');
      case 'event':
        if (_has('location')) parts.add(_s('location'));
        if (_has('calendar')) parts.add(_s('calendar'));
        if (_has('repeat') && _s('repeat') != 'none') parts.add('repeats ${_s('repeat')}');
      case 'edit_recurring':
        if (_has('name') && name != _s('target')) parts.add('Rename to $name');
        if (amount != null) parts.add(money(cents, currency));
        if (_has('period')) parts.add(periodLabel(period).toLowerCase());
        if (date('next') != null) parts.add('next ${HubDates.short(date('next')!)}');
        if (_has('category')) parts.add(_s('category'));
        if (_has('account')) parts.add('from ${_s('account')}');
        if (_bool('active') == false) parts.add('Paused');
        if (_bool('active') == true) parts.add('Active again');
      case 'saving':
        if (_has('note')) parts.add(_s('note'));
      case 'work_day':
        final t = _times;
        if (t != null) parts.add(t.label);
        if (_has('note')) parts.add(_s('note'));
      case 'space_date':
        parts.add('In ${_s('space')}');
      case 'delete_event' || 'delete_task':
        break;
    }
    final line = parts.join(' · ');
    final wasCents = _int('was_cents');
    final wasText = wasCents != null
        ? '${money(wasCents, currency)}${_has('was_period') ? ' ${periodLabel(_int('was_period') ?? 1).toLowerCase()}' : ''}'
        : was;
    final before = wasText.isEmpty ? '' : (destructive ? wasText : 'was $wasText');
    final out = [if (line.isNotEmpty) line, if (before.isNotEmpty) before].join(type == 'edit_event' ? ', ' : ' · ');
    return out.isEmpty ? null : out;
  }

  String? get detail => detailIn('EUR');

  static String _clip(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > n ? '${t.substring(0, n)}…' : t;
  }

  DayTimes? get _times {
    final a = _clock('start'), b = _clock('end');
    if (a == null || b == null) return null;
    return DayTimes(a, b, breakMinutes: _int('break_minutes') ?? 0);
  }

  double? get _hours {
    if (_status != 'work' && _status != 'remote') return null;
    final h = fields['hours'];
    final v = h is num ? h.toDouble() : double.tryParse('${h ?? ''}'.replaceAll(',', '.'));
    return v ?? _times?.hours;
  }

  DateTime get _spaceStart {
    final d = date('date')!;
    final t = _clock('time') ?? 9 * 60;
    return DateTime(d.year, d.month, d.day, t ~/ 60, t % 60);
  }

  DateTime _habitDay([DateTime? now]) => dateOnly(date('date') ?? now ?? DateTime.now());

  String _habitDayWords() {
    final d = date('date');
    if (d == null) return 'today';
    final today = dateOnly(DateTime.now());
    if (dateOnly(d) == today) return 'today';
    if (dateOnly(d) == addDays(today, -1)) return 'yesterday';
    return HubDates.short(d);
  }

  String get label => switch (type) {
    'expense' => 'Expense',
    'income' => 'Income',
    'note' => 'Note',
    'edit_note' => _has('append') && !_has('body') && !_has('title') ? 'Add to note' : 'Edit note',
    'task' => 'Task',
    'edit_task' =>
      (_has('due') || _bool('clear_due') == true) && !_has('title') && !_has('details') && _bool('important') == null
          ? 'Reschedule task'
          : 'Edit task',
    'complete' => 'Mark done',
    'delete_task' => 'Delete task',
    'event' => 'Event',
    'edit_event' => _has('start') && !_has('title') && !_has('location') ? 'Reschedule event' : 'Edit event',
    'delete_event' => 'Delete event',
    'shopping' => 'Shopping',
    'recurring' => recurringKind == EntryKind.income ? 'Recurring income' : 'Recurring payment',
    'edit_recurring' => _bool('active') == false ? 'Pause recurring payment' : 'Edit recurring payment',
    'saving' => _bool('withdraw') == true ? 'Savings withdrawal' : 'Savings deposit',
    'budget_target' => 'Monthly budget',
    'work_day' => 'Job hours',
    'space_date' => 'Important date',
    'habit' => 'Habit',
    _ => type,
  };

  /// What the confirm button says.
  String get verb => switch (type) {
    'complete' || 'habit' => 'Done',
    'delete_task' || 'delete_event' => 'Delete',
    'edit_note' || 'edit_task' || 'edit_event' || 'edit_recurring' || 'budget_target' => 'Save',
    'work_day' => 'Log',
    _ => 'Add',
  };

  /// What the card says once confirmed.
  String get doneLabel => switch (verb) {
    'Done' => 'Done',
    'Delete' => 'Deleted',
    'Save' => 'Saved',
    'Log' => 'Logged',
    _ => 'Added',
  };

  /// The line in the snack bar after a tap.
  String get doneMessage => switch (type) {
    'complete' => 'Marked done',
    'habit' => 'Habit ticked',
    'delete_task' => 'Task deleted',
    'delete_event' => 'Event deleted',
    'edit_note' => 'Note saved',
    'edit_task' => 'Task saved',
    'edit_event' => 'Event saved',
    'edit_recurring' => 'Recurring payment saved',
    'budget_target' => 'Budget saved',
    'work_day' => 'Hours logged',
    _ => '$label added',
  };

  Map<String, dynamic> toJson() => {'type': type, ...fields};

  static AgentAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = (j['type'] ?? '').toString().toLowerCase();
    if (!types.contains(type)) return null;
    final a = AgentAction(type, Map<String, dynamic>.from(j)..remove('type'));
    return a.valid ? a : null;
  }

  // Finding what an action is about

  Future<Todo?> _findTask(AppDatabase db) async {
    final i = id;
    if (i != null) {
      final t = await db.todoById(i);
      if (t != null) return t;
    }
    if (type != 'complete' || title.isEmpty) return null;
    final want = title.toLowerCase();
    return (await db.watchTodos().first).where((t) => !t.done && t.title.toLowerCase() == want).firstOrNull;
  }

  Future<Event?> _findEvent(AppDatabase db) async {
    final i = id;
    if (i == null) return null;
    return (db.select(db.events)..where((e) => e.id.equals(i))).getSingleOrNull();
  }

  Future<Note?> _findNote(AppDatabase db) async {
    final i = id;
    if (i == null) return null;
    return (db.select(db.notes)..where((n) => n.id.equals(i))).getSingleOrNull();
  }

  Future<Subscription?> _findRecurring(AppDatabase db) async {
    final i = id;
    if (i == null) return null;
    return (db.select(db.subscriptions)..where((s) => s.id.equals(i))).getSingleOrNull();
  }

  Future<SavingsGoal?> _findGoal(AppDatabase db) async {
    final goals = (await db.watchGoals().first).where((g) => !g.archived).toList();
    final gid = _int('goal_id');
    if (gid != null) return goals.where((g) => g.id == gid).firstOrNull;
    final want = _s('goal').toLowerCase();
    if (want.isEmpty) return goals.length == 1 ? goals.single : null;
    return goals.where((g) => g.name.toLowerCase() == want).firstOrNull ??
        goals.where((g) => g.name.toLowerCase().contains(want) || want.contains(g.name.toLowerCase())).firstOrNull;
  }

  Future<Habit?> _findHabit(AppDatabase db) async {
    final list = await db.watchHabits().first;
    final i = id;
    if (i != null) {
      final h = list.where((h) => h.id == i).firstOrNull;
      if (h != null) return h;
    }
    final want = name.toLowerCase();
    if (want.isEmpty) return null;
    return list.where((h) => h.name.toLowerCase() == want).firstOrNull ??
        list.where((h) => h.name.toLowerCase().contains(want)).firstOrNull;
  }

  Future<Space?> _findSpace(AppDatabase db) async {
    final want = _s('space').toLowerCase();
    final list = await db.watchSpaces().first;
    final kinds = {'university': 'school', 'study': 'school', 'job': 'work', 'work': 'work', 'research': 'science'};
    return list.where((s) => s.name.toLowerCase() == want).firstOrNull ??
        list.where((s) => s.name.toLowerCase().contains(want) || want.contains(s.name.toLowerCase())).firstOrNull ??
        list.where((s) => s.icon == kinds[want]).firstOrNull;
  }

  /// The calendar a new or moved event goes to: the one the model named (or a space's), else the first own one.
  static Future<Calendar?> calendarNamed(AppDatabase db, String name) async {
    final own = (await db.watchCalendars().first).where((c) => c.icsUrl == null).toList();
    if (own.isEmpty) return null;
    final want = name.trim().toLowerCase();
    if (want.isEmpty) return own.first;
    final hit =
        own.where((c) => c.name.toLowerCase() == want).firstOrNull ??
        own.where((c) => c.name.toLowerCase().contains(want) || want.contains(c.name.toLowerCase())).firstOrNull;
    if (hit != null) return hit;
    final space = (await db.watchSpaces().first)
        .where((s) => s.calendarId != null && s.name.toLowerCase().contains(want))
        .firstOrNull;
    return own.where((c) => c.id == space?.calendarId).firstOrNull ?? own.first;
  }

  static String _when(Event e) => e.allDay ? HubDates.short(e.start) : HubDates.withTime(e.start);

  /// Checks the action against the data before it becomes a card, and notes what it changes ("was …").
  /// Returns why it cannot be done, or null.
  Future<String?> resolve(AppDatabase db, {DateTime? now}) async {
    switch (type) {
      case 'edit_task' || 'delete_task' || 'complete':
        final t = await _findTask(db);
        if (t == null) return 'There is no task with that id. Look it up with get_tasks first.';
        if (type == 'complete' && t.done) return 'That task is already done.';
        fields['id'] = t.id;
        fields['target'] = t.title;
        if (type == 'edit_task' && (_has('due') || _bool('clear_due') == true)) {
          fields['was'] = t.due == null ? 'no due date' : 'due ${HubDates.short(t.due!)}';
        }
        if (type == 'delete_task' && t.due != null) fields['was'] = 'due ${HubDates.short(t.due!)}';
      case 'edit_event' || 'delete_event':
        final e = await _findEvent(db);
        if (e == null) return 'There is no event with that id. Look it up with get_calendar first.';
        final cal = (await db.watchCalendars().first).where((c) => c.id == e.calendarId).firstOrNull;
        if (cal?.icsUrl != null) {
          return 'That event comes from the imported calendar "${cal!.name}", which is read-only in Hub.';
        }
        fields['target'] = e.title;
        fields['was'] = [
          _when(e),
          if (e.repeat != 'none') 'repeats ${e.repeat}${type == 'delete_event' ? ', every one goes' : ''}',
        ].join(', ');
      case 'edit_note':
        final n = await _findNote(db);
        if (n == null) return 'There is no note with that id. Look it up with search_notes first.';
        fields['target'] = n.title.isNotEmpty ? n.title : _clip(n.body, 40);
      case 'edit_recurring':
        final s = await _findRecurring(db);
        if (s == null) return 'There is no recurring payment with that id. Look it up with get_recurring first.';
        fields['target'] = s.name;
        fields['was_cents'] = s.amountCents;
        fields['was_period'] = s.periodMonths;
      case 'saving':
        final g = await _findGoal(db);
        if (g == null) return 'No savings goal matches that name. Read get_savings for the names.';
        fields['goal'] = g.name;
        fields['goal_id'] = g.id;
      case 'budget_target':
        final old = int.tryParse((await db.readSettings())[spendTargetKey] ?? '');
        if (old != null && old > 0) fields['was_cents'] = old;
      case 'work_day':
        final d = date('date')!;
        final key = AppDatabase.dayKey(d);
        final old = (await db.watchWorkDays(d, addDays(d, 1)).first).where((w) => w.day == key).firstOrNull;
        if (old != null) {
          fields['was'] =
              '${workStatusLabels[old.status] ?? old.status}${old.hours == null ? '' : ' ${formatHours(old.hours!)} h'}';
        }
      case 'space_date':
        final s = await _findSpace(db);
        if (s == null || s.calendarId == null) return 'No space matches that name. Read get_spaces for the names.';
        fields['space'] = s.name;
      case 'habit':
        final h = await _findHabit(db);
        if (h == null) return 'No habit matches that name. Read get_habits for the names.';
        fields['id'] = h.id;
        fields['name'] = h.name;
      case 'event':
        if (_has('calendar')) {
          final c = await calendarNamed(db, _s('calendar'));
          if (c != null) fields['calendar'] = c.name;
        }
    }
    return null;
  }

  /// Writes the action with the app's own database methods, and returns how to take it back.
  /// [settings] keeps the in-memory copy in step for the monthly budget.
  Future<Undo> apply(AppDatabase db, {DateTime? now, AppSettings? settings}) async {
    final today = now ?? DateTime.now();
    switch (type) {
      case 'expense' || 'income':
        final kind = type == 'expense' ? EntryKind.expense : EntryKind.income;
        final rowId = await db.addEntry(
          EntriesCompanion(
            amountCents: Value(cents),
            kind: Value(kind),
            category: Value(category(kind)),
            note: Value(_s('note')),
            account: Value(_s('account')),
            date: Value(date('date') ?? today),
          ),
        );
        return () => db.deleteEntry(rowId);
      case 'note':
        final body = _s('body');
        final rowId = await db.saveNote(title: title, body: body.isEmpty ? title : body);
        return () => db.deleteNote(rowId);
      case 'edit_note':
        final old = await _findNote(db);
        if (old == null) throw StateError('No such note');
        var body = _has('body') ? _s('body') : old.body;
        if (_has('append')) body = body.trimRight().isEmpty ? _s('append') : '${body.trimRight()}\n${_s('append')}';
        await db.saveNote(id: old.id, title: _has('title') ? title : old.title, body: body);
        return () => db.update(db.notes).replace(old);
      case 'task':
        final rowId = await db.addTodo(title, due: date('due'), important: _bool('important') == true);
        return () => db.deleteTodo(rowId);
      case 'edit_task':
        final old = await _findTask(db);
        if (old == null) throw StateError('No such task');
        final clear = _bool('clear_due') == true || _s('due').toLowerCase() == 'none';
        final due = date('due');
        await db.updateTodo(
          old.copyWith(
            title: _has('title') ? title : old.title,
            details: _has('details') ? _s('details') : old.details,
            important: _bool('important') ?? old.important,
            due: clear ? const Value(null) : (due != null ? Value(dateOnly(due)) : Value(old.due)),
          ),
        );
        return () => db.updateTodo(old);
      case 'complete':
        final t = await _findTask(db);
        if (t == null) throw StateError('No such task');
        await db.setTodoDone(t.id, true);
        return () => db.setTodoDone(t.id, false);
      case 'delete_task':
        final old = await _findTask(db);
        if (old == null) throw StateError('No such task');
        await db.deleteTodo(old.id);
        return () => db.restoreTodo(old);
      case 'event':
        final start = _start();
        final allDay = _allDay;
        var end = date('end');
        if (allDay && end != null && !end.isAfter(start)) end = addDays(dateOnly(end), 1);
        if (end == null || !end.isAfter(start)) {
          end = allDay ? DateTime(start.year, start.month, start.day + 1) : start.add(const Duration(hours: 1));
        }
        final cal = await calendarNamed(db, _s('calendar'));
        if (cal == null) throw StateError('No calendar');
        final repeat = _s('repeat').toLowerCase();
        final rowId = await db.saveEvent(
          EventsCompanion(
            calendarId: Value(cal.id),
            title: Value(title),
            location: Value(_s('location')),
            notes: Value(_s('notes')),
            start: Value(allDay ? dateOnly(start) : start),
            end: Value(end),
            allDay: Value(allDay),
            repeat: Value(const {'daily', 'weekly', 'monthly', 'yearly'}.contains(repeat) ? repeat : 'none'),
            remindMinutes: Value(_int('remind_minutes')),
          ),
        );
        return () => db.deleteEvent(rowId);
      case 'edit_event':
        final old = await _findEvent(db);
        if (old == null) throw StateError('No such event');
        final allDay = _bool('allDay') ?? (_has('start') ? _allDay : old.allDay);
        var start = date('start') ?? old.start;
        if (allDay) start = dateOnly(start);
        var end = date('end');
        if (end == null) {
          // Moving an event keeps its length; switching to all day makes it one day.
          end = allDay && !old.allDay ? addDays(start, 1) : start.add(old.end.difference(old.start));
        } else if (allDay && !end.isAfter(start)) {
          end = addDays(dateOnly(end), 1);
        }
        if (!end.isAfter(start)) end = allDay ? addDays(start, 1) : start.add(const Duration(hours: 1));
        final cal = _has('calendar') ? await calendarNamed(db, _s('calendar')) : null;
        await db
            .update(db.events)
            .replace(
              old.copyWith(
                title: _has('title') ? title : old.title,
                location: _has('location') ? _s('location') : old.location,
                start: start,
                end: end,
                allDay: allDay,
                calendarId: cal?.id ?? old.calendarId,
              ),
            );
        return () => db.update(db.events).replace(old);
      case 'delete_event':
        final old = await _findEvent(db);
        if (old == null) throw StateError('No such event');
        await db.deleteEvent(old.id);
        return () => db.restoreEvent(old);
      case 'shopping':
        final rowId = await db.addShoppingItem(name, quantity: _s('quantity'), category: categorize(name));
        return () => db.deleteShoppingItem(rowId);
      case 'recurring':
        final kind = recurringKind;
        var next = date('next') ?? dateOnly(today);
        if (next.isBefore(dateOnly(today))) next = dateOnly(today);
        final rowId = await db.saveSubscription(
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
        return () => db.deleteSubscription(rowId);
      case 'edit_recurring':
        final old = await _findRecurring(db);
        if (old == null) throw StateError('No such recurring payment');
        final kind = old.kind == EntryKind.income ? EntryKind.income : EntryKind.subscription;
        await db
            .update(db.subscriptions)
            .replace(
              old.copyWith(
                name: _has('name') ? name : old.name,
                amountCents: amount != null && cents > 0 ? cents : old.amountCents,
                periodMonths: _has('period') ? period : old.periodMonths,
                nextDate: date('next') != null ? dateOnly(date('next')!) : old.nextDate,
                category: _has('category') ? category(kind) : old.category,
                account: _has('account') ? _s('account') : old.account,
                active: _bool('active') ?? old.active,
              ),
            );
        return () => db.update(db.subscriptions).replace(old);
      case 'saving':
        final g = await _findGoal(db);
        if (g == null) throw StateError('No such goal');
        final signed = _bool('withdraw') == true ? -cents : cents;
        final rowId = await db.addMove(g.id, signed, note: _s('note'), date: date('date') ?? today);
        return () => db.deleteMove(rowId);
      case 'budget_target':
        final old = settings?.raw(spendTargetKey) ?? (await db.readSettings())[spendTargetKey] ?? '';
        Future<void> write(String v) =>
            settings != null ? settings.setRaw(spendTargetKey, v) : db.writeSetting(spendTargetKey, v);
        await write(cents <= 0 ? '' : '$cents');
        return () => write(old);
      case 'work_day':
        final d = dateOnly(date('date')!);
        final key = AppDatabase.dayKey(d);
        final old = (await db.watchWorkDays(d, addDays(d, 1)).first).where((w) => w.day == key).firstOrNull;
        final times = _times;
        final text = _s('note');
        await db.setWorkDay(d, _status, hours: _hours, note: DayTimes.join(times, text));
        return () => db.setWorkDay(d, old?.status, hours: old?.hours, note: old?.note ?? '');
      case 'space_date':
        final s = await _findSpace(db);
        if (s?.calendarId == null) throw StateError('No such space');
        final timed = _has('time');
        final d = dateOnly(date('date')!);
        final last = date('end_date');
        final rowId = await db.saveEvent(
          EventsCompanion(
            calendarId: Value(s!.calendarId!),
            title: Value(title),
            notes: Value(_s('notes')),
            start: Value(timed ? _spaceStart : d),
            end: Value(
              timed
                  ? _spaceStart.add(const Duration(hours: 1))
                  : addDays(last != null && !last.isBefore(d) ? dateOnly(last) : d, 1),
            ),
            allDay: Value(!timed),
            // Like adding a date by hand: the evening before for an all-day date.
            remindMinutes: Value(timed ? 60 : 900),
          ),
        );
        return () => db.deleteEvent(rowId);
      case 'habit':
        final h = await _findHabit(db);
        if (h == null) throw StateError('No such habit');
        final day = _habitDay(today);
        final key = AppDatabase.dayKey(day);
        final already = (await db.habitChecksSince(day)).any((c) => c.habitId == h.id && c.day == key);
        await db.setHabitDone(h.id, day, true);
        return already ? () async {} : () => db.setHabitDone(h.id, day, false);
    }
    throw StateError('Unknown action $type');
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
