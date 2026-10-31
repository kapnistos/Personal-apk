import 'package:drift/drift.dart' show Value, Variable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/reminders.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../calendar/calendar_model.dart';
import '../calendar/calendar_page.dart' show EventRow;
import '../calendar/event_editor.dart';
import '../todo/todo_page.dart';
import 'space_model.dart';
import 'work_log.dart';

/// Opens a space by its fixed id (seed-job, seed-lab, seed-uni) or by name.
class SpaceLauncher extends StatelessWidget {
  const SpaceLauncher({super.key, required this.gid, required this.fallbackName});
  final String gid;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    return FutureBuilder<Space?>(
      future: () async {
        final row = await db
            .customSelect('SELECT id FROM spaces WHERE gid = ?', variables: [Variable.withString(gid)])
            .getSingleOrNull();
        final spaces = await db.watchSpaces().first;
        final id = row?.read<int>('id');
        return spaces.where((s) => s.id == id).firstOrNull ?? spaces.where((s) => s.name == fallbackName).firstOrNull;
      }(),
      builder: (context, snap) {
        // Keep a back button while the space loads, so the page is never a dead end.
        if (snap.connectionState != ConnectionState.done) return Scaffold(appBar: HubBar(title: Text(fallbackName)));
        final space = snap.data;
        if (space == null) {
          return Scaffold(
            appBar: HubBar(title: Text(fallbackName)),
            body: const EmptyState(
              icon: Icons.folder_off_outlined,
              title: 'Not found',
              message: 'This space was removed.',
            ),
          );
        }
        return SpacePage(spaceId: space.id);
      },
    );
  }
}

class SpacePage extends StatelessWidget {
  const SpacePage({super.key, required this.spaceId});
  final int spaceId;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    return StreamBuilder<List<Space>>(
      stream: db.watchSpaces(),
      builder: (context, snap) {
        final space = (snap.data ?? const <Space>[]).where((s) => s.id == spaceId).firstOrNull;
        if (space == null) return Scaffold(appBar: HubBar()); // Deleted elsewhere: still a way back.
        final color = Color(space.color);
        final words = SpaceWords.of(space.icon);
        return Scaffold(
          appBar: HubBar(
            title: Row(
              children: [
                Icon(spaceIcon(space.icon), color: color),
                const SizedBox(width: 10),
                Flexible(child: Text(space.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add',
            backgroundColor: color,
            foregroundColor: Colors.white,
            onPressed: () => _addMenu(context, space, words),
            child: const Icon(Icons.add_rounded),
          ),
          body: ListView(
            // Room for the floating button (56 + its 16 margin) and the gesture bar, so the last rows, such
            // as the Worked / Off / Holiday / Sick counts, can scroll clear of it.
            padding: EdgeInsets.fromLTRB(16, 8, 16, 120 + MediaQuery.paddingOf(context).bottom),
            children: [
              // The work log is what a job page is mostly for, so it comes first there.
              if (space.icon == 'work') ...[ContentWidth(child: WorkLogCard(color: color)), const SizedBox(height: 12)],
              ContentWidth(
                child: _UpcomingDates(space: space, title: words.dates),
              ),
              const SizedBox(height: 12),
              ContentWidth(
                child: _Meetings(space: space, title: words.meetings),
              ),
              const SizedBox(height: 12),
              ContentWidth(
                child: _Plan(space: space, words: words),
              ),
              const SizedBox(height: 12),
              ContentWidth(child: _Saved(space: space)),
            ],
          ),
        );
      },
    );
  }

  static void _addMenu(BuildContext context, Space space, SpaceWords words) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Press(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text('Add to ${words.dates.toLowerCase()}'),
                subtitle: const Text('Exam, deadline, holiday: a whole-day date with a reminder'),
                onTap: () {
                  Navigator.pop(sheet);
                  addImportantDate(context, space);
                },
              ),
            ),
            Press(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text('Add to ${words.meetings.toLowerCase()}'),
                subtitle: const Text('A meeting, lecture or shift with a time'),
                onTap: () {
                  Navigator.pop(sheet);
                  addMeeting(context, space);
                },
              ),
            ),
            Press(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text('Add to ${words.plan.toLowerCase()}'),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TodoPage(spaceId: space.id)));
                },
              ),
            ),
            Press(
              child: ListTile(
                leading: const Icon(Icons.notes_rounded),
                title: const Text('Save a note'),
                onTap: () {
                  Navigator.pop(sheet);
                  editSpaceItem(context, space, kind: 'note');
                },
              ),
            ),
            Press(
              child: ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Save a link'),
                onTap: () {
                  Navigator.pop(sheet);
                  editSpaceItem(context, space, kind: 'link');
                },
              ),
            ),
            Press(
              child: ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: const Text('Save a file'),
                onTap: () {
                  Navigator.pop(sheet);
                  pickSpaceFile(context, space);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void addImportantDate(BuildContext context, Space space) {
  final today = dateOnly(DateTime.now());
  openEventEditor(context, start: addDays(today, 1), calendarId: space.calendarId, allDay: true, remindMinutes: 900);
}

void addMeeting(BuildContext context, Space space) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, now.hour + 1);
  openEventEditor(context, start: start, calendarId: space.calendarId);
}

