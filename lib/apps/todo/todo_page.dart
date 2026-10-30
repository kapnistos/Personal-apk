import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/reminders.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../spaces/space_model.dart';

enum TodoFilter { open, today, important, done }

class TodoPage extends StatefulWidget {
  const TodoPage({super.key, this.spaceId});

  /// Shows only the tasks of one space when set.
  final int? spaceId;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  TodoFilter _filter = TodoFilter.open;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-do'),
        actions: [
          if (_filter == TodoFilter.done)
            TextButton(
              onPressed: () async {
                final n = await db.clearCompletedTodos();
                if (context.mounted && n > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cleared $n completed ${n == 1 ? 'task' : 'tasks'}')));
                }
              },
              child: const Text('Clear all'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Space>>(
        stream: db.watchSpaces(),
        builder: (context, spaceSnap) {
          final spaces = {for (final s in spaceSnap.data ?? const <Space>[]) s.id: s};
          return StreamBuilder<List<Todo>>(
            stream: widget.spaceId == null ? db.watchTodos() : db.watchSpaceTodos(widget.spaceId!),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final all = snap.data!;
              final counts = {for (final f in TodoFilter.values) f: applyTodoFilter(all, f).length};
              final groups = groupTodos(applyTodoFilter(all, _filter), byDate: _filter != TodoFilter.done);
              return Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final f in TodoFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              label: Text('${switch (f) {
                                TodoFilter.open => 'Open',
                                TodoFilter.today => 'Today',
                                TodoFilter.important => 'Important',
                                TodoFilter.done => 'Done',
                              }}${counts[f]! > 0 && f != TodoFilter.done ? '  ${counts[f]}' : ''}'),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: groups.isEmpty
                        ? EmptyState(
                            icon: _filter == TodoFilter.done ? Icons.history_rounded : Icons.check_circle_outline_rounded,
                            title: _filter == TodoFilter.done ? 'Nothing completed yet' : 'All clear',
                            message: _filter == TodoFilter.done
                                ? 'Finished tasks show up here.'
                                : 'Add a task below. Try "Call the bank tomorrow 10:00" or "Gym every monday 18:00".',
                          )
                        : ContentWidth(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              children: [
                                for (final (label, items) in groups) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                                    child: Row(children: [
                                      SectionLabel(label),
                                      const SizedBox(width: 6),
                                      Text('${items.length}',
                                          style: TextStyle(fontSize: 12.5, color: Palette.of(context).muted)),
                                    ]),
                                  ),
                                  for (final t in items) TodoTile(todo: t, space: spaces[t.spaceId]),
                                ],
                              ],
                            ),
                          ),
                  ),
                  _QuickAdd(spaceId: widget.spaceId),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// True when the task is due, or has a reminder, before the end of today.
bool isTodayTask(Todo t, {DateTime? now}) {
  final tomorrow = addDays(dateOnly(now ?? DateTime.now()), 1);
  return !t.done &&
      ((t.due != null && t.due!.isBefore(tomorrow)) || (t.remindAt != null && t.remindAt!.isBefore(tomorrow)));
}

List<Todo> applyTodoFilter(List<Todo> all, TodoFilter f) => switch (f) {
      TodoFilter.open => all.where((t) => !t.done).toList(),
      TodoFilter.today => all.where((t) => isTodayTask(t)).toList(),
      TodoFilter.important => all.where((t) => !t.done && t.important).toList(),
      TodoFilter.done => all.where((t) => t.done).toList()
        ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt)),
    };

/// Splits tasks into Overdue, Today, Tomorrow, This week, Later and No date.
List<(String, List<Todo>)> groupTodos(List<Todo> todos, {bool byDate = true, DateTime? now}) {
  if (todos.isEmpty) return const [];
  if (!byDate) return [('Completed', todos)];
  final today = dateOnly(now ?? DateTime.now());
  final buckets = <String, List<Todo>>{};
  for (final t in todos) {
    final when = t.due ?? t.remindAt;
    final String key;
    if (when == null) {
      key = 'No date';
    } else {
      final d = daysBetween(today, when);
      key = d < 0
          ? 'Overdue'
          : d == 0
              ? 'Today'
              : d == 1
                  ? 'Tomorrow'
                  : d < 7
                      ? 'This week'
                      : 'Later';
    }
    (buckets[key] ??= []).add(t);
  }
  const order = ['Overdue', 'Today', 'Tomorrow', 'This week', 'Later', 'No date'];
  return [
    for (final k in order)
      if (buckets[k] != null)
        (
          k,
          buckets[k]!
            ..sort((a, b) {
              if (a.important != b.important) return a.important ? -1 : 1;
              final x = a.due ?? a.remindAt, y = b.due ?? b.remindAt;
              if (x != null && y != null) return x.compareTo(y);
              return b.createdAt.compareTo(a.createdAt);
            })
        ),
  ];
}

