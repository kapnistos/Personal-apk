import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import 'calendar_model.dart';
import 'feed_sync.dart';

Future<void> openEventEditor(
  BuildContext context, {
  Event? event,
  Event? copyOf,
  DateTime? start,
  int? calendarId,
  bool allDay = false,
  int? remindMinutes,
  String title = '',
}) {
  final hub = Hub.of(context);
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Hub(
        db: hub.db,
        settings: hub.settings,
        child: _EventEditor(
          event: event,
          copyOf: copyOf,
          start: start,
          calendarId: calendarId,
          allDay: allDay,
          remindMinutes: remindMinutes,
          title: title,
        ),
      ),
    ),
  );
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({
    this.event,
    this.copyOf,
    this.start,
    this.calendarId,
    this.allDay = false,
    this.remindMinutes,
    this.title = '',
  });
  final Event? event;

  /// An event to start a new one from, for Duplicate. It is saved as a new event.
  final Event? copyOf;
  final DateTime? start;
  final int? calendarId;
  final bool allDay;
  final int? remindMinutes;
  final String title;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final Event? _source = widget.event ?? widget.copyOf;
  late final _title = TextEditingController(text: _source?.title ?? widget.title);
  late final _location = TextEditingController(text: _source?.location ?? '');
  late final _notes = TextEditingController(text: _source?.notes ?? '');
  late DateTime _start = _source?.start ?? widget.start ?? DateTime.now();
  late DateTime _end = _source?.end ?? _start.add(const Duration(hours: 1));
  late bool _allDay = _source?.allDay ?? widget.allDay;
  late String _repeat = _source?.repeat ?? 'none';
  late int? _remind = _source == null ? (widget.remindMinutes ?? (widget.allDay ? -540 : 15)) : _source.remindMinutes;
  int? _calendarId;

  /// What the editor opened with, to tell whether closing it would lose anything.
  late final String _initial;
  bool _saved = false;

  String _snapshot() => [
    _title.text.trim(),
    _location.text.trim(),
    _notes.text.trim(),
    _start,
    _end,
    _allDay,
    _repeat,
    _remind,
    _calendarId,
  ].join('|');

  bool get _dirty => !_saved && _snapshot() != _initial;

  @override
  void initState() {
    super.initState();
    _calendarId = _source?.calendarId ?? widget.calendarId;
    // All-day events store an exclusive end; the editor shows the last day.
    if (_source?.allDay == true) _end = addDays(_end, -1);
    _initial = _snapshot();
    // Typing changes whether back has to ask first.
    for (final c in [_title, _location, _notes]) {
      c.addListener(_typed);
    }
  }

  bool _wasDirty = false;

  void _typed() {
    if (_dirty != _wasDirty) setState(() => _wasDirty = _dirty);
  }

  /// Asks before throwing away changes; true when it is fine to close.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('What you changed in this event is not saved yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) {
      _saved = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _start : _end;
    final d = await showDatePicker(
      context: context,
      // A birthday that repeats from 1990 must still open the picker.
      initialDate: current,
      firstDate: current.year < 2000 ? DateTime(current.year) : DateTime(2000),
      lastDate: current.year > 2100 ? DateTime(current.year + 1) : DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (isStart) {
        // Move the end by whole days so it keeps its clock time across a summer time change.
        final days = daysBetween(_start, _end);
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
        _end = DateTime(d.year, d.month, d.day + days, _end.hour, _end.minute);
      } else {
        _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
        if (_end.isBefore(_start)) {
          // An all-day event then starts on the chosen day too, not at 23:00 the evening before.
          _start = _allDay
              ? DateTime(d.year, d.month, d.day, _start.hour, _start.minute)
              : _end.subtract(const Duration(hours: 1));
          if (_end.isBefore(_start)) _end = _start;
        }
      }
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null || !mounted) return;
    setState(() {
      final length = _end.difference(_start);
      if (isStart) {
        _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        _end = _start.add(length);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
        if (!_end.isAfter(_start)) _end = addDays(_end, 1);
      }
    });
  }

  Future<void> _save(List<Calendar> cals) async {
    final title = _title.text.trim().isEmpty ? '(No title)' : _title.text.trim();
    var start = _start;
    var end = _end;
    if (_allDay) {
      start = dateOnly(_start);
      end = addDays(dateOnly(_end), 1);
    }
    await context.db.saveEvent(
      EventsCompanion(
        id: widget.event == null ? const Value.absent() : Value(widget.event!.id),
        calendarId: Value(cals.where((c) => c.id == _calendarId).firstOrNull?.id ?? cals.first.id),
        title: Value(title),
        location: Value(_location.text.trim()),
        notes: Value(_notes.text.trim()),
        start: Value(start),
        end: Value(end),
        allDay: Value(_allDay),
        repeat: Value(_repeat),
        remindMinutes: Value(_remind),
      ),
    );
    _saved = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<Calendar>>(
      stream: context.db.watchCalendars(),
      builder: (context, snap) {
        final cals = (snap.data ?? const <Calendar>[]).where((c) => c.icsUrl == null).toList();
        final cal = cals.where((c) => c.id == _calendarId).firstOrNull ?? cals.firstOrNull;
        // The ones that fit this kind of event, plus whatever an older event already has.
        final reminders = {
          ...reminderChoices(allDay: _allDay),
          if (reminderOptions.containsKey(_remind)) _remind: reminderOptions[_remind]!,
        };
        return PopScope(
          // Back and the close button ask first when something was changed, so an edit is never lost by accident.
          canPop: !_dirty,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) _close();
          },
          child: Scaffold(
            appBar: HubBar(
              leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: _close),
              title: Text(widget.event == null ? 'New event' : 'Edit event'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(onPressed: cals.isEmpty ? null : () => _save(cals), child: const Text('Save')),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    TextField(
                      controller: _title,
                      autofocus: widget.event == null,
                      textCapitalization: TextCapitalization.sentences,
                      style: Theme.of(context).textTheme.titleLarge,
                      decoration: const InputDecoration(hintText: 'Add title'),
                    ),
                    const SizedBox(height: 16),
                    _Row(
                      icon: Icons.schedule_rounded,
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('All day'),
                            value: _allDay,
                            onChanged: (v) => setState(() {
                              _allDay = v;
                              _remind = reminderAfterAllDayToggle(_remind, allDay: v);
                            }),
                          ),
                          _DateTimeLine(
                            date: _start,
                            showTime: !_allDay,
                            onDate: () => _pickDate(true),
                            onTime: () => _pickTime(true),
                          ),
                          _DateTimeLine(
                            date: _end,
                            showTime: !_allDay,
                            onDate: () => _pickDate(false),
                            onTime: () => _pickTime(false),
                          ),
                        ],
                      ),
                    ),
                    _Row(
                      icon: Icons.repeat_rounded,
                      child: DropdownButtonFormField<String>(
                        initialValue: _repeat,
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        items: [
                          for (final e in repeatLabels.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _repeat = v ?? 'none'),
                      ),
                    ),
                    _Row(
                      icon: Icons.notifications_none_rounded,
                      child: DropdownButtonFormField<int?>(
                        // Rebuilt when all-day flips, since the choices and the value change with it.
                        key: ValueKey(_allDay),
                        initialValue: reminders.containsKey(_remind) ? _remind : null,
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        items: [
                          for (final e in reminders.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _remind = v),
                      ),
                    ),
                    if (cal != null)
                      _Row(
                        icon: Icons.layers_outlined,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in cals)
                                _CalendarChip(
                                  calendar: c,
                                  selected: c.id == cal.id,
                                  onTap: () => setState(() => _calendarId = c.id),
                                ),
                            ],
                          ),
                        ),
                      ),
                    _Row(
                      icon: Icons.place_outlined,
                      child: TextField(
                        controller: _location,
                        decoration: const InputDecoration(hintText: 'Add location'),
                      ),
                    ),
                    _Row(
                      icon: Icons.notes_rounded,
                      child: TextField(
                        controller: _notes,
                        minLines: 3,
                        maxLines: 8,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Add description'),
                      ),
                    ),
                    if (widget.event != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: p.danger),
                          onPressed: () async {
                            await deleteEventWithUndo(context, widget.event!);
                            _saved = true;
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete event'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarChip extends StatelessWidget {
  const _CalendarChip({required this.calendar, required this.selected, required this.onTap});
  final Calendar calendar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = Color(calendar.color);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : p.raised,
        shape: StadiumBorder(side: BorderSide(color: selected ? color : Colors.transparent, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      calendar.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, right: 14),
          child: Icon(icon, size: 22, color: Palette.of(context).muted),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _DateTimeLine extends StatelessWidget {
  const _DateTimeLine({required this.date, required this.showTime, required this.onDate, required this.onTime});
  final DateTime date;
  final bool showTime;
  final VoidCallback onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            onPressed: onDate,
            child: Text(DateFormat('EEE d MMM y').format(date)),
          ),
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: OutlinedButton(onPressed: onTime, child: Text(DateFormat.Hm().format(date))),
          ),
        ],
      ],
    ),
  );
}

