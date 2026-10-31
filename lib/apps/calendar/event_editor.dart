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
    this.start,
    this.calendarId,
    this.allDay = false,
    this.remindMinutes,
    this.title = '',
  });
  final Event? event;
  final DateTime? start;
  final int? calendarId;
  final bool allDay;
  final int? remindMinutes;
  final String title;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title ?? widget.title);
  late final _location = TextEditingController(text: widget.event?.location ?? '');
  late final _notes = TextEditingController(text: widget.event?.notes ?? '');
  late DateTime _start = widget.event?.start ?? widget.start ?? DateTime.now();
  late DateTime _end = widget.event?.end ?? _start.add(const Duration(hours: 1));
  late bool _allDay = widget.event?.allDay ?? widget.allDay;
  late String _repeat = widget.event?.repeat ?? 'none';
  late int? _remind = widget.event == null ? (widget.remindMinutes ?? 15) : widget.event!.remindMinutes;
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
    _calendarId = widget.event?.calendarId ?? widget.calendarId;
    // All-day events store an exclusive end; the editor shows the last day.
    if (widget.event?.allDay == true) _end = addDays(_end, -1);
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
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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
        calendarId: Value(_calendarId ?? cals.first.id),
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
                            onChanged: (v) => setState(() => _allDay = v),
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
                        initialValue: reminderOptions.containsKey(_remind) ? _remind : 15,
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        items: [
                          for (final e in reminderOptions.entries)
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
                        icon: Icons.circle,
                        iconColor: Color(cal.color),
                        child: DropdownButtonFormField<int>(
                          initialValue: cal.id,
                          isExpanded: true,
                          decoration: const InputDecoration(),
                          items: [
                            for (final c in cals)
                              DropdownMenuItem(
                                value: c.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Color(c.color),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _calendarId = v),
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

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child, this.iconColor});
  final IconData icon;
  final Color? iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, right: 14),
          child: Icon(icon, size: iconColor != null ? 16 : 22, color: iconColor ?? Palette.of(context).muted),
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
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Event deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreEvent(e)),
      ),
    );
}

Future<void> showEventDetails(BuildContext context, Occurrence o) {
  return showModalBottomSheet(
    context: context,
    builder: (sheet) {
      final p = Palette.of(sheet);
      final e = o.event;
      final sameDay = dateOnly(o.start) == dateOnly(o.end.subtract(const Duration(seconds: 1)));
      final when = e.allDay
          ? (sameDay
                ? DateFormat('EEEE d MMMM').format(o.start)
                : '${DateFormat('d MMM').format(o.start)} – ${DateFormat('d MMM').format(addDays(o.end, -1))}')
          : sameDay
          ? '${DateFormat('EEEE d MMMM').format(o.start)}\n${DateFormat.Hm().format(o.start)} – ${DateFormat.Hm().format(o.end)}'
          : '${DateFormat('d MMM HH:mm').format(o.start)} – ${DateFormat('d MMM HH:mm').format(o.end)}';
      Widget line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: p.muted),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
      // Long notes scroll inside the sheet instead of running off the bottom.
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: o.color, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.title, style: Theme.of(sheet).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 16),
            line(Icons.schedule_rounded, when),
            if (e.repeat != 'none') line(Icons.repeat_rounded, repeatLabels[e.repeat] ?? e.repeat),
            if (e.remindMinutes != null) line(Icons.notifications_none_rounded, reminderOptions[e.remindMinutes] ?? ''),
            if (e.location.isNotEmpty) line(Icons.place_outlined, e.location),
            if (e.notes.isNotEmpty) line(Icons.notes_rounded, e.notes),
            const SizedBox(height: 4),
            if (e.uid != null)
              Text(
                'From a subscribed calendar. Edit it in the original app.',
                style: TextStyle(color: p.muted, fontSize: 13.5),
              )
            else
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: () {
                      Navigator.pop(sheet);
                      deleteEventWithUndo(context, e);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheet);
                      openEventEditor(context, event: e);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ],
              ),
          ],
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