class TodoTile extends StatelessWidget {
  const TodoTile({super.key, required this.todo, this.dense = false, this.space});
  final Todo todo;
  final bool dense;
  final Space? space;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    final now = DateTime.now();
    final overdue = !todo.done && todo.due != null && daysBetween(now, todo.due!) < 0;
    final remind = todo.remindAt;
    final parts = <List<InlineSpan>>[
      if (space != null)
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(spaceIcon(space!.icon), size: 13, color: Color(space!.color)),
            ),
          ),
          TextSpan(text: space!.name),
        ],
      if (todo.due != null)
        [TextSpan(text: friendlyDay(todo.due!), style: overdue ? TextStyle(color: p.danger) : null)],
      if (remind != null && !todo.done)
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.notifications_none_rounded, size: 13, color: p.muted),
            ),
          ),
          TextSpan(
              text: todo.due != null && daysBetween(todo.due!, remind) == 0
                  ? DateFormat.Hm().format(remind)
                  : '${friendlyDay(remind)} ${DateFormat.Hm().format(remind)}'),
        ],
      if (todo.repeat != 'none')
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.repeat_rounded, size: 13, color: p.muted),
          ),
        ],
      if (todo.details.isNotEmpty) [TextSpan(text: todo.details.split('\n').first)],
    ];
    final spans = <InlineSpan>[
      for (var i = 0; i < parts.length; i++) ...[if (i > 0) const TextSpan(text: '  ·  '), ...parts[i]],
    ];
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => editTodo(context, todo),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
          child: Row(
            children: [
              Checkbox(
                value: todo.done,
                shape: const CircleBorder(),
                activeColor: TileColors.todo,
                onChanged: (v) {
                  if (v ?? false) HapticFeedback.lightImpact();
                  db.setTodoDone(todo.id, v ?? false);
                  if ((v ?? false) && todo.repeat != 'none') {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text('Done. It repeats ${todoRepeatLabels[todo.repeat]!.toLowerCase()}.')));
                  }
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 15,
                        decoration: todo.done ? TextDecoration.lineThrough : null,
                        color: todo.done ? p.muted : p.ink,
                      ),
                    ),
                    if (spans.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: spans),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: p.muted),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: todo.important ? 'Unmark important' : 'Mark important',
                visualDensity: VisualDensity.compact,
                icon: Icon(todo.important ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: todo.important ? const Color(0xFFE0A526) : p.muted),
                onPressed: () => db.updateTodo(todo.copyWith(important: !todo.important)),
              ),
            ],
          ),
        ),
      ),
    );
    if (dense) return tile;
    return Dismissible(
      key: ValueKey(todo.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(color: TileColors.todo, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.check_rounded, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          if (!todo.done) HapticFeedback.lightImpact();
          await db.setTodoDone(todo.id, !todo.done);
          return false;
        }
        return true;
      },
      onDismissed: (_) {
        db.deleteTodo(todo.id);
        showUndo(context, 'Task deleted', () => db.restoreTodo(todo));
      },
      child: tile,
    );
  }
}

/// What quick-add understood from a line of text.
class QuickTask {
  const QuickTask(this.title, {this.due, this.remindAt, this.repeat = 'none', this.important = false});
  final String title;
  final DateTime? due;
  final DateTime? remindAt;
  final String repeat;
  final bool important;
}

const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

int? _weekday(String w) {
  if (w.length < 3) return null;
  final i = _weekdays.indexWhere((d) => d == w || d.substring(0, 3) == w);
  return i < 0 ? null : i + 1;
}

