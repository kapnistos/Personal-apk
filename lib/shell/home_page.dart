import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/internships/internships_page.dart';
import '../apps/news/news_page.dart';
import '../apps/news/news_service.dart';
import '../apps/notes/notes_page.dart';
import '../apps/registry.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dash = GlobalKey<DashboardState>();
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.settings;
    final now = DateTime.now();
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE d MMMM').format(now).toUpperCase(),
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                              color: p.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _editing
                                ? 'Edit home'
                                : settings.name.isEmpty
                                ? greeting(now)
                                : '${greeting(now)}, ${settings.name}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    if (_editing) ...[
                      IconButton(
                        tooltip: 'Back to the starting layout',
                        icon: const Icon(Icons.restart_alt_rounded),
                        onPressed: () => _dash.currentState?.resetLayout(),
                      ),
                      FilledButton(onPressed: () => setState(() => _editing = false), child: const Text('Done')),
                    ] else ...[
                      IconButton(
                        tooltip: 'Edit home',
                        icon: Icon(Icons.dashboard_customize_outlined, color: p.muted),
                        onPressed: () => setState(() => _editing = true),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => widget.onOpenTab(3),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: p.raised,
                          child: Text(
                            settings.name.isEmpty ? '?' : settings.name.characters.first.toUpperCase(),
                            style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 17),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_editing)
                ContentWidth(
                  maxWidth: 960,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Tap a widget to change its size, shape and colour. Hold and drag to move it.',
                      style: TextStyle(color: p.muted),
                    ),
                  ),
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
            return Wrap(
              runSpacing: 12,
              children: [
                for (final app in miniApps)
                  SizedBox(
                    width: w,
                    child: _AppTile(app: app, muted: p.muted),
                  ),
              ],
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
      borderRadius: BorderRadius.circular(20),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _news.loadCache(context.settings);
    if (_news.stale) {
      _news
          .refresh(context.settings)
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((_) {});
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
                child: Text('Loading the latest news…', style: TextStyle(color: p.muted)),
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