Future<void> deleteEventWithUndo(BuildContext context, Event e) async {
  final db = context.db;
  final messenger = ScaffoldMessenger.of(context);
  await db.deleteEvent(e.id);
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Event deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreEvent(e)),
      ),
    );
}

/// "Friday 6 November" with "10:00 – 11:00" under it, or the range for longer events.
(String, String?) eventWhen(Occurrence o) {
  final e = o.event;
  final sameDay = dateOnly(o.start) == dateOnly(o.end.subtract(const Duration(seconds: 1)));
  String day(DateTime d) => DateFormat(d.year == DateTime.now().year ? 'EEEE d MMMM' : 'EEEE d MMMM y').format(d);
  if (e.allDay) {
    if (sameDay || !o.end.isAfter(o.start)) return (day(o.start), 'All day');
    final last = addDays(o.end, -1);
    return (
      '${DateFormat('EEE d MMM').format(o.start)} – ${DateFormat('EEE d MMM').format(last)}',
      'All day · ${daysBetween(dateOnly(o.start), dateOnly(last)) + 1} days',
    );
  }
  if (sameDay || !o.end.isAfter(o.start)) {
    final mins = o.end.difference(o.start).inMinutes;
    final length = mins <= 0
        ? ''
        : mins < 60
        ? ' · $mins min'
        : mins % 60 == 0
        ? ' · ${mins ~/ 60} h'
        : ' · ${mins ~/ 60} h ${mins % 60} min';
    final range = mins <= 0
        ? DateFormat.Hm().format(o.start)
        : '${DateFormat.Hm().format(o.start)} – ${DateFormat.Hm().format(o.end)}';
    return (day(o.start), '$range$length');
  }
  return ('${DateFormat('EEE d MMM, HH:mm').format(o.start)} –', DateFormat('EEE d MMM, HH:mm').format(o.end));
}

