import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/event_editor.dart';
import '../apps/notes/notes_page.dart';
import '../apps/todo/todo_page.dart';
import '../apps/wallet/wallet_model.dart';
import '../apps/wallet/wallet_page.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// One search box for notes, tasks, events and wallet entries.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchResults {
  List<Note> notes = [];
  List<Todo> todos = [];
  List<Event> events = [];
  List<Entry> entries = [];
  bool get isEmpty => notes.isEmpty && todos.isEmpty && events.isEmpty && entries.isEmpty;
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _SearchResults? _results;
  Map<int, Calendar> _cals = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(q));
  }

  Future<void> _run(String q) async {
    final text = q.trim();
    if (text.length < 2) {
      setState(() => _results = null);
      return;
    }
    final db = context.db;
    final like = '%$text%';
    final r = _SearchResults()
      ..notes = await (db.select(db.notes)
            ..where((n) => n.title.like(like) | n.body.like(like))
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
            ..limit(8))
          .get()
      ..todos = await (db.select(db.todos)
            ..where((t) => t.title.like(like) | t.details.like(like))
            ..orderBy([(t) => OrderingTerm.asc(t.done)])
            ..limit(8))
          .get()
      ..events = await (db.select(db.events)
            ..where((e) => e.title.like(like) | e.location.like(like) | e.notes.like(like))
            ..orderBy([(e) => OrderingTerm.desc(e.start)])
            ..limit(8))
          .get()
      ..entries = await (db.select(db.entries)
            ..where((e) => e.note.like(like) | e.category.like(like) | e.account.like(like))
            ..orderBy([(e) => OrderingTerm.desc(e.date)])
            ..limit(8))
          .get();
    final cals = await db.watchCalendars().first;
    if (!mounted || _controller.text.trim() != text) return;
    setState(() {
      _results = r;
      _cals = {for (final c in cals) c.id: c};
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = _results;
    final currency = context.settings.currency;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search notes, tasks, events, wallet',
            filled: false,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      body: r == null
          ? const SizedBox.shrink()
          : r.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'No results', message: 'Try another word.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    if (r.notes.isNotEmpty)
                      _group('Notes', [
                        for (final n in r.notes)
                          ListTile(
                            leading: const Icon(Icons.sticky_note_2_outlined, color: TileColors.notes),
                            title: Text(n.title.isEmpty ? 'Untitled' : n.title),
                            subtitle: Text(n.body.replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => openNote(context, note: n),
                          ),
                      ]),
                    if (r.todos.isNotEmpty)
                      _group('Tasks', [for (final t in r.todos) TodoTile(todo: t, dense: true)]),
                    if (r.events.isNotEmpty)
                      _group('Events', [
                        for (final e in r.events)
                          ListTile(
                            leading: Icon(Icons.circle, size: 14, color: Color(_cals[e.calendarId]?.color ?? 0xFF888888)),
                            title: Text(e.title),
                            subtitle: Text(
                              '${DateFormat('EEE d MMM y').format(e.start)}${e.allDay ? '' : ', ${DateFormat.Hm().format(e.start)}'}'
                              '${e.repeat != 'none' ? ' · ${repeatLabels[e.repeat]}' : ''}',
                              style: TextStyle(color: p.muted),
                            ),
                            onTap: () => showEventDetails(
                              context,
                              Occurrence(e, e.start, e.end, Color(_cals[e.calendarId]?.color ?? 0xFF888888)),
                            ),
                          ),
                      ]),
                    if (r.entries.isNotEmpty)
                      _group('Wallet', [
                        for (final e in r.entries)
                          ListTile(
                            leading: Icon(categoryInfo(e.category).icon, color: categoryInfo(e.category).color),
                            title: Text(e.note.isEmpty ? e.category : e.note),
                            subtitle: Text('${friendlyDay(e.date)} · ${e.category}', style: TextStyle(color: p.muted)),
                            trailing: Text(money(e.kind.sign * e.amountCents, currency, signed: e.kind.sign != 0)),
                            onTap: () => editEntry(context, entry: e),
                          ),
                      ]),
                  ],
                ),
    );
  }

  Widget _group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ContentWidth(child: Section(title: title, child: Column(children: [...children, const SizedBox(height: 6)]))),
      );
}