/// Reads "18:00", "9.30", "6pm" or "9am".
(int, int)? _time(String w) {
  var m = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(w);
  if (m != null) {
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    return h < 24 && min < 60 ? (h, min) : null;
  }
  m = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)$').firstMatch(w);
  if (m != null) {
    var h = int.parse(m[1]!);
    final min = int.parse(m[2] ?? '0');
    if (h < 1 || h > 12 || min > 59) return null;
    if (m[3] == 'pm' && h != 12) h += 12;
    if (m[3] == 'am' && h == 12) h = 0;
    return (h, min);
  }
  return null;
}

/// Understands trailing words like "tomorrow", "fri 18:00", "at 9am", "every week" and "!".
QuickTask parseQuickTask(String input, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = dateOnly(clock);
  final words = input.trim().split(RegExp(r'\s+'));
  DateTime? day;
  (int, int)? time;
  var repeat = 'none';
  var important = false;
  // Eat recognised words from the end, keeping at least one word of title.
  while (words.length > 1) {
    final w = words.last.toLowerCase();
    final prev = words.length > 2 ? words[words.length - 2].toLowerCase() : null;
    if (w == '!' && !important) {
      important = true;
    } else if (time == null && _time(w) != null) {
      time = _time(w);
      if (prev == 'at') words.removeLast();
    } else if (time == null && prev == 'at' && RegExp(r'^\d{1,2}$').hasMatch(w) && int.parse(w) < 24) {
      time = (int.parse(w), 0);
      words.removeLast();
    } else if (day == null && repeat == 'none' && prev == 'every') {
      final wd = _weekday(w);
      final r = switch (w) {
        'day' => 'daily',
        'weekday' => 'weekdays',
        'week' => 'weekly',
        'month' => 'monthly',
        'year' => 'yearly',
        _ => wd != null ? 'weekly' : null,
      };
      if (r == null) break;
      repeat = r;
      if (wd != null) {
        var delta = wd - today.weekday;
        if (delta < 0) delta += 7;
        day = addDays(today, delta);
      }
      words.removeLast();
    } else if (day == null && w == 'today') {
      day = today;
    } else if (day == null && w == 'tomorrow') {
      day = addDays(today, 1);
    } else if (day == null && _weekday(w) != null) {
      var delta = _weekday(w)! - today.weekday;
      if (delta <= 0) delta += 7;
      day = addDays(today, delta);
    } else {
      break;
    }
    words.removeLast();
  }
  if (day == null && time == null && repeat == 'none' && !important) return QuickTask(input.trim());
  DateTime? remind;
  if (time != null) {
    final d = day ?? today;
    remind = DateTime(d.year, d.month, d.day, time.$1, time.$2);
    // "18:00" alone, when it's already later than that, means tomorrow.
    if (day == null && remind.isBefore(clock)) remind = addDays(remind, 1);
    day ??= dateOnly(remind);
  }
  if (repeat == 'daily' || repeat == 'weekdays' || repeat == 'monthly' || repeat == 'yearly') day ??= today;
  return QuickTask(words.join(' '), due: day, remindAt: remind, repeat: repeat, important: important);
}

/// Kept for older callers: just the title and due day.
(String, DateTime?) parseQuickDue(String input, {DateTime? now}) {
  final q = parseQuickTask(input, now: now);
  return (q.title, q.due);
}

