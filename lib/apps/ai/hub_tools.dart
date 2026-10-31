import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Table;
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/reminders.dart' show occurrences, occurrenceEnd;
import '../habits/habits_page.dart' show habitDueOn, habitStreak;
import '../spaces/work_hours.dart' show WorkSchedule;
import '../wallet/wallet_model.dart';
import '../weather/weather_service.dart';
import 'ai_service.dart';
import 'hub_agent.dart';

/// Reads weather for a city; swapped in tests so nothing goes to the network.
typedef WeatherLookup = Future<Forecast> Function(City city);

/// The Hub agent's view of the app: read tools over every table, and "propose" tools that turn into
/// cards the user confirms. Nothing here writes to the database; [proposals] collects what the model
/// suggested, and only the user's Add runs [AgentAction.apply].
class HubTools {
  HubTools(this.db, {this.currency = 'EUR', DateTime Function()? clock, this.weather, this.writes = true})
    : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final String currency;
  final DateTime Function() clock;
  final WeatherLookup? weather;

  /// Whether the propose tools are offered (the agent), or only reading (Chat with "Use my Hub").
  final bool writes;

  /// What the model proposed during this answer, in order.
  final proposals = <AgentAction>[];

  String _m(int cents) => money(cents, currency);
  static final _day = DateFormat('yyyy-MM-dd');
  static final _dayTime = DateFormat("yyyy-MM-dd'T'HH:mm");
  static String day(DateTime d) => _day.format(d);

  static const _date = {'type': 'string', 'description': 'YYYY-MM-DD'};
  static Map<String, Object?> _obj(Map<String, Object?> props, [List<String> required = const []]) => {
    'type': 'object',
    'properties': props,
    if (required.isNotEmpty) 'required': required,
  };

