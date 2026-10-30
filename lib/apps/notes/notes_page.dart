import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';

/// Soft card colours for notes, light and dark. Index 0 is the normal card.
const noteColors = <(Color, Color)>[
  (Color(0x00000000), Color(0x00000000)),
  (Color(0xFFFBEFD0), Color(0xFF3A3220)),
  (Color(0xFFE2F0E4), Color(0xFF22332A)),
  (Color(0xFFDDEBF7), Color(0xFF1F2C3A)),
  (Color(0xFFF6E0DA), Color(0xFF3A2622)),
  (Color(0xFFE9E2F5), Color(0xFF2C2638)),
];

Color? noteColor(BuildContext context, int i) {
  if (i <= 0 || i >= noteColors.length) return null;
  return Theme.of(context).brightness == Brightness.dark ? noteColors[i].$2 : noteColors[i].$1;
}

/// A line like "- [ ] milk" or "- [x] milk".
final _checkLine = RegExp(r'^(\s*)[-*] \[( |x|X)\] ?(.*)$');

/// Ticked and total checklist items in a note body.
(int, int) checklistCount(String body) {
  var done = 0, total = 0;
  for (final l in body.split('\n')) {
    final m = _checkLine.firstMatch(l);
    if (m == null) continue;
    total++;
    if (m[2]!.toLowerCase() == 'x') done++;
  }
  return (done, total);
}

/// Flips the checklist item on [line] of [body].
String toggleChecklistLine(String body, int line) {
  final lines = body.split('\n');
  final m = _checkLine.firstMatch(lines[line]);
  if (m == null) return body;
  final ticked = m[2]!.toLowerCase() == 'x';
  lines[line] = '${m[1]}- [${ticked ? ' ' : 'x'}] ${m[3]}';
  return lines.join('\n');
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String _query = '';
  late Stream<List<Note>> _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream = context.db.watchNotes(query: _query);
  }

  void _setQuery(String q) => setState(() {
        _query = q;
        _stream = context.db.watchNotes(query: q);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'checklist',
          tooltip: 'New checklist',
          onPressed: () => openNote(context, startWith: '- [ ] '),
          child: const Icon(Icons.checklist_rounded),
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: 'note',
          tooltip: 'New note',
          onPressed: () => openNote(context),
          child: const Icon(Icons.edit_rounded),
        ),
      ]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ContentWidth(
              maxWidth: 960,
              child: TextField(
                onChanged: _setQuery,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: _stream,
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final notes = snap.data!;
                if (notes.isEmpty) {
                  return _query.isEmpty
                      ? const EmptyState(
                          icon: Icons.sticky_note_2_outlined,
                          title: 'No notes yet',
                          message: 'Tap the pencil to write a note, or the list button for a checklist.',
                        )
                      : const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Nothing found',
                          message: 'No note matches that search.',
                        );
                }
                final pinned = notes.where((n) => n.pinned).toList();
                final others = notes.where((n) => !n.pinned).toList();
                return LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth.clamp(0, 960) / 290).floor().clamp(2, 3);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        const ContentWidth(maxWidth: 960, child: _GroupLabel('Pinned')),
                        ContentWidth(maxWidth: 960, child: _Masonry(columns: cols, notes: pinned)),
                        if (others.isNotEmpty) const ContentWidth(maxWidth: 960, child: _GroupLabel('Others')),
                      ],
                      ContentWidth(maxWidth: 960, child: _Masonry(columns: cols, notes: others)),
                    ],
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 8), child: SectionLabel(text));
}