/// Shared look for a section with a title, an add button and rows.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children, this.onAdd, this.empty, this.action});
  final String title;
  final List<Widget> children;
  final VoidCallback? onAdd;
  final String? empty;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GroupSection(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?action,
          if (onAdd != null)
            IconButton(
              tooltip: 'Add',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: onAdd,
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (children.isEmpty && empty != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Text(empty!, style: TextStyle(color: p.muted)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _UpcomingDates extends StatelessWidget {
  const _UpcomingDates({required this.space, required this.title});
  final Space space;
  final String title;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final today = dateOnly(DateTime.now());
    final to = addDays(today, 366);
    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, cSnap) {
        final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
        return StreamBuilder<List<Event>>(
          stream: db.watchEventsBetween(today, to),
          builder: (context, snap) {
            final occ = expand(
              (snap.data ?? const []).where((e) => e.calendarId == space.calendarId).toList(),
              cals,
              today,
              to,
            ).where((o) => o.allDay).take(8).toList();
            return _Block(
              title: title,
              onAdd: () => addImportantDate(context, space),
              empty: 'Nothing coming up. Add exams, deadlines or holidays here and get reminded the day before.',
              children: [
                for (final o in occ)
                  Press(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: () => showEventDetails(context, o),
                      leading: _Countdown(days: daysBetween(today, o.start), color: Color(space.color)),
                      title: Text(o.event.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          DateFormat('EEE d MMM').format(o.start),
                          if (o.event.location.isNotEmpty) o.event.location,
                        ].join(' · '),
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.days, required this.color});
  final int days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final urgent = days <= 7;
    return Container(
      // One fixed size with or without the "days" line, so the badges line up; large text shrinks to fit.
      width: 52,
      height: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: urgent ? color : Palette.of(context).raised, shape: BoxShape.circle),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              days == 0 ? 'Today' : '$days',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontSize: days == 0 ? 13 : 17,
                color: urgent ? Colors.white : Palette.of(context).ink,
              ),
            ),
            if (days != 0)
              Text(
                days == 1 ? 'day' : 'days',
                style: TextStyle(fontSize: 11.5, color: urgent ? Colors.white : Palette.of(context).muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Meetings extends StatefulWidget {
  const _Meetings({required this.space, required this.title});
  final Space space;
  final String title;

  @override
  State<_Meetings> createState() => _MeetingsState();
}

class _MeetingsState extends State<_Meetings> {
  bool _all = false;

  Space get space => widget.space;
  String get title => widget.title;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final now = DateTime.now();
    final today = dateOnly(now);
    final to = addDays(today, 14);
    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, cSnap) {
        final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
        return StreamBuilder<List<Event>>(
          stream: db.watchEventsBetween(today, to),
          builder: (context, snap) {
            final occ = expand(
              (snap.data ?? const []).where((e) => e.calendarId == space.calendarId).toList(),
              cals,
              today,
              to,
            ).where((o) => !o.allDay && o.end.isAfter(now)).toList();
            const limit = 5;
            final byDay = <DateTime, List<Occurrence>>{};
            for (final o in _all ? occ : occ.take(limit)) {
              (byDay[dateOnly(o.start)] ??= []).add(o);
            }
            final hours = occ.fold<double>(0, (a, o) => a + o.end.difference(o.start).inMinutes / 60);
            return _Block(
              title: '$title · next 2 weeks',
              onAdd: () => addMeeting(context, space),
              empty: 'No meetings planned. They show up here and in your Calendar.',
              children: [
                for (final MapEntry(key: d, value: list) in byDay.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Text(
                      friendlyDay(d),
                      style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final o in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: EventRow(o: o),
                    ),
                ],
                if (occ.length > limit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(_all ? 'Show less' : 'Show all ${occ.length}'),
                    ),
                  ),
                if (occ.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text(
                      '${occ.length} ${occ.length == 1 ? 'session' : 'sessions'}, '
                      '${hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 1)} hours in total',
                      style: TextStyle(color: p.muted, fontSize: 13.5),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Plan extends StatefulWidget {
  const _Plan({required this.space, required this.words});
  final Space space;
  final SpaceWords words;

  @override
  State<_Plan> createState() => _PlanState();
}

class _PlanState extends State<_Plan> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    final q = parseQuickTask(text);
    await context.db.addTodo(
      q.title,
      due: q.due,
      remindAt: q.remindAt,
      repeat: q.repeat,
      important: q.important,
      spaceId: widget.space.id,
    );
    if (q.remindAt != null) await Reminders.instance.ensurePermission();
    if (mounted) _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = Color(widget.space.color);
    return StreamBuilder<List<Todo>>(
      stream: context.db.watchSpaceTodos(widget.space.id),
      builder: (context, snap) {
        final all = snap.data ?? const <Todo>[];
        final open = all.where((t) => !t.done).toList();
        final done = all.length - open.length;
        return _Block(
          title: widget.words.plan,
          action: all.isEmpty
              ? null
              : TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TodoPage(spaceId: widget.space.id))),
                  child: const Text('All'),
                ),
          children: [
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: all.isEmpty ? 0 : done / all.length,
                          minHeight: 6,
                          color: color,
                          backgroundColor: p.raised,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$done of ${all.length} done', style: TextStyle(color: p.muted, fontSize: 13.5)),
                  ],
                ),
              ),
            for (final t in open.take(8)) TodoTile(todo: t, dense: true),
            if (open.length > 8)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('${open.length - 8} more', style: TextStyle(color: p.muted)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TextField(
                controller: _add,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.words.planHint,
                  prefixIcon: const Icon(Icons.add_rounded),
                  suffixIcon: IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_upward_rounded)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Saved extends StatelessWidget {
  const _Saved({required this.space});
  final Space space;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    return StreamBuilder<List<SpaceItem>>(
      stream: db.watchSpaceItems(space.id),
      builder: (context, snap) {
        final items = snap.data ?? const <SpaceItem>[];
        return _Block(
          title: 'Saved',
          onAdd: () => SpacePage._addMenu(context, space, SpaceWords.of(space.icon)),
          empty: 'Keep important notes, links (course pages, portals, papers) and files here.',
          children: [
            for (final i in items)
              Dismissible(
                key: ValueKey(i.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: p.danger,
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                ),
                onDismissed: (_) {
                  db.deleteSpaceItem(i.id);
                  showUndo(context, 'Removed', () => db.restoreSpaceItem(i));
                },
                child: Press(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(switch (i.kind) {
                      'link' => Icons.link_rounded,
                      'file' => Icons.insert_drive_file_outlined,
                      _ => Icons.notes_rounded,
                    }, color: Color(space.color)),
                    title: Text(
                      i.title.isEmpty ? (i.kind == 'link' ? i.url : 'Note') : i.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      i.kind == 'note'
                          ? i.body.replaceAll('\n', ' ')
                          : (i.kind == 'link' ? Uri.tryParse(i.url)?.host ?? i.url : i.url),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted),
                    ),
                    trailing: IconButton(
                      tooltip: i.pinned ? 'Unpin' : 'Pin',
                      icon: Icon(
                        i.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        size: 18,
                        color: i.pinned ? Color(space.color) : p.muted,
                      ),
                      onPressed: () => db.saveSpaceItem(i.toCompanion(false).copyWith(pinned: Value(!i.pinned))),
                    ),
                    onTap: () => _open(context, i),
                    onLongPress: () => editSpaceItem(context, space, item: i, kind: i.kind),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _open(BuildContext context, SpaceItem i) async {
    final messenger = ScaffoldMessenger.of(context);
    if (i.kind == 'note') {
      editSpaceItem(context, space, item: i, kind: 'note');
      return;
    }
    final uri = i.kind == 'file' ? Uri.file(i.url) : Uri.tryParse(i.url.contains('://') ? i.url : 'https://${i.url}');
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        SnackBar(content: Text(i.kind == 'file' ? 'That file is not on this device.' : 'Could not open the link.')),
      );
    }
  }
}

Future<void> pickSpaceFile(BuildContext context, Space space) async {
  final db = context.db;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final List<PlatformFile> res;
  try {
    res = await FilePicker.pickFiles();
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open the file picker')));
    return;
  }
  final f = res.firstOrNull;
  if (f == null || f.path == null) return;
  await db.saveSpaceItem(
    SpaceItemsCompanion.insert(spaceId: space.id, kind: 'file', title: Value(f.name), url: Value(f.path!)),
  );
}

Future<void> editSpaceItem(BuildContext context, Space space, {SpaceItem? item, required String kind}) async {
  final db = context.db;
  final title = TextEditingController(text: item?.title ?? '');
  final body = TextEditingController(text: item?.body ?? '');
  final url = TextEditingController(text: item?.url ?? '');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item == null ? (kind == 'link' ? 'Save a link' : 'Save a note') : 'Edit',
            style: Theme.of(sheet).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (kind == 'link') ...[
            TextField(
              controller: url,
              autofocus: item == null,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link', hintText: 'https://'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: title,
            autofocus: item == null && kind != 'link',
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: kind == 'link' ? 'Name (optional)' : 'Title'),
          ),
          if (kind != 'link') ...[
            const SizedBox(height: 10),
            TextField(
              controller: body,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: kind == 'file' ? 'Note about this file' : 'Note'),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Save')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (kind == 'link' && url.text.trim().isEmpty) return;
  if (kind == 'note' && title.text.trim().isEmpty && body.text.trim().isEmpty) return;
  await db.saveSpaceItem(
    SpaceItemsCompanion(
      id: item == null ? const Value.absent() : Value(item.id),
      spaceId: Value(space.id),
      kind: Value(kind),
      title: Value(title.text.trim()),
      body: Value(body.text.trim()),
      url: Value(kind == 'file' ? (item?.url ?? '') : url.text.trim()),
      pinned: Value(item?.pinned ?? false),
      createdAt: item == null ? const Value.absent() : Value(item.createdAt),
    ),
  );
}
