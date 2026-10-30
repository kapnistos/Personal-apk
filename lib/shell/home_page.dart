import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/internships/internships_page.dart';
import '../apps/news/news_page.dart';
import '../apps/news/news_service.dart';
import '../apps/notes/notes_page.dart';
import '../apps/registry.dart';
import '../apps/spaces/my_spaces.dart';
import '../apps/todo/todo_page.dart';
import '../apps/weather/weather_page.dart';
import '../apps/weather/weather_service.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/mini_app.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'dashboard.dart';
import 'me_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dash = GlobalKey<DashboardState>();
  bool _editing = false;

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text('Home goes back to the starting widgets. Your data stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) _dash.currentState?.resetLayout();
  }

  Widget _header(BuildContext context, String name, bool greet) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final showText = _editing || greet;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: !showText
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE d MMMM').format(now),
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: p.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _editing
                          ? 'Edit home'
                          : name.isEmpty
                          ? greeting(now)
                          : '${greeting(now)}, $name',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
        ),
        if (_editing) ...[
          IconButton(
            tooltip: 'Back to the starting layout',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _confirmReset,
          ),
          IconButton.filledTonal(
            tooltip: 'Add a widget',
            style: IconButton.styleFrom(backgroundColor: p.raised, foregroundColor: p.ink),
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _dash.currentState?.addWidget(),
          ),
          const SizedBox(width: 6),
          FilledButton(onPressed: () => setState(() => _editing = false), child: const Text('Done')),
        ] else ...[
          IconButton.filledTonal(
            tooltip: 'Edit home',
            style: IconButton.styleFrom(backgroundColor: p.raised, foregroundColor: p.ink),
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _editing = true);
            },
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'Me and settings',
            child: GestureDetector(
              // Your profile holds every setting.
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MePage())),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: p.accent,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) setState(() => _editing = false);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ContentWidth(
                maxWidth: 960,
                child: SettingSelector<(String, bool)>(
                  select: (s) => (s.name, s.raw(homeGreetingKey) != 'off'),
                  builder: (context, v) => _header(context, v.$1, v.$2),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _editing
                    ? ContentWidth(
                        maxWidth: 960,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Hold and drag a widget to move it. Tap one to change its size, shape and colour.',
                            style: TextStyle(color: p.muted),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 16),
              ContentWidth(
                maxWidth: 960,
                child: Dashboard(key: _dash, editing: _editing, onEditing: (v) => setState(() => _editing = v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppGrid extends StatelessWidget {
  const AppGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: LayoutBuilder(
          builder: (context, c) {
            final perRow = c.maxWidth >= 640 ? 6 : 4;
            final w = c.maxWidth / perRow;
            final hidden = hiddenApps(context.settings);
            return StreamBuilder<List<Space>>(
              stream: context.db.watchSpaces(),
              builder: (context, snap) => Wrap(
                runSpacing: 12,
                children: [
                  for (final app in [...miniApps, ...customSpaceApps(snap.data ?? const [])])
                    if (!hidden.contains(app.id))
                      SizedBox(
                        width: w,
                        child: _AppTile(app: app, muted: p.muted),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.muted});
  final MiniApp app;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: app.subtitle,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => app.open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Opacity(
                opacity: app.available ? 1 : 0.45,
                child: AppGlyph(icon: app.icon, color: app.color, size: 50),
              ),
              const SizedBox(height: 7),
              Text(
                app.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: app.available ? null : muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeatherGlance extends StatelessWidget {
  const WeatherGlance({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<City>>(
      stream: context.db.watchCities(),
      builder: (context, snap) {
        final city = selectedCity(context, snap.data ?? const <City>[]);
        if (city == null) return const SizedBox.shrink();
        return WeatherGlanceCard(key: ValueKey(city.id), city: city, compact: compact);
      },
    );
  }
}

class WeatherGlanceCard extends StatefulWidget {
  const WeatherGlanceCard({super.key, required this.city, this.compact = false});
  final City city;
  final bool compact;

  @override
  State<WeatherGlanceCard> createState() => _WeatherGlanceCardState();
}

class _WeatherGlanceCardState extends State<WeatherGlanceCard> {
  Forecast? _f;
  Nowcast? _n;

  @override
  void initState() {
    super.initState();
    final s = WeatherService.instance;
    s.forecast(widget.city.latitude, widget.city.longitude).then((f) {
      if (mounted) setState(() => _f = f);
    }, onError: (_) {});
    s.nowcast(widget.city.latitude, widget.city.longitude).then((n) {
      if (mounted) setState(() => _n = n);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final unit = context.settings.tempUnit;
    final colors = f == null ? const [Color(0xFF5B7A99), Color(0xFF8AA4BD)] : WeatherCode.gradient(f.code, f.isDay);
    final dim = Colors.white.withValues(alpha: 0.8);
    final today = f?.days.firstOrNull;
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeatherPage())),
          child: widget.compact
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.city.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: dim, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (f != null) Icon(WeatherCode.icon(f.code, isDay: f.isDay), color: Colors.white, size: 26),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        f == null ? '--' : formatTemp(f.temperature, unit),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1.2,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        f == null ? 'Loading' : WeatherCode.label(f.code),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      if (today != null)
                        Text(
                          'H ${formatTemp(today.max, unit)}  L ${formatTemp(today.min, unit)}',
                          style: TextStyle(color: dim, fontSize: 13),
                        ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.city.name,
                              style: TextStyle(color: dim, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f == null ? '--' : formatTemp(f.temperature, unit),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w300,
                                height: 1.1,
                                letterSpacing: -1.5,
                              ),
                            ),
                            Text(
                              f == null
                                  ? 'Loading'
                                  : '${WeatherCode.label(f.code)}${today == null ? '' : ' · H ${formatTemp(today.max, unit)}  L ${formatTemp(today.min, unit)}'}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                            if (_n != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.umbrella_rounded, size: 14, color: dim),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      _n!.summary(DateFormat.Hm().format),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: dim, fontSize: 13.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (f != null) Icon(WeatherCode.icon(f.code, isDay: f.isDay), color: Colors.white, size: 54),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class TodayCard extends StatefulWidget {
  const TodayCard({super.key});

  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> with WidgetsBindingObserver {
  Timer? _tick;
  DateTime _today = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-check every minute so finished events fade and the day rolls over at midnight.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _today = dateOnly(DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final now = DateTime.now();
    final today = _today;
    final tomorrow = addDays(today, 1);
    return Section(
      title: 'Today',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalendarPage())),
        child: const Text('Calendar'),
      ),
      child: StreamBuilder<List<Calendar>>(
        stream: db.watchCalendars(),
        builder: (context, calSnap) {
          final cals = {for (final c in calSnap.data ?? const <Calendar>[]) c.id: c};
          return StreamBuilder<List<Event>>(
            stream: db.watchEventsBetween(today, tomorrow),
            builder: (context, evSnap) {
              final events = expand(evSnap.data ?? const [], cals, today, tomorrow);
              return StreamBuilder<List<Todo>>(
                stream: db.watchTodos(),
                builder: (context, tSnap) {
                  final todos = (tSnap.data ?? const <Todo>[]).where((t) => isTodayTask(t, now: now)).toList()
                    ..sort((a, b) {
                      if (a.important != b.important) return a.important ? -1 : 1;
                      final x = a.remindAt ?? a.due!, y = b.remindAt ?? b.due!;
                      return x.compareTo(y);
                    });
                  return StreamBuilder<List<Application>>(
                    stream: db.watchApplications(),
                    builder: (context, aSnap) => StreamBuilder<List<Subscription>>(
                      stream: db.watchSubscriptions(),
                      builder: (context, sSnap) {
                        final deadlines = (aSnap.data ?? const <Application>[])
                            .where(
                              (a) =>
                                  (a.status == 'wishlist' || a.status == 'preparing') &&
                                  a.deadline != null &&
                                  daysBetween(today, a.deadline!) >= 0 &&
                                  daysBetween(today, a.deadline!) <= 3,
                            )
                            .toList();
                        final payments = (sSnap.data ?? const <Subscription>[])
                            .where((s) => s.active && daysBetween(today, s.nextDate) == 0)
                            .toList();
                        if (events.isEmpty && todos.isEmpty && payments.isEmpty && deadlines.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                            child: Text('Nothing planned for today.', style: TextStyle(color: p.muted)),
                          );
                        }
                        const maxEvents = 6, maxTodos = 8;
                        final hiddenEvents = events.length - maxEvents;
                        final hiddenTodos = todos.length - maxTodos;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final o in events.take(maxEvents))
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Opacity(
                                    // Finished events stay visible but step back.
                                    opacity: !o.allDay && o.end.isBefore(now) ? 0.5 : 1,
                                    child: EventRow(o: o),
                                  ),
                                ),
                              if (hiddenEvents > 0)
                                _More(
                                  '$hiddenEvents more ${hiddenEvents == 1 ? 'event' : 'events'}',
                                  () =>
                                      Navigator.of(context)
                                          .push(MaterialPageRoute(builder: (_) => const CalendarPage())),
                                ),
                              for (final t in todos.take(maxTodos)) TodoTile(todo: t, dense: true),
                              if (hiddenTodos > 0)
                                _More(
                                  '$hiddenTodos more ${hiddenTodos == 1 ? 'task' : 'tasks'}',
                                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TodoPage())),
                                ),
                              for (final a in deadlines)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.badge_outlined, color: internshipColor, size: 20),
                                  title: Text('Apply: ${a.company}'),
                                  subtitle: Text('Deadline ${friendlyDay(a.deadline!).toLowerCase()}'),
                                  onTap: () => editApplication(context, application: a),
                                ),
                              for (final s in payments)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.payments_outlined, color: TileColors.finance, size: 20),
                                  title: Text(s.name),
                                  subtitle: const Text('Payment due today'),
                                  trailing: Text(money(s.amountCents, context.settings.currency)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// The newest important headlines, refreshed at most every half hour.
class HeadlinesCard extends StatefulWidget {
  const HeadlinesCard({super.key});

  @override
  State<HeadlinesCard> createState() => _HeadlinesCardState();
}

class _HeadlinesCardState extends State<HeadlinesCard> {
  final _news = NewsService.instance;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _news.loadCache(context.settings);
    // Settings changes land here too; after a failed try, wait for the next visit instead of retrying each time.
    if (_news.stale && !_failed) {
      _news
          .refresh(context.settings)
          // An offline refresh finishes without news rather than throwing.
          .then((_) {
            if (mounted) setState(() => _failed = _news.briefing(perTopic: 1, max: 1).isEmpty);
          })
          .catchError((_) {
            if (mounted) setState(() => _failed = true);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = _news.briefing(perTopic: 1, max: 4);
    return Section(
      title: 'Headlines',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsPage())),
        child: const Text('All news'),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  _failed ? 'Could not load the news. Check your connection.' : 'Loading the latest news…',
                  style: TextStyle(color: p.muted),
                ),
              )
            : Column(children: [for (final i in items) NewsTile(item: i, compact: true)]),
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(onPressed: onTap, child: Text(label)),
  );
}

class RecentNotesCard extends StatelessWidget {
  const RecentNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<Note>>(
      stream: context.db.watchNotes(),
      builder: (context, snap) {
        final notes = (snap.data ?? const <Note>[]).take(4).toList();
        return Section(
          title: 'Recent notes',
          trailing: IconButton(
            tooltip: 'New note',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: () => openNote(context),
          ),
          child: notes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  child: Text('No notes yet.', style: TextStyle(color: p.muted)),
                )
              : Column(
                  children: [
                    for (final n in notes)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          n.pinned ? Icons.push_pin_rounded : Icons.notes_rounded,
                          size: 18,
                          color: n.pinned ? TileColors.notes : p.muted,
                        ),
                        title: Text(
                          n.title.trim().isEmpty ? 'Untitled' : n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(relativeTime(n.updatedAt)),
                        onTap: () => openNote(context, note: n),
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
        );
      },
    );
  }
}

const _hiddenAppsKey = 'home.hiddenApps';

/// Apps the user took off the Apps widget.
Set<String> hiddenApps(AppSettings s) => {...?s.raw(_hiddenAppsKey)?.split(',').where((x) => x.isNotEmpty)};

/// Tick the apps to show on Home; your own spaces are listed too.
Future<void> pickVisibleApps(BuildContext context) async {
  final settings = context.settings;
  final spaces = await context.db.watchSpaces().first;
  if (!context.mounted) return;
  final apps = [...miniApps, ...customSpaceApps(spaces)];
  final hidden = hiddenApps(settings);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Apps on Home', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final a in apps)
              CheckboxListTile(
                secondary: AppGlyph(icon: a.icon, color: a.color, size: 36),
                title: Text(a.title),
                value: !hidden.contains(a.id),
                onChanged: (on) {
                  setSheet(() => on == true ? hidden.remove(a.id) : hidden.add(a.id));
                  settings.setRaw(_hiddenAppsKey, hidden.join(','));
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Make a new space'),
              onTap: () {
                Navigator.pop(ctx);
                editSpace(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