/// Cards in columns of different heights, filled left to right by shortest column.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.columns, required this.notes});
  final int columns;
  final List<Note> notes;

  static double _estimate(Note n) {
    final lines = n.body.trim().isEmpty ? 0 : n.body.trim().split('\n').length.clamp(1, 8);
    return 70.0 + lines * 20;
  }

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(columns, (_) => <Note>[]);
    final heights = List.filled(columns, 0.0);
    for (final n in notes) {
      var i = 0;
      for (var c = 1; c < columns; c++) {
        if (heights[c] < heights[i]) i = c;
      }
      cols[i].add(n);
      heights[i] += _estimate(n);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) const SizedBox(width: 10),
          Expanded(
            child: Column(children: [
              for (final n in cols[c]) Padding(padding: const EdgeInsets.only(bottom: 10), child: NoteCard(note: n)),
            ]),
          ),
        ],
      ],
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title = note.title.trim();
    final lines = note.body.trim().split('\n').where((l) => l.trim().isNotEmpty).take(8).toList();
    final (done, total) = checklistCount(note.body);
    return Card(
      color: noteColor(context, note.color),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openNote(context, note: note),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty || note.pinned)
                Row(children: [
                  Expanded(
                    child: Text(title.isEmpty ? 'Untitled' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (note.pinned) const Icon(Icons.push_pin_rounded, size: 15, color: TileColors.notes),
                ]),
              if (lines.isNotEmpty) const SizedBox(height: 4),
              for (final l in lines) _PreviewLine(line: l, note: note),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(relativeTime(note.updatedAt), style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
                if (total > 0)
                  Text('$done/$total', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.line, required this.note});
  final String line;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = _checkLine.firstMatch(line);
    final style = TextStyle(color: p.muted, height: 1.35, fontSize: 13.5);
    if (m == null) {
      return Text(line.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    }
    final ticked = m[2]!.toLowerCase() == 'x';
    return InkWell(
      onTap: () {
        final index = note.body.split('\n').indexOf(line);
        if (index < 0) return;
        context.db.saveNote(id: note.id, title: note.title, body: toggleChecklistLine(note.body, index));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Icon(ticked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 17, color: ticked ? TileColors.notes : p.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(m[3]!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(decoration: ticked ? TextDecoration.lineThrough : null)),
          ),
        ]),
      ),
    );
  }
}

