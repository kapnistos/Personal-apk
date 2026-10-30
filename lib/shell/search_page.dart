import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/event_editor.dart';
import '../apps/habits/habits_page.dart';
import '../apps/notes/notes_page.dart';
import '../apps/shopping/shopping_page.dart';
import '../apps/spaces/space_page.dart';
import '../apps/todo/todo_page.dart';
import '../apps/wallet/wallet_model.dart';
import '../apps/wallet/subscriptions_page.dart';
import '../apps/wallet/wallet_page.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Recent searches, newest first, kept in a raw setting.
class RecentSearches {
  static const key = 'search.recent';
  static const limit = 8;

  static List<String> read(AppSettings s) {
    try {
      final j = jsonDecode(s.raw(key) ?? '[]');
      return j is List ? [for (final x in j) ?(x is String && x.trim().isNotEmpty ? x : null)] : [];
    } catch (_) {
      return [];
    }
  }

  /// Puts [q] first, drops a repeat of it (any case) and keeps [limit].
  static List<String> add(List<String> list, String q) {
    final t = q.trim();
    if (t.length < 2) return list;
    return [t, ...list.where((x) => x.toLowerCase() != t.toLowerCase())].take(limit).toList();
  }

  static Future<void> remember(AppSettings s, String q) => s.setRaw(key, jsonEncode(add(read(s), q)), quiet: true);
  static Future<void> clear(AppSettings s) => s.setRaw(key, '[]');
}