Future<void> showEventDetails(BuildContext context, Occurrence o) {
  final db = context.db;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final p = Palette.of(sheet);
      final e = o.event;
      final (whenDay, whenSub) = eventWhen(o);
      final soon = startsIn(o, DateTime.now());
      Widget line(IconData icon, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 24, child: Icon(icon, size: 20, color: p.muted)),
            const SizedBox(width: 16),
            Expanded(child: child),
          ],
        ),
      );
      Text plain(String text) => Text(text, style: const TextStyle(fontSize: 15.5, height: 1.4));
      final readOnly = e.uid != null;
      // Long notes scroll inside the sheet instead of running off the bottom.
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.paddingOf(sheet).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(color: o.color, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          StreamBuilder<List<Calendar>>(
                            stream: db.watchCalendars(),
                            builder: (context, snap) {
                              final name = snap.data?.where((c) => c.id == e.calendarId).firstOrNull?.name;
                              return Text([?name, ?soon].join(' · '), style: TextStyle(color: p.muted, fontSize: 14));
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              line(
                Icons.schedule_rounded,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    plain(whenDay),
                    if (whenSub != null) Text(whenSub, style: TextStyle(color: p.muted, fontSize: 14, height: 1.4)),
                  ],
                ),
              ),
              if (e.repeat != 'none') line(Icons.repeat_rounded, plain(repeatLabels[e.repeat] ?? e.repeat)),
              if (e.remindMinutes != null && reminderOptions.containsKey(e.remindMinutes))
                line(Icons.notifications_none_rounded, plain(reminderOptions[e.remindMinutes]!)),
              if (e.location.isNotEmpty)
                line(
                  Icons.place_outlined,
                  SelectableText(e.location, style: const TextStyle(fontSize: 15.5, height: 1.4)),
                ),
              if (e.notes.isNotEmpty)
                line(Icons.notes_rounded, SelectableText(e.notes, style: const TextStyle(fontSize: 15.5, height: 1.4))),
              if (readOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'From a subscribed calendar. Edit it in the original app, or copy it to one of yours.',
                    style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (!readOnly)
                    IconButton(
                      tooltip: 'Delete',
                      style: IconButton.styleFrom(foregroundColor: p.danger),
                      onPressed: () {
                        Navigator.pop(sheet);
                        deleteEventWithUndo(context, e);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  const SizedBox(width: 8),
                  // Wraps to a second line rather than overflow with large text.
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(sheet);
                            openEventEditor(
                              context,
                              // A subscribed event lands in one of your own calendars.
                              copyOf: e.copyWith(start: o.start, end: o.end, calendarId: readOnly ? -1 : e.calendarId),
                            );
                          },
                          child: Text(readOnly ? 'Copy to my calendar' : 'Duplicate'),
                        ),
                        if (!readOnly)
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(sheet);
                              openEventEditor(context, event: e);
                            },
                            child: const Text('Edit'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> editCalendar(BuildContext context, Calendar? cal) {
  final db = context.db;
  final name = TextEditingController(text: cal?.name ?? '');
  var color = cal?.color ?? calendarColors.first;
  return showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: Text(cal == null ? 'New calendar' : 'Edit calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in calendarColors)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: c == color ? Palette.of(dialog).ink : Colors.transparent, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (cal != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Palette.of(dialog).danger),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: dialog,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete calendar?'),
                    content: Text('This deletes "${cal.name}" and all its events.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await db.deleteCalendar(cal.id);
                  if (dialog.mounted) Navigator.pop(dialog);
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await db.saveCalendar(
                CalendarsCompanion(
                  id: cal == null ? const Value.absent() : Value(cal.id),
                  name: Value(name.text.trim()),
                  color: Value(color),
                  visible: Value(cal?.visible ?? true),
                ),
              );
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Subscribe to a calendar by its .ics link (Proton, Google, Outlook).
Future<void> subscribeCalendar(BuildContext context) {
  final db = context.db;
  final name = TextEditingController();
  final url = TextEditingController();
  var color = calendarColors[3];
  String? error;
  var busy = false;
  return showDialog(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final p = Palette.of(dialog);
        return AlertDialog(
          title: const Text('Subscribe by link'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(hintText: 'Name, e.g. Proton'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(hintText: 'https://… .ics link'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final c in calendarColors)
                        GestureDetector(
                          onTap: () => setState(() => color = c),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(color: c == color ? p.ink : Colors.transparent, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Proton: Settings → Calendars → your calendar → Share → Create link (full view).\n'
                    'Google: Calendar settings → Integrate calendar → Secret address in iCal format.\n'
                    'Outlook: Settings → Calendar → Shared calendars → Publish → ICS link.\n'
                    'Subscribed calendars are read-only and refresh every hour.',
                    style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5),
                  ),
                  if (error != null) ...[const SizedBox(height: 10), Text(error!, style: TextStyle(color: p.danger))],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!url.text.trim().contains('://')) {
                        setState(() => error = 'Paste the full link, starting with https:// or webcal://');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      final id = await db.saveCalendar(
                        CalendarsCompanion.insert(
                          name: name.text.trim().isEmpty ? 'Subscribed' : name.text.trim(),
                          color: color,
                          icsUrl: Value(url.text.trim()),
                        ),
                      );
                      final cal = (await db.watchCalendars().first).firstWhere((c) => c.id == id);
                      try {
                        await FeedSync.instance.sync(db, cal);
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        await db.deleteCalendar(id);
                        setState(() {
                          busy = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(busy ? 'Loading…' : 'Subscribe'),
            ),
          ],
        );
      },
    ),
  );
}

/// Calendar list for phones: show/hide, edit, add, subscribe, refresh.
Future<void> showCalendarsSheet(BuildContext context) {
  final db = context.db;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (sheet, snap) {
        final p = Palette.of(sheet);
        final cals = snap.data ?? const <Calendar>[];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text('Calendars', style: Theme.of(sheet).textTheme.titleLarge),
                ),
                for (final c in cals)
                  ListTile(
                    leading: Checkbox(
                      value: c.visible,
                      activeColor: Color(c.color),
                      side: BorderSide(color: Color(c.color), width: 2),
                      onChanged: (v) => db.saveCalendar(c.toCompanion(false).copyWith(visible: Value(v ?? true))),
                    ),
                    title: Text(c.name),
                    subtitle: c.icsUrl == null
                        ? null
                        : Text(
                            c.syncedAt == null
                                ? 'Subscribed'
                                : 'Subscribed · updated ${DateFormat.Hm().format(c.syncedAt!)}',
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_horiz_rounded),
                      onPressed: () => editCalendar(context, c),
                    ),
                  ),
                const Divider(),
                Press(
                  child: ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('New calendar'),
                    onTap: () => editCalendar(context, null),
                  ),
                ),
                Press(
                  child: ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Subscribe by link (Proton, Google, Outlook)'),
                    onTap: () => subscribeCalendar(context),
                  ),
                ),
                if (cals.any((c) => c.icsUrl != null))
                  Press(
                    child: ListTile(
                      leading: const Icon(Icons.sync_rounded),
                      title: const Text('Refresh subscribed calendars'),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        for (final c in cals.where((c) => c.icsUrl != null)) {
                          try {
                            await FeedSync.instance.sync(db, c);
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