void openNote(BuildContext context, {Note? note, String startWith = ''}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditor(note: note, startWith: startWith)));
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note, this.startWith = ''});
  final Note? note;
  final String startWith;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? widget.startWith);
  late int? _id = widget.note?.id;
  late bool _pinned = widget.note?.pinned ?? false;
  late int _color = widget.note?.color ?? 0;
  late final AppDatabase _db;
  Timer? _debounce;
  bool _dirty = false;
  bool _deleted = false;
  String _lastBody = '';

  @override
  void initState() {
    super.initState();
    _lastBody = _body.text;
    _title.addListener(_changed);
    _body.addListener(_bodyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _db = context.db;
  }

  /// Pressing Enter on a list line starts the next item; on an empty item it ends the list.
  void _bodyChanged() {
    final text = _body.text;
    final sel = _body.selection;
    if (text.length == _lastBody.length + 1 && sel.isCollapsed && sel.start > 0 && text[sel.start - 1] == '\n') {
      final before = text.substring(0, sel.start - 1);
      final prevLine = before.substring(before.lastIndexOf('\n') + 1);
      final check = _checkLine.firstMatch(prevLine);
      final bullet = RegExp(r'^(\s*)([-*•]) (.*)$').firstMatch(prevLine);
      String? prefix;
      var emptyItem = false;
      if (check != null) {
        prefix = '${check[1]}- [ ] ';
        emptyItem = check[3]!.trim().isEmpty;
      } else if (bullet != null) {
        prefix = '${bullet[1]}${bullet[2]} ';
        emptyItem = bullet[3]!.trim().isEmpty;
      }
      if (prefix != null) {
        if (emptyItem) {
          // Remove the empty item and the new line.
          final start = before.length - prevLine.length;
          final next = text.substring(0, start) + text.substring(sel.start);
          _lastBody = next;
          _body.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start));
        } else {
          final next = text.substring(0, sel.start) + prefix + text.substring(sel.start);
          _lastBody = next;
          _body.value =
              TextEditingValue(text: next, selection: TextSelection.collapsed(offset: sel.start + prefix.length));
        }
        _changed();
        return;
      }
    }
    _lastBody = text;
    _changed();
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
    setState(() {});
  }

  Future<void> _save() async {
    if (!_dirty || _deleted) return;
    _dirty = false;
    final title = _title.text;
    final body = _body.text;
    if (_id == null && title.trim().isEmpty && (body.trim().isEmpty || body == widget.startWith)) return;
    _id = await _db.saveNote(id: _id, title: title, body: body);
    if (_pinned) await _db.setNotePinned(_id!, true);
    if (_color != 0) await _db.setNoteColor(_id!, _color);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _togglePin() async {
    setState(() => _pinned = !_pinned);
    _dirty = true;
    await _save();
    if (_id != null) await _db.setNotePinned(_id!, _pinned);
  }

  Future<void> _setColor(int c) async {
    setState(() => _color = c);
    _dirty = true;
    await _save();
    if (_id != null) await _db.setNoteColor(_id!, c);
  }

  /// Turns the current line into a checklist or bullet item, or back to text.
  void _toggleLinePrefix(String prefix) {
    final text = _body.text;
    final at = _body.selection.isValid ? _body.selection.start : text.length;
    final lineStart = text.lastIndexOf('\n', at - 1 < 0 ? 0 : at - 1) + 1;
    final lineEnd = text.indexOf('\n', at) < 0 ? text.length : text.indexOf('\n', at);
    final line = text.substring(lineStart, lineEnd);
    final stripped = line.replaceFirst(RegExp(r'^\s*([-*•] \[( |x|X)\] |[-*•] )'), '');
    final next = line.startsWith(prefix) ? stripped : prefix + stripped;
    final updated = text.substring(0, lineStart) + next + text.substring(lineEnd);
    _lastBody = updated;
    _body.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: lineStart + next.length));
    _changed();
  }

  void _insert(String s) {
    final text = _body.text;
    final at = _body.selection.isValid ? _body.selection.start : text.length;
    final updated = text.substring(0, at) + s + text.substring(_body.selection.isValid ? _body.selection.end : at);
    _lastBody = updated;
    _body.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: at + s.length));
    _changed();
  }

  Future<void> _delete() async {
    _debounce?.cancel();
    _deleted = true;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final id = _id;
    if (id != null) {
      final snapshot = Note(
        id: id,
        title: _title.text,
        body: _body.text,
        pinned: _pinned,
        color: _color,
        createdAt: widget.note?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _db.deleteNote(id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Note deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () => _db.restoreNote(snapshot)),
        ));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = noteColor(context, _color);
    final plain = InputDecoration(
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintStyle: TextStyle(color: p.muted),
    );
    final words = RegExp(r'\S+').allMatches(_body.text).length;
    final (done, total) = checklistCount(_body.text);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        actions: [
          IconButton(
            tooltip: _pinned ? 'Unpin' : 'Pin',
            icon: Icon(_pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _pinned ? TileColors.notes : null),
            onPressed: _togglePin,
          ),
          IconButton(
            tooltip: 'Ask Claude about this note',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => ClaudeBridge.ask(
              context,
              'Help me with this note.\n\n# ${_title.text}\n\n${_body.text}',
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') _delete();
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: '${_title.text}\n\n${_body.text}'.trim()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                }
              }
              if (v == 'untick') {
                _lastBody = _body.text.replaceAll(RegExp(r'\[(x|X)\]'), '[ ]');
                _body.text = _lastBody;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy text')),
              if (total > 0) const PopupMenuItem(value: 'untick', child: Text('Untick all items')),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded, color: p.danger),
                  const SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: p.danger)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
              children: [
                TextField(
                  controller: _title,
                  autofocus: widget.note == null && widget.startWith.isEmpty,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: plain.copyWith(hintText: 'Title'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    [
                      if (widget.note != null) 'Edited ${relativeTime(widget.note!.updatedAt)}',
                      '$words ${words == 1 ? 'word' : 'words'}',
                      if (total > 0) '$done of $total done',
                    ].join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  autofocus: widget.startWith.isNotEmpty,
                  maxLines: null,
                  minLines: 12,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: plain.copyWith(hintText: 'Start writing'),
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + MediaQuery.paddingOf(context).bottom),
          child: Row(children: [
            IconButton(
              tooltip: 'Checklist item',
              icon: const Icon(Icons.check_box_outlined),
              onPressed: () => _toggleLinePrefix('- [ ] '),
            ),
            IconButton(
              tooltip: 'Bullet',
              icon: const Icon(Icons.format_list_bulleted_rounded),
              onPressed: () => _toggleLinePrefix('- '),
            ),
            IconButton(
              tooltip: 'Insert date and time',
              icon: const Icon(Icons.schedule_rounded),
              onPressed: () {
                final now = DateTime.now();
                _insert('${friendlyDay(now)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ');
              },
            ),
            const Spacer(),
            for (var i = 0; i < noteColors.length; i++)
              GestureDetector(
                onTap: () => _setColor(i),
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == 0 ? p.surface : noteColor(context, i),
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == i ? p.ink : p.line, width: _color == i ? 2 : 1),
                  ),
                ),
              ),
            const SizedBox(width: 6),
          ]),
        ),
      ]),
    );
  }
}