/// One search box for notes, tasks, events, wallet, spaces, shopping and habits.
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
  List<Subscription> recurring = [];
  List<SpaceItem> saved = [];
  List<ShoppingItem> shopping = [];
  List<Habit> habits = [];
  bool get isEmpty =>
      notes.isEmpty &&
      todos.isEmpty &&
      events.isEmpty &&
      entries.isEmpty &&
      recurring.isEmpty &&
      saved.isEmpty &&
      shopping.isEmpty &&
      habits.isEmpty;
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _SearchResults? _results;
  Map<int, Calendar> _cals = {};
  Map<int, Space> _spaces = {};

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
    if (!mounted) return;
    if (text.length < 2) {
      setState(() => _results = null);
      return;
    }
    final db = context.db;
    // Escape LIKE wildcards so "50%" or "a_b" match literally.
    final like = '%${text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    Expression<bool> has(Expression<String> column) => column.like(like, escapeChar: r'\');
    // All at once: each is small, and together they answer faster than one after another.
    final notes =
        (db.select(db.notes)
              ..where((n) => has(n.title) | has(n.body))
              ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
              ..limit(8))
            .get();
    final todos =
        (db.select(db.todos)
              ..where((t) => has(t.title) | has(t.details))
              ..orderBy([(t) => OrderingTerm.asc(t.done)])
              ..limit(8))
            .get();
    final events =
        (db.select(db.events)
              ..where((e) => has(e.title) | has(e.location) | has(e.notes))
              ..orderBy([(e) => OrderingTerm.desc(e.start)])
              ..limit(8))
            .get();
    final entries =
        (db.select(db.entries)
              ..where((e) => has(e.note) | has(e.category) | has(e.account))
              ..orderBy([(e) => OrderingTerm.desc(e.date)])
              ..limit(8))
            .get();
    final recurring =
        (db.select(db.subscriptions)
              ..where((x) => has(x.name) | has(x.category) | has(x.account))
              ..orderBy([(x) => OrderingTerm.desc(x.active), (x) => OrderingTerm.asc(x.nextDate)])
              ..limit(8))
            .get();
    final saved =
        (db.select(db.spaceItems)
              ..where((i) => has(i.title) | has(i.body) | has(i.url))
              ..orderBy([(i) => OrderingTerm.desc(i.updatedAt)])
              ..limit(8))
            .get();
    final shopping =
        (db.select(db.shoppingItems)
              ..where((i) => has(i.name) | has(i.store) | has(i.category))
              ..orderBy([(i) => OrderingTerm.asc(i.done)])
              ..limit(8))
            .get();
    final habits =
        (db.select(db.habits)
              ..where((h) => has(h.name))
              ..orderBy([(h) => OrderingTerm.asc(h.archived), (h) => OrderingTerm.asc(h.position)])
              ..limit(8))
            .get();
    final calsF = db.watchCalendars().first;
    final spacesF = db.watchSpaces().first;
    final r = _SearchResults()
      ..notes = await notes
      ..todos = await todos
      ..events = await events
      ..entries = await entries
      ..recurring = await recurring
      ..saved = await saved
      ..shopping = await shopping
      ..habits = await habits;
    final cals = await calsF;
    final spaces = await spacesF;
    if (!mounted || _controller.text.trim() != text) return;
    setState(() {
      _results = r;
      _cals = {for (final c in cals) c.id: c};
      _spaces = {for (final x in spaces) x.id: x};
    });
  }

  /// Remembers the search, then opens what was tapped.
  void _open(VoidCallback go) {
    RecentSearches.remember(context.settings, _controller.text);
    go();
  }

  void _push(Widget page) => _open(() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)));

  Widget _recent(Palette p) {
    final recent = RecentSearches.read(context.settings);
    if (recent.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        ContentWidth(
          child: Section(
            title: 'Recent',
            trailing: TextButton(onPressed: () => RecentSearches.clear(context.settings), child: const Text('Clear')),
            child: Column(
              children: [
                for (final q in recent)
                  ListTile(
                    leading: Icon(Icons.history_rounded, color: p.muted),
                    title: Text(q),
                    trailing: Icon(Icons.north_west_rounded, size: 18, color: p.muted),
                    onTap: () {
                      _controller.text = q;
                      _controller.selection = TextSelection.collapsed(offset: q.length);
                      _run(q);
                    },
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ],
    );
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
          onSubmitted: (q) => RecentSearches.remember(context.settings, q),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search everything',
            filled: false,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      body: r == null
          ? _recent(p)
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
                        onTap: () => _open(() => openNote(context, note: n)),
                      ),
                  ]),
                if (r.todos.isNotEmpty) _group('Tasks', [for (final t in r.todos) TodoTile(todo: t, dense: true)]),
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
                        onTap: () => _open(
                          () => showEventDetails(
                            context,
                            Occurrence(e, e.start, e.end, Color(_cals[e.calendarId]?.color ?? 0xFF888888)),
                          ),
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
                        onTap: () => _open(() => editEntry(context, entry: e)),
                      ),
                  ]),
                if (r.recurring.isNotEmpty)
                  _group('Recurring', [
                    for (final x in r.recurring)
                      ListTile(
                        leading: Icon(categoryInfo(x.category).icon, color: categoryInfo(x.category).color),
                        title: Text(x.name),
                        subtitle: Text(
                          x.active ? 'Next ${friendlyDay(x.nextDate).toLowerCase()} · ${x.category}' : 'Paused',
                          style: TextStyle(color: p.muted),
                        ),
                        trailing: Text(money(x.kind.sign * x.amountCents, currency, signed: x.kind.sign != 0)),
                        onTap: () => _push(const SubscriptionsPage()),
                      ),
                  ]),
                if (r.saved.isNotEmpty)
                  _group('Saved in spaces', [
                    for (final i in r.saved)
                      ListTile(
                        leading: Icon(switch (i.kind) {
                          'link' => Icons.link_rounded,
                          'file' => Icons.insert_drive_file_outlined,
                          _ => Icons.notes_rounded,
                        }, color: Color(_spaces[i.spaceId]?.color ?? 0xFF888888)),
                        title: Text(i.title.isEmpty ? (i.url.isEmpty ? 'Untitled' : i.url) : i.title),
                        subtitle: Text(
                          _spaces[i.spaceId]?.name ?? 'Space',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted),
                        ),
                        onTap: () => _push(SpacePage(spaceId: i.spaceId)),
                      ),
                  ]),
                if (r.shopping.isNotEmpty)
                  _group('Shopping', [
                    for (final i in r.shopping)
                      ListTile(
                        leading: Icon(
                          i.done ? Icons.check_circle_rounded : Icons.shopping_basket_outlined,
                          color: i.done ? p.muted : p.accent,
                        ),
                        title: Text(
                          i.quantity.isEmpty ? i.name : '${i.name} (${i.quantity})',
                          style: i.done ? TextStyle(color: p.muted, decoration: TextDecoration.lineThrough) : null,
                        ),
                        subtitle: i.store.isEmpty ? null : Text(i.store, style: TextStyle(color: p.muted)),
                        onTap: () => _push(const ShoppingPage()),
                      ),
                  ]),
                if (r.habits.isNotEmpty)
                  _group('Habits', [
                    for (final h in r.habits)
                      ListTile(
                        leading: Icon(habitIcons[h.icon] ?? Icons.check_rounded, color: Color(h.color)),
                        title: Text(h.name),
                        subtitle: h.archived ? Text('Archived', style: TextStyle(color: p.muted)) : null,
                        onTap: () => _open(() => showHabitHistory(context, h)),
                      ),
                  ]),
              ],
            ),
    );
  }

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ContentWidth(
      child: Section(
        title: title,
        child: Column(children: [...children, const SizedBox(height: 6)]),
      ),
    ),
  );
}