class _QuickAdd extends StatefulWidget {
  const _QuickAdd({this.spaceId});
  final int? spaceId;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  QuickTask? _preview;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final q = parseQuickTask(text);
    await context.db.addTodo(q.title,
        due: q.due, remindAt: q.remindAt, repeat: q.repeat, important: q.important, spaceId: widget.spaceId);
    if (q.remindAt != null) await Reminders.instance.ensurePermission();
    _controller.clear();
    setState(() => _preview = null);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final q = _preview;
    final hint = q == null || (q.due == null && q.remindAt == null && q.repeat == 'none' && !q.important)
        ? null
        : [
            if (q.due != null) friendlyDay(q.due!),
            if (q.remindAt != null) 'reminder ${DateFormat.Hm().format(q.remindAt!)}',
            if (q.repeat != 'none') todoRepeatLabels[q.repeat]!.toLowerCase(),
            if (q.important) 'important',
          ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 10, 10 + MediaQuery.paddingOf(context).bottom),
      child: ContentWidth(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Text(hint, style: const TextStyle(fontSize: 13.5, color: TileColors.todo)),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setState(() => _preview = v.trim().isEmpty ? null : parseQuickTask(v)),
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: 'Add a task', prefixIcon: Icon(Icons.add_rounded)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Add',
                onPressed: _submit,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

Future<void> editTodo(BuildContext context, Todo todo) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Hub(db: context.db, settings: context.settings, child: _TodoEditor(todo: todo)),
  );
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({required this.todo});
  final Todo todo;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  late final _title = TextEditingController(text: widget.todo.title);
  late final _details = TextEditingController(text: widget.todo.details);
  late DateTime? _due = widget.todo.due;
  late bool _important = widget.todo.important;
  late DateTime? _remind = widget.todo.remindAt;
  late String _repeat = widget.todo.repeat;
  late int? _spaceId = widget.todo.spaceId;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final base = _remind ?? (_due != null ? DateTime(_due!.year, _due!.month, _due!.day, 9) : now.add(const Duration(hours: 1)));
    final day = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: dateOnly(now),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    setState(() => _remind = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final db = context.db;
    await db.updateTodo(widget.todo.copyWith(
      title: title,
      details: _details.text.trim(),
      due: Value(_due),
      remindAt: Value(_remind),
      important: _important,
      repeat: _repeat,
      spaceId: Value(_spaceId),
    ));
    if (_remind != null && _remind != widget.todo.remindAt) await Reminders.instance.ensurePermission();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 18);
    final presets = <String, DateTime>{
      'In 1 hour': DateTime(now.year, now.month, now.day, now.hour + 1, now.minute),
      if (evening.isAfter(now.add(const Duration(minutes: 30)))) 'This evening': evening,
      'Tomorrow 9:00': DateTime(now.year, now.month, now.day + 1, 9),
      if (_due != null && DateTime(_due!.year, _due!.month, _due!.day, 9).isAfter(now))
        'On the day 9:00': DateTime(_due!.year, _due!.month, _due!.day, 9),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(hintText: 'Task'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Details'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InputChip(
                  avatar: Icon(Icons.event_outlined, size: 18, color: p.muted),
                  label: Text(_due == null ? 'Add due date' : friendlyDay(_due!)),
                  onPressed: _pickDate,
                  onDeleted: _due == null ? null : () => setState(() => _due = null),
                ),
                InputChip(
                  avatar: Icon(Icons.notifications_none_rounded, size: 18, color: p.muted),
                  label: Text(_remind == null
                      ? 'Remind me'
                      : '${friendlyDay(_remind!)} ${DateFormat.Hm().format(_remind!)}'),
                  onPressed: _pickReminder,
                  onDeleted: _remind == null ? null : () => setState(() => _remind = null),
                ),
                FilterChip(
                  avatar: Icon(_important ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 18, color: _important ? const Color(0xFFE0A526) : p.muted),
                  showCheckmark: false,
                  label: const Text('Important'),
                  selected: _important,
                  onSelected: (v) => setState(() => _important = v),
                ),
              ],
            ),
            if (_remind == null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final MapEntry(key: label, value: at) in presets.entries)
                  ActionChip(label: Text(label), onPressed: () => setState(() => _remind = at)),
              ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _repeat,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: [
                    for (final MapEntry(key: k, value: v) in todoRepeatLabels.entries)
                      DropdownMenuItem(value: k, child: Text(v, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _repeat = v ?? 'none'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StreamBuilder<List<Space>>(
                  stream: context.db.watchSpaces(),
                  builder: (context, snap) {
                    final spaces = snap.data ?? const <Space>[];
                    return DropdownButtonFormField<int?>(
                      key: ValueKey(spaces.length),
                      initialValue: spaces.any((s) => s.id == _spaceId) ? _spaceId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Part of'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Nothing')),
                        for (final s in spaces)
                          DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _spaceId = v),
                    );
                  },
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.danger),
                onPressed: () {
                  final db = context.db;
                  final messenger = ScaffoldMessenger.of(context);
                  db.deleteTodo(widget.todo.id);
                  Navigator.of(context).pop();
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: const Text('Task deleted'),
                      action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreTodo(widget.todo)),
                    ));
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ]),
          ],
        ),
      ),
    );
  }
}