  static final readTools = [
    AiTool(
      'get_calendar',
      'Events between two dates from every calendar, including imported and subscribed calendars, repeating '
          'events (expanded to each date) and all-day events. Use it for any question about plans, the week, '
          'the next days or a date. Defaults to today and the next 14 days.',
      _obj({
        'from': {..._date, 'description': 'First day, YYYY-MM-DD. Default today.'},
        'to': {..._date, 'description': 'Last day included, YYYY-MM-DD. Default 14 days after from.'},
        'query': {'type': 'string', 'description': 'Only events whose title, place or notes contain this.'},
      }),
    ),
    AiTool(
      'get_tasks',
      'To-dos, with and without a due date, including those in spaces. Default: every open task.',
      _obj({
        'status': {
          'type': 'string',
          'enum': ['open', 'done', 'all'],
        },
        'due_from': _date,
        'due_to': _date,
        'query': {'type': 'string'},
      }),
    ),
    AiTool(
      'get_transactions',
      'Wallet entries (expenses, income, subscription payments, taxes, transfers) between two dates, with '
          'totals by category. Default: this month so far.',
      _obj({
        'from': _date,
        'to': {..._date, 'description': 'Last day included.'},
        'category': {'type': 'string'},
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income', 'subscription', 'tax', 'transfer'],
        },
        'account': {'type': 'string'},
        'query': {'type': 'string', 'description': 'Text in the note, e.g. a shop name.'},
        'limit': {'type': 'integer', 'description': 'Most entries to list, default 80.'},
      }),
    ),
    AiTool(
      'get_money_summary',
      'One month of money: income, spending by category and kind, budgets and how much of each is used, '
          'the monthly spending target, recurring bills still to come, and the month before for comparison.',
      _obj({
        'month': {'type': 'string', 'description': 'YYYY-MM. Default this month.'},
      }),
    ),
    const AiTool(
      'get_recurring',
      'Every recurring payment, subscription and recurring income in Wallet: amount, how often, next date, '
          'account, whether it is active, and the monthly totals.',
    ),
    const AiTool(
      'get_accounts',
      'Bank accounts and cards with their current balance (when set) and this month in and out.',
    ),
    const AiTool('get_savings', 'Savings goals: target, saved so far, deadline and recent moves.'),
    const AiTool('get_investments', 'Investments: each holding with units, value, invested and gain.'),
    AiTool(
      'search_notes',
      'Notes, newest first, with their text. Without a query, the most recent ones.',
      _obj({
        'query': {'type': 'string'},
        'limit': {'type': 'integer', 'description': 'Default 15.'},
      }),
    ),
    AiTool(
      'get_habits',
      'Habits with their schedule, streak, and which recent days were done.',
      _obj({
        'days': {'type': 'integer', 'description': 'How many past days to show, default 14.'},
      }),
    ),
    const AiTool('get_shopping_list', 'The shopping list: items still to buy and items bought.'),
    const AiTool(
      'get_spaces',
      'Spaces (such as University, Job, Lab research): their saved notes and links, open tasks, and '
          'important dates (exams, deadlines, shifts) from the space\'s calendar for the next 90 days.',
    ),
    AiTool(
      'get_work_log',
      'The work log: days worked, from home, off, holiday or sick, with hours. Default: this month.',
      _obj({'from': _date, 'to': _date}),
    ),
    const AiTool('get_applications', 'Internship and job applications: company, role, status, deadlines.'),
    AiTool(
      'get_weather',
      'Current weather and the forecast for the next days for the saved cities.',
      _obj({
        'city': {'type': 'string', 'description': 'A saved city name. Default the first one.'},
      }),
    ),
    AiTool(
      'search_hub',
      'Searches everything at once: notes, tasks, events (a year back and ahead), wallet entries (two years), '
          'recurring payments, shopping and space items. Use it to find when or where something was.',
      _obj(
        {
          'query': {'type': 'string'},
        },
        ['query'],
      ),
    ),
  ];

  static const _id = {'type': 'integer', 'description': 'The id from a read tool.'};
  static const _time = {'type': 'string', 'description': 'YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all day.'};
  static const _clock = {'type': 'string', 'description': 'HH:MM, 24 hour.'};
  static const _saved = 'The user sees a card and it is saved only when they tap it.';

  static final writeTools = [
    AiTool(
      'propose_expense',
      'Proposes logging money spent. $_saved',
      _obj(
        {
          'amount': {'type': 'number'},
          'category': {'type': 'string', 'description': 'One of the expense categories.'},
          'note': {'type': 'string'},
          'date': _date,
          'account': {'type': 'string'},
        },
        ['amount'],
      ),
    ),
    AiTool(
      'propose_income',
      'Proposes logging money received. $_saved',
      _obj(
        {
          'amount': {'type': 'number'},
          'category': {'type': 'string'},
          'note': {'type': 'string'},
          'date': _date,
          'account': {'type': 'string'},
        },
        ['amount'],
      ),
    ),
    AiTool(
      'propose_task',
      'Proposes a new to-do. $_saved',
      _obj(
        {
          'title': {'type': 'string'},
          'due': _date,
          'important': {'type': 'boolean'},
        },
        ['title'],
      ),
    ),
    AiTool(
      'propose_edit_task',
      'Proposes changing an open task: rename it, move its due date (reschedule), clear the date, star it or '
          'change its details. Give only what changes. $_saved',
      _obj(
        {
          'id': _id,
          'title': {'type': 'string', 'description': 'New title.'},
          'due': {..._date, 'description': 'New due date, YYYY-MM-DD.'},
          'clear_due': {'type': 'boolean', 'description': 'True to take the due date away.'},
          'important': {'type': 'boolean'},
          'details': {'type': 'string'},
        },
        ['id'],
      ),
    ),
    AiTool(
      'propose_complete_task',
      'Proposes ticking off an open task. Give its id from get_tasks. $_saved',
      _obj(
        {
          'id': _id,
          'title': {'type': 'string'},
        },
        ['id'],
      ),
    ),
    AiTool(
      'propose_delete_task',
      'Proposes deleting a task for good. Only when the user asks to delete or remove it. $_saved',
      _obj({'id': _id}, ['id']),
    ),
    AiTool(
      'propose_event',
      'Proposes a new calendar event. $_saved',
      _obj(
        {
          'title': {'type': 'string'},
          'start': _time,
          'end': {..._time, 'description': 'Default one hour after start, or the same day for all day.'},
          'allDay': {'type': 'boolean'},
          'location': {'type': 'string'},
          'calendar': {
            'type': 'string',
            'description': 'Which calendar, by name (from get_calendar), e.g. Personal, Work, Study. Default Personal.',
          },
          'repeat': {
            'type': 'string',
            'enum': ['none', 'daily', 'weekly', 'monthly', 'yearly'],
          },
          'remind_minutes': {'type': 'integer', 'description': 'Reminder this many minutes before.'},
          'notes': {'type': 'string'},
        },
        ['title', 'start'],
      ),
    ),
    AiTool(
      'propose_edit_event',
      'Proposes changing an event: move it to another time or day (reschedule), rename it, change the place or '
          'calendar. Give only what changes; a new start keeps the length. A repeating event moves as a whole. '
          'Events from imported calendars cannot be changed. $_saved',
      _obj(
        {
          'id': _id,
          'title': {'type': 'string'},
          'start': _time,
          'end': _time,
          'allDay': {'type': 'boolean'},
          'location': {'type': 'string'},
          'calendar': {'type': 'string'},
        },
        ['id'],
      ),
    ),
    AiTool(
      'propose_delete_event',
      'Proposes deleting an event (all its repeats). Only when the user asks to delete, cancel or remove it. $_saved',
      _obj({'id': _id}, ['id']),
    ),
    AiTool(
      'propose_note',
      'Proposes a new note. $_saved',
      _obj(
        {
          'title': {'type': 'string'},
          'body': {'type': 'string'},
        },
        ['body'],
      ),
    ),
    AiTool(
      'propose_edit_note',
      'Proposes changing a note: add text at the end (append), or replace its title or text. Prefer append '
          'unless the user wants it rewritten. $_saved',
      _obj(
        {
          'id': {'type': 'integer', 'description': 'The id from search_notes.'},
          'append': {'type': 'string', 'description': 'Text to add on a new line at the end.'},
          'title': {'type': 'string', 'description': 'New title.'},
          'body': {'type': 'string', 'description': 'New full text, replacing the old.'},
        },
        ['id'],
      ),
    ),
    AiTool(
      'propose_shopping',
      'Proposes an item for the shopping list. Call it once per item. $_saved',
      _obj(
        {
          'name': {'type': 'string'},
          'quantity': {'type': 'string'},
        },
        ['name'],
      ),
    ),
    AiTool(
      'propose_recurring',
      'Proposes a new recurring payment, subscription or recurring income. $_saved',
      _obj(
        {
          'name': {'type': 'string'},
          'amount': {'type': 'number'},
          'kind': {
            'type': 'string',
            'enum': ['payment', 'income'],
          },
          'category': {'type': 'string'},
          'period_months': {'type': 'integer', 'description': '1 monthly, 3 quarterly, 12 yearly.'},
          'next_date': _date,
          'account': {'type': 'string'},
        },
        ['name', 'amount'],
      ),
    ),
    AiTool(
      'propose_edit_recurring',
      'Proposes changing a recurring payment or subscription: new price, period, next date, category, account, '
          'or pausing (active false) and resuming it. Give only what changes. $_saved',
      _obj(
        {
          'id': {'type': 'integer', 'description': 'The id from get_recurring.'},
          'name': {'type': 'string'},
          'amount': {'type': 'number'},
          'period_months': {'type': 'integer'},
          'next_date': _date,
          'category': {'type': 'string'},
          'account': {'type': 'string'},
          'active': {'type': 'boolean'},
        },
        ['id'],
      ),
    ),
    AiTool(
      'propose_savings_deposit',
      'Proposes putting money into a savings goal (or taking it out with withdraw true). $_saved',
      _obj(
        {
          'goal': {'type': 'string', 'description': 'The goal name from get_savings.'},
          'amount': {'type': 'number'},
          'withdraw': {'type': 'boolean'},
          'note': {'type': 'string'},
          'date': _date,
        },
        ['goal', 'amount'],
      ),
    ),
    AiTool(
      'propose_budget_target',
      'Proposes the monthly spending budget in Wallet (the target the month is paced against). 0 removes it. $_saved',
      _obj(
        {
          'amount': {'type': 'number', 'description': 'Per month.'},
        },
        ['amount'],
      ),
    ),
    AiTool(
      'propose_work_hours',
      'Proposes logging a day in the Job work log: worked, from home, day off, holiday, sick or public holiday, '
          'with hours or start and end times. One call per day. Replaces what that day had. $_saved',
      _obj(
        {
          'date': _date,
          'status': {
            'type': 'string',
            'enum': ['work', 'remote', 'off', 'holiday', 'sick', 'public'],
            'description': 'Default work.',
          },
          'hours': {'type': 'number', 'description': 'Hours worked. Leave out for a normal day or with start and end.'},
          'start': _clock,
          'end': _clock,
          'break_minutes': {'type': 'integer'},
          'note': {'type': 'string'},
        },
        ['date'],
      ),
    ),
    AiTool(
      'propose_space_date',
      'Proposes an important date (exam, deadline, shift, hand-in) in a space such as University or Job. It goes '
          'into that space\'s calendar with a reminder. $_saved',
      _obj(
        {
          'space': {'type': 'string', 'description': 'The space name from get_spaces.'},
          'title': {'type': 'string'},
          'date': _date,
          'end_date': {..._date, 'description': 'Last day, for something that spans days.'},
          'time': {..._clock, 'description': 'Only when it has a time.'},
          'notes': {'type': 'string'},
        },
        ['space', 'title', 'date'],
      ),
    ),
    AiTool(
      'propose_habit_done',
      'Proposes ticking a habit off for a day. $_saved',
      _obj(
        {
          'name': {'type': 'string', 'description': 'The habit name from get_habits.'},
          'date': {..._date, 'description': 'Default today.'},
        },
        ['name'],
      ),
    ),
  ];

  List<AiTool> get tools => [...readTools, if (writes) ...writeTools];

  /// A few words for the "Looked at" line under an answer.
  static String labelFor(String tool) => switch (tool) {
    'get_calendar' => 'calendar',
    'get_tasks' => 'tasks',
    'get_transactions' => 'transactions',
    'get_money_summary' => 'spending',
    'get_recurring' => 'recurring payments',
    'get_accounts' => 'accounts',
    'get_savings' => 'savings',
    'get_investments' => 'investments',
    'search_notes' => 'notes',
    'get_habits' => 'habits',
    'get_shopping_list' => 'shopping list',
    'get_spaces' => 'spaces',
    'get_work_log' => 'work log',
    'get_applications' => 'applications',
    'get_weather' => 'weather',
    'search_hub' => 'search',
    _ => tool.startsWith('propose_') ? '' : tool,
  };

  /// Runs one tool and returns JSON for the model.
  Future<String> run(String name, Map<String, dynamic> args) async {
    try {
      final out = await _run(name, args);
      return jsonEncode(out);
    } catch (e) {
      return jsonEncode({'error': 'Could not read that: $e'});
    }
  }

  Future<Object?> _run(String name, Map<String, dynamic> a) async {
    String? s(String k) {
      final v = a[k]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    final today = dateOnly(clock());
    switch (name) {
      case 'get_calendar':
        final from = _parseDay(s('from')) ?? today;
        final to = _parseDay(s('to')) ?? addDays(from, 14);
        return events(from, addDays(to, 1), query: s('query'));
      case 'get_tasks':
        return tasks(
          status: s('status') ?? 'open',
          from: _parseDay(s('due_from')),
          to: _parseDay(s('due_to')),
          query: s('query'),
        );
      case 'get_transactions':
        final from = _parseDay(s('from')) ?? DateTime(today.year, today.month);
        final to = _parseDay(s('to')) ?? today;
        return transactions(
          from,
          addDays(to, 1),
          category: s('category'),
          kind: s('kind'),
          account: s('account'),
          query: s('query'),
          limit: (a['limit'] as num?)?.toInt() ?? 80,
        );
      case 'get_money_summary':
        final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(s('month') ?? '');
        return moneySummary(
          m == null ? DateTime(today.year, today.month) : DateTime(int.parse(m[1]!), int.parse(m[2]!)),
        );
      case 'get_recurring':
        return recurring();
      case 'get_accounts':
        return accounts();
      case 'get_savings':
        return savings();
      case 'get_investments':
        return investments();
      case 'search_notes':
        return notes(query: s('query'), limit: (a['limit'] as num?)?.toInt() ?? 15);
      case 'get_habits':
        return habits(days: ((a['days'] as num?)?.toInt() ?? 14).clamp(1, 120));
      case 'get_shopping_list':
        return shopping();
      case 'get_spaces':
        return spaces();
      case 'get_work_log':
        final from = _parseDay(s('from')) ?? DateTime(today.year, today.month);
        final to = _parseDay(s('to')) ?? DateTime(today.year, today.month + 1, 0);
        return workLog(from, addDays(to, 1));
      case 'get_applications':
        return applications();
      case 'get_weather':
        return weatherFor(s('city'));
      case 'search_hub':
        return search(s('query') ?? '');
    }
    if (name.startsWith('propose_') && writes) return await _propose(name.substring(8), a);
    return {'error': 'There is no tool called $name.'};
  }

  /// The card type each propose_ tool makes.
  static const _proposeTypes = {
    'complete_task': 'complete',
    'savings_deposit': 'saving',
    'work_hours': 'work_day',
    'habit_done': 'habit',
  };

  Future<Map<String, Object?>> _propose(String what, Map<String, dynamic> a) async {
    final fields = Map<String, dynamic>.of(a);
    final type = _proposeTypes[what] ?? what;
    if (fields.containsKey('next_date')) fields['next'] = fields.remove('next_date');
    if (fields.containsKey('period_months')) fields['period'] = fields.remove('period_months');
    final action = AgentAction(type, fields);
    if (!AgentAction.types.contains(type) || !action.valid) {
      return {'proposed': false, 'error': 'Something needed is missing, so nothing was proposed.'};
    }
    final problem = await action.resolve(db, now: clock());
    if (problem != null) return {'proposed': false, 'error': problem};
    proposals.add(action);
    final detail = action.detailIn(currency);
    return {
      'proposed': true,
      'card': '${action.label}: ${action.summaryIn(currency)}${detail == null ? '' : ' ($detail)'}',
      'note':
          'The user sees this as a card with a ${action.verb} button; nothing changes until they tap it. '
          'Do not say it is done.',
    };
  }

  static DateTime? _parseDay(String? v) {
    if (v == null) return null;
    final d = DateTime.tryParse(v);
    return d == null ? null : dateOnly(d);
  }

  // Calendar

  Future<Map<String, Object?>> events(DateTime from, DateTime to, {String? query, int limit = 300}) async {
    final cals = {for (final c in await db.watchCalendars().first) c.id: c};
    final rows =
        await (db.select(db.events)..where(
              (e) =>
                  e.start.isSmallerThanValue(to) & (e.end.isBiggerOrEqualValue(from) | e.repeat.equals('none').not()),
            ))
            .get();
    final q = query?.toLowerCase();
    final out = <(DateTime, Map<String, Object?>)>[];
    for (final e in rows) {
      if (q != null && !'${e.title} ${e.location} ${e.notes}'.toLowerCase().contains(q)) continue;
      final cal = cals[e.calendarId];
      for (final start in occurrences(e, from, to)) {
        final end = occurrenceEnd(e, start);
        final lastDay = e.allDay ? addDays(dateOnly(end), -1) : null;
        out.add((
          start,
          {
            'id': e.id,
            'title': e.title,
            if (e.allDay) 'date': day(start) else 'start': _dayTime.format(start),
            if (e.allDay && lastDay != null && lastDay.isAfter(start)) 'until': day(lastDay),
            if (!e.allDay) 'end': _dayTime.format(end),
            if (e.allDay) 'allDay': true,
            'weekday': DateFormat.EEEE().format(start),
            if (e.location.isNotEmpty) 'location': e.location,
            if (e.notes.trim().isNotEmpty) 'notes': _clip(e.notes, 200),
            if (e.repeat != 'none') 'repeats': e.repeat,
            if (cal != null) 'calendar': cal.name,
            if (cal != null && !cal.visible) 'hiddenCalendar': true,
            if (cal?.icsUrl != null) 'readOnly': true,
          },
        ));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return {
      'from': day(from),
      'to': day(addDays(to, -1)),
      'count': out.length,
      'events': [for (final o in out.take(limit)) o.$2],
      if (out.length > limit) 'more': out.length - limit,
      'calendars': [
        for (final c in cals.values)
          {'name': c.name, if (c.icsUrl != null) 'imported': true, if (!c.visible) 'hidden': true},
      ],
    };
  }

  // Tasks

  Future<Map<String, Object?>> tasks({String status = 'open', DateTime? from, DateTime? to, String? query}) async {
    final spaceNames = {for (final s in await db.watchSpaces().first) s.id: s.name};
    final today = dateOnly(clock());
    final q = query?.toLowerCase();
    final all = await db.watchTodos().first;
    final list = all.where((t) {
      if (status == 'open' && t.done) return false;
      if (status == 'done' && !t.done) return false;
      if (from != null && (t.due == null || t.due!.isBefore(from))) return false;
      if (to != null && (t.due == null || t.due!.isAfter(to))) return false;
      if (q != null && !'${t.title} ${t.details}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    return {
      'count': list.length,
      'tasks': [
        for (final t in list.take(150))
          {
            'id': t.id,
            'title': t.title,
            if (t.details.trim().isNotEmpty) 'details': _clip(t.details, 200),
            'due': t.due == null ? null : day(t.due!),
            if (t.due != null && !t.done && dateOnly(t.due!).isBefore(today)) 'overdue': true,
            if (t.important) 'important': true,
            if (t.remindAt != null) 'remind': _dayTime.format(t.remindAt!),
            if (t.repeat != 'none') 'repeats': t.repeat,
            if (t.spaceId != null && spaceNames[t.spaceId] != null) 'space': spaceNames[t.spaceId],
            if (t.done) 'done': t.completedAt == null ? true : day(t.completedAt!),
          },
      ],
      if (list.length > 150) 'more': list.length - 150,
    };
  }

  // Money

  Future<Map<String, Object?>> transactions(
    DateTime from,
    DateTime to, {
    String? category,
    String? kind,
    String? account,
    String? query,
    int limit = 80,
  }) async {
    final all = await db.watchEntries(from, to).first;
    final list = all.where((e) {
      if (category != null && e.category.toLowerCase() != category.toLowerCase()) return false;
      if (kind != null && e.kind.name != kind) return false;
      if (account != null && e.account.toLowerCase() != account.toLowerCase()) return false;
      if (query != null && !'${e.note} ${e.category}'.toLowerCase().contains(query.toLowerCase())) return false;
      return true;
    }).toList();
    final sum = MonthSummary(list);
    final top = sum.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'from': day(from),
      'to': day(addDays(to, -1)),
      'count': list.length,
      'income': _m(sum.income),
      'spent': _m(sum.out),
      'byCategory': {for (final e in top) e.key: _m(e.value)},
      'entries': [for (final e in list.take(limit.clamp(1, 500))) _entry(e)],
      if (list.length > limit) 'more': list.length - limit,
    };
  }

  Map<String, Object?> _entry(Entry e) => {
    'date': day(e.date),
    'amount': _m(e.amountCents),
    'kind': e.kind.name,
    'category': e.category,
    if (e.note.isNotEmpty) 'note': e.note,
    if (e.account.isNotEmpty) 'account': e.account,
    if (e.subscriptionId != null) 'fromRecurring': true,
  };

  Future<Map<String, Object?>> moneySummary(DateTime month) async {
    final now = clock();
    final next = DateTime(month.year, month.month + 1);
    final prev = DateTime(month.year, month.month - 1);
    final entries = await db.watchEntries(prev, next).first;
    final cur = MonthSummary(entries.where((e) => !e.date.isBefore(month) && !e.date.isAfter(now)).toList());
    final before = MonthSummary(entries.where((e) => e.date.isBefore(month)).toList());
    final budgets = await db.watchBudgets().first;
    final subs = (await db.watchSubscriptions().first).where((s) => s.active).toList();
    final ahead = subs.where((s) => s.nextDate.isAfter(now) && s.nextDate.isBefore(next)).toList();
    final target = int.tryParse((await db.readSettings())['wallet.target'] ?? '');
    final top = cur.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'month': DateFormat('MMMM y').format(month),
      'income': _m(cur.income),
      'spent': _m(cur.out),
      'net': _m(cur.net),
      'byCategory': {for (final e in top) e.key: _m(e.value)},
      'byKind': {for (final e in cur.byKind.entries) e.key.name: _m(e.value)},
      if (target != null && target > 0) 'monthlySpendingTarget': _m(target),
      'budgets': [
        for (final b in budgets)
          {'category': b.category, 'budget': _m(b.monthlyCents), 'spent': _m(cur.byCategory[b.category] ?? 0)},
      ],
      'recurringStillToCome': [
        for (final s in ahead)
          {'name': s.name, 'amount': _m(s.amountCents), 'date': day(s.nextDate), 'in': s.kind == EntryKind.income},
      ],
      'monthBefore': {'income': _m(before.income), 'spent': _m(before.out)},
    };
  }

  Future<Map<String, Object?>> recurring() async {
    final subs = await db.watchSubscriptions().first;
    var outMonthly = 0, inMonthly = 0;
    for (final s in subs.where((s) => s.active)) {
      if (s.kind == EntryKind.income) {
        inMonthly += monthlyCents(s);
      } else if (s.kind.sign < 0) {
        outMonthly += monthlyCents(s);
      }
    }
    return {
      'count': subs.length,
      'monthlyOut': _m(outMonthly),
      'monthlyIn': _m(inMonthly),
      'items': [
        for (final s in subs)
          {
            'id': s.id,
            'name': s.name,
            'amount': _m(s.amountCents),
            'type': s.kind == EntryKind.income
                ? 'income'
                : (s.kind == EntryKind.subscription ? 'payment' : s.kind.name),
            'category': s.category,
            'every': periodLabel(s.periodMonths),
            if (s.periodMonths != 1) 'perMonth': _m(monthlyCents(s)),
            'next': day(s.nextDate),
            if (s.account.isNotEmpty) 'account': s.account,
            if (!s.active) 'paused': true,
          },
      ],
    };
  }

  Future<Map<String, Object?>> accounts() async {
    final now = clock();
    final month = DateTime(now.year, now.month);
    final list = await db.watchAccounts().first;
    final out = <Map<String, Object?>>[];
    for (final a in list) {
      final entries = await db.watchAccountEntries(a.name).first;
      var balance = a.balanceCents, inM = 0, outM = 0;
      for (final e in entries) {
        final signed = e.kind.sign * e.amountCents;
        if (a.balanceAt != null && e.date.isAfter(a.balanceAt!) && !e.date.isAfter(now)) balance += signed;
        if (!e.date.isBefore(month) && !e.date.isAfter(now)) {
          if (signed > 0) inM += signed;
          if (signed < 0) outM -= signed;
        }
      }
      out.add({
        'name': a.name,
        if (a.balanceAt != null) 'balance': _m(balance) else 'balance': 'not set',
        if (a.balanceAt != null) 'balanceSetOn': day(a.balanceAt!),
        'thisMonthIn': _m(inM),
        'thisMonthOut': _m(outM),
      });
    }
    return {'accounts': out};
  }

  Future<Map<String, Object?>> savings() async {
    final goals = await db.watchGoals().first;
    final moves = await db.watchMoves().first;
    return {
      'goals': [
        for (final g in goals)
          {
            'id': g.id,
            'name': g.name,
            'target': _m(g.targetCents),
            'saved': _m(moves.where((m) => m.goalId == g.id).fold(0, (a, m) => a + m.amountCents)),
            if (g.deadline != null) 'deadline': day(g.deadline!),
            if (g.archived) 'archived': true,
          },
      ],
      'recentMoves': [
        for (final m in moves.take(15))
          {
            'goal': goals.where((g) => g.id == m.goalId).firstOrNull?.name,
            'amount': _m(m.amountCents),
            'date': day(m.date),
            if (m.note.isNotEmpty) 'note': m.note,
          },
      ],
    };
  }

  Future<Map<String, Object?>> investments() async {
    final list = await db.watchHoldings().first;
    var value = 0, invested = 0;
    final rows = <Map<String, Object?>>[];
    for (final h in list) {
      final v = (h.units * h.price * 100).round();
      value += v;
      invested += h.investedCents;
      rows.add({
        'name': h.name,
        if (h.symbol.isNotEmpty) 'symbol': h.symbol,
        'kind': h.kind,
        'units': h.units,
        'price': h.price,
        'value': _m(v),
        'invested': _m(h.investedCents),
        'gain': _m(v - h.investedCents),
        if (h.priceAt != null) 'priceOn': day(h.priceAt!),
        if (h.account.isNotEmpty) 'account': h.account,
      });
    }
    return {'value': _m(value), 'invested': _m(invested), 'gain': _m(value - invested), 'holdings': rows};
  }

  // Notes, habits, shopping

  Future<Map<String, Object?>> notes({String? query, int limit = 15}) async {
    final list = await db.watchNotes(query: query ?? '').first;
    return {
      'count': list.length,
      'notes': [
        for (final n in list.take(limit.clamp(1, 60)))
          {
            'id': n.id,
            if (n.title.isNotEmpty) 'title': n.title,
            'text': _clip(n.body, 1500),
            if (n.pinned) 'pinned': true,
            'updated': day(n.updatedAt),
          },
      ],
    };
  }

  Future<Map<String, Object?>> habits({int days = 14}) async {
    final today = dateOnly(clock());
    final list = await db.watchHabits().first;
    final checks = await db.habitChecksSince(addDays(today, -400));
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return {
      'habits': [
        for (final h in list)
          () {
            final done = {for (final c in checks.where((c) => c.habitId == h.id)) c.day};
            final since = AppDatabase.dayKey(addDays(today, -days + 1));
            return {
              'id': h.id,
              'name': h.name,
              'on': h.days == '1111111' || h.days.length != 7
                  ? 'every day'
                  : [
                      for (var i = 0; i < 7; i++)
                        if (h.days[i] == '1') names[i],
                    ].join(', '),
              'streak': habitStreak(h, done, now: today),
              'doneToday': done.contains(AppDatabase.dayKey(today)),
              'dueToday': habitDueOn(h, today),
              'doneDays': (done.where((d) => d.compareTo(since) >= 0).toList()..sort()),
            };
          }(),
      ],
    };
  }

  Future<Map<String, Object?>> shopping() async {
    final list = await db.watchShopping().first;
    Map<String, Object?> one(ShoppingItem i) => {
      'name': i.name,
      if (i.quantity.isNotEmpty) 'quantity': i.quantity,
      if (i.store.isNotEmpty) 'store': i.store,
    };
    return {
      'toBuy': [for (final i in list.where((i) => !i.done)) one(i)],
      'bought': [for (final i in list.where((i) => i.done).take(30)) one(i)],
    };
  }

  // Spaces, work, applications

  Future<Map<String, Object?>> spaces() async {
    final today = dateOnly(clock());
    final list = await db.watchSpaces().first;
    final cals = {for (final c in await db.watchCalendars().first) c.id: c.name};
    final ahead = list.any((s) => s.calendarId != null)
        ? (await events(today, addDays(today, 90), limit: 400))['events'] as List
        : const [];
    final out = <Map<String, Object?>>[];
    for (final s in list) {
      final items = await db.watchSpaceItems(s.id).first;
      final todos = (await db.watchSpaceTodos(s.id).first).where((t) => !t.done).toList();
      final calName = cals[s.calendarId];
      final dates = calName == null
          ? const []
          : ahead.where((e) => (e as Map)['calendar'] == calName).take(40).toList();
      out.add({
        'name': s.name,
        'type': switch (s.icon) {
          'school' => 'study',
          'work' => 'job',
          'science' => 'research',
          _ => s.icon,
        },
        'saved': [
          for (final i in items.take(30))
            {
              'kind': i.kind,
              if (i.title.isNotEmpty) 'title': i.title,
              if (i.body.trim().isNotEmpty) 'text': _clip(i.body, 400),
              if (i.kind == 'link' && i.url.isNotEmpty) 'url': i.url,
            },
        ],
        'openTasks': [
          for (final t in todos.take(40)) {'id': t.id, 'title': t.title, if (t.due != null) 'due': day(t.due!)},
        ],
        'upcomingDates': dates,
      });
    }
    return {'spaces': out};
  }

  Future<Map<String, Object?>> workLog(DateTime from, DateTime to) async {
    final days = (await db.watchWorkDays(from, to).first)..sort((a, b) => a.day.compareTo(b.day));
    final count = <String, int>{};
    var hours = 0.0;
    for (final d in days) {
      count[d.status] = (count[d.status] ?? 0) + 1;
      if (d.status == 'work' || d.status == 'remote') hours += d.hours ?? 0;
    }
    final schedule = WorkSchedule.parse((await db.readSettings())[WorkSchedule.key]);
    return {
      'from': day(from),
      'to': day(addDays(to, -1)),
      'contract': schedule.describe(),
      'totals': count,
      'hours': hours,
      'days': [
        for (final d in days)
          {
            'day': d.day,
            'status': d.status,
            if (d.hours != null) 'hours': d.hours,
            if (d.note.isNotEmpty) 'note': d.note,
          },
      ],
    };
  }

  Future<Map<String, Object?>> applications() async {
    final list = await db.watchApplications().first;
    return {
      'applications': [
        for (final a in list)
          {
            'company': a.company,
            if (a.role.isNotEmpty) 'role': a.role,
            'status': a.status,
            if (a.deadline != null) 'deadline': day(a.deadline!),
            if (a.appliedAt != null) 'applied': day(a.appliedAt!),
            if (a.location.isNotEmpty) 'location': a.location,
            if (a.notes.trim().isNotEmpty) 'notes': _clip(a.notes, 200),
          },
      ],
    };
  }

  // Weather

  Future<Map<String, Object?>> weatherFor(String? city) async {
    final cities = await db.watchCities().first;
    if (cities.isEmpty) return {'error': 'No cities saved in Weather.'};
    final c = cities.firstWhere(
      (c) => city != null && c.name.toLowerCase().contains(city.toLowerCase()),
      orElse: () => cities.first,
    );
    final lookup = weather ?? (c) => WeatherService.instance.forecast(c.latitude, c.longitude);
    final Forecast f;
    try {
      f = await lookup(c).timeout(const Duration(seconds: 12));
    } catch (_) {
      return {'city': c.name, 'error': 'The forecast could not be loaded right now.'};
    }
    return {
      'city': c.name,
      'savedCities': [for (final x in cities) x.name],
      'now': {
        'temperatureC': f.temperature.round(),
        'feelsLikeC': f.feelsLike.round(),
        'sky': WeatherCode.label(f.code),
        'windKmh': f.wind.round(),
        'humidity': f.humidity,
      },
      'days': [
        for (final d in f.days.take(7))
          {
            'date': day(d.date),
            'sky': WeatherCode.label(d.code),
            'minC': d.min.round(),
            'maxC': d.max.round(),
            'rainChance': d.rainChance,
          },
      ],
    };
  }

  // Search

  Future<Map<String, Object?>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return {'error': 'Give something to search for.'};
    final today = dateOnly(clock());
    bool hit(String s) => s.toLowerCase().contains(q);
    final notesHit = (await db.watchNotes(query: query.trim()).first).take(10);
    final todos = (await db.watchTodos().first).where((t) => hit('${t.title} ${t.details}')).take(20);
    final ev = await events(addDays(today, -365), addDays(today, 366), query: q, limit: 30);
    final entries = (await db.watchEntries(addDays(today, -730), addDays(today, 1)).first)
        .where((e) => hit('${e.note} ${e.category} ${e.account}'))
        .toList();
    final subs = (await db.watchSubscriptions().first).where((s) => hit('${s.name} ${s.category}'));
    final shop = (await db.watchShopping().first).where((i) => hit(i.name));
    final spaceItems = (await (db.select(db.spaceItems)..orderBy([(i) => OrderingTerm.desc(i.updatedAt)])).get())
        .where((i) => hit('${i.title} ${i.body} ${i.url}'))
        .take(10);
    return {
      'notes': [
        for (final n in notesHit) {'id': n.id, if (n.title.isNotEmpty) 'title': n.title, 'text': _clip(n.body, 300)},
      ],
      'tasks': [
        for (final t in todos)
          {'id': t.id, 'title': t.title, 'due': t.due == null ? null : day(t.due!), 'done': t.done},
      ],
      'events': ev['events'],
      'entries': {
        'count': entries.length,
        'total': _m(MonthSummary(entries).out),
        'latest': [for (final e in entries.take(15)) _entry(e)],
      },
      'recurring': [
        for (final s in subs) {'id': s.id, 'name': s.name, 'amount': _m(s.amountCents), 'next': day(s.nextDate)},
      ],
      'shopping': [
        for (final i in shop) {'name': i.name, 'bought': i.done},
      ],
      'spaceItems': [
        for (final i in spaceItems) {'title': i.title, if (i.body.isNotEmpty) 'text': _clip(i.body, 200)},
      ],
    };
  }

  static String _clip(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > n ? '${t.substring(0, n)}…' : t;
  }

  /// Everything a model without tools needs in one block: the next two weeks, all recurring money, this
  /// month's spending, open tasks, notes, habits, shopping, spaces and more. Used for Claude Code, the
  /// Claude app and models that cannot call tools.
  Future<String> snapshot() async {
    final today = dateOnly(clock());
    final parts = <String, Future<Object?>>{
      'Calendar, today and the next 14 days': events(today, addDays(today, 15), limit: 120),
      'Open tasks': tasks(),
      'Recurring payments and income': recurring(),
      'Accounts': accounts(),
      'This month\'s money': moneySummary(DateTime(today.year, today.month)),
      'Latest wallet entries': transactions(addDays(today, -45), addDays(today, 1), limit: 30),
      'Savings': savings(),
      'Investments': investments(),
      'Recent notes': notes(limit: 10),
      'Habits': habits(days: 7),
      'Shopping list': shopping(),
      'Spaces': spaces(),
      'Work log this month': workLog(DateTime(today.year, today.month), DateTime(today.year, today.month + 1)),
      'Applications': applications(),
    };
    final out = StringBuffer();
    for (final e in parts.entries) {
      try {
        out.writeln('## ${e.key}\n${jsonEncode(await e.value)}');
      } catch (_) {}
    }
    final cities = await db.watchCities().first;
    if (cities.isNotEmpty) {
      final f = WeatherService.instance.cached(cities.first.latitude, cities.first.longitude);
      if (f != null) {
        out.writeln(
          '## Weather in ${cities.first.name}\nNow ${f.temperature.round()}°C, ${WeatherCode.label(f.code)}. '
          '${f.days.take(3).map((d) => '${day(d.date)}: ${d.min.round()} to ${d.max.round()}°C, ${WeatherCode.label(d.code)}, rain ${d.rainChance}%').join('; ')}.',
        );
      }
    }
    return out.toString().trim();
  }
}
