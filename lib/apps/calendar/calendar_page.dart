import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'calendar_model.dart';
import 'event_editor.dart';

enum CalView { month, week, threeDay, day, agenda }

extension on CalView {
  String get label => switch (this) {
    CalView.month => 'Month',
    CalView.week => 'Week',
    CalView.threeDay => '3 days',
    CalView.day => 'Day',
    CalView.agenda => 'Agenda',
  };
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalView? _view;
  DateTime _anchor = dateOnly(DateTime.now());
  DateTime _selected = dateOnly(DateTime.now());

  bool _wide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

  CalView _effectiveView(BuildContext context) => _view ?? (_wide(context) ? CalView.week : CalView.month);

  (DateTime, DateTime) _range(CalView v) => rangeFor(v, _anchor);

  static (DateTime, DateTime) rangeFor(CalView v, DateTime anchor) => switch (v) {
    CalView.month => (monthGridStart(anchor), addDays(monthGridStart(anchor), 42)),
    CalView.week => (weekStart(anchor), addDays(weekStart(anchor), 7)),
    CalView.threeDay => (anchor, addDays(anchor, 3)),
    CalView.day => (anchor, addDays(anchor, 1)),
    CalView.agenda => (addDays(anchor, -1), addDays(anchor, 60)),
  };

  /// Pages scroll sideways without end; page [_origin] shows [_base].
  static const _origin = 100000;
  DateTime _base = dateOnly(DateTime.now());
  PageController _pages = PageController(initialPage: _origin);
  int _page = _origin;

  static DateTime shift(CalView v, DateTime base, int n) => switch (v) {
    CalView.month => DateTime(base.year, base.month + n, 1),
    CalView.week => addDays(base, 7 * n),
    CalView.threeDay => addDays(base, 3 * n),
    CalView.day || CalView.agenda => addDays(base, n),
  };

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    final v = _effectiveView(context);
    setState(() {
      _page = page;
      _anchor = shift(v, _base, page - _origin);
      if (v == CalView.month) {
        // Keep the same day number when moving between months, if it exists.
        final last = DateTime(_anchor.year, _anchor.month + 1, 0).day;
        final today = dateOnly(DateTime.now());
        _selected = _anchor.year == today.year && _anchor.month == today.month
            ? today
            : DateTime(_anchor.year, _anchor.month, _selected.day > last ? last : _selected.day);
      }
      if (v == CalView.day) _selected = _anchor;
    });
  }

  void _step(int dir) {
    if (_effectiveView(context) == CalView.agenda) {
      _goTo(addDays(_anchor, 30 * dir));
      return;
    }
    _pages.animateToPage(_page + dir, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _today() => _goTo(DateTime.now());

  void _goTo(DateTime day, {CalView? view}) => setState(() {
    if (view != null) _view = view;
    final v = _effectiveView(context);
    final d = dateOnly(day);
    _selected = d;
    _base = v == CalView.month ? DateTime(d.year, d.month, 1) : d;
    _anchor = _base;
    _page = _origin;
    _pages.dispose();
    _pages = PageController(initialPage: _origin);
  });

  void _setView(CalView v) => _goTo(_selected, view: v);

  String _title(CalView v) {
    switch (v) {
      case CalView.month:
        return DateFormat('MMMM y').format(_anchor);
      case CalView.day:
        return DateFormat('EEE d MMMM').format(_anchor);
      case CalView.week:
      case CalView.threeDay:
      case CalView.agenda:
        final (a, b) = _range(v);
        final last = addDays(b, -1);
        if (v == CalView.agenda) return 'From ${DateFormat('d MMM').format(a)}';
        return a.month == last.month
            ? DateFormat('MMMM y').format(a)
            : '${DateFormat('MMM').format(a)} – ${DateFormat('MMM y').format(last)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final wide = _wide(context);
    final view = _effectiveView(context);
    final p = Palette.of(context);

    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, calSnap) {
        final cals = {for (final c in calSnap.data ?? const <Calendar>[]) c.id: c};
        return Scaffold(
          appBar: AppBar(
            titleSpacing: wide ? 20 : null,
            title: Text(_title(view)),
            actions: [
              TextButton(onPressed: _today, child: const Text('Today')),
              IconButton(tooltip: 'Previous', onPressed: () => _step(-1), icon: const Icon(Icons.chevron_left_rounded)),
              IconButton(tooltip: 'Next', onPressed: () => _step(1), icon: const Icon(Icons.chevron_right_rounded)),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 16),
                  child: SegmentedButton<CalView>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    segments: [
                      for (final v in [CalView.day, CalView.week, CalView.month, CalView.agenda])
                        ButtonSegment(value: v, label: Text(v.label)),
                    ],
                    selected: {view},
                    onSelectionChanged: (s) => _setView(s.first),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: 'Calendars',
                  icon: const Icon(Icons.layers_outlined),
                  onPressed: () => showCalendarsSheet(context),
                ),
                PopupMenuButton<CalView>(
                  tooltip: 'View',
                  icon: const Icon(Icons.view_agenda_outlined),
                  initialValue: view,
                  onSelected: _setView,
                  itemBuilder: (_) => [
                    for (final v in [CalView.day, CalView.threeDay, CalView.month, CalView.agenda])
                      PopupMenuItem(value: v, child: Text(v.label)),
                  ],
                ),
              ],
            ],
          ),
          floatingActionButton: wide
              ? null
              : FloatingActionButton(
                  tooltip: 'New event',
                  onPressed: () => openEventEditor(context, start: _defaultStart()),
                  child: const Icon(Icons.add_rounded),
                ),
          body: Builder(
            builder: (context) {
              Widget period(DateTime anchor) {
                final (from, to) = rangeFor(view, anchor);
                return StreamBuilder<List<Event>>(
                  stream: db.watchEventsBetween(from, to),
                  builder: (context, snap) {
                    final occ = expand(snap.data ?? const [], cals, from, to);
                    return switch (view) {
                      CalView.month => _MonthView(
                        anchor: anchor,
                        selected: _selected,
                        occ: occ,
                        compact: !wide,
                        onSelect: (d) => setState(() => _selected = d),
                        onOpenDay: (d) => _goTo(d, view: CalView.day),
                      ),
                      CalView.week => _TimeGrid(days: _days(from, 7), occ: occ),
                      CalView.threeDay => _TimeGrid(days: _days(from, 3), occ: occ),
                      CalView.day => _TimeGrid(days: [anchor], occ: occ),
                      CalView.agenda => const SizedBox.shrink(),
                    };
                  },
                );
              }

              final main = view == CalView.agenda
                  ? _Agenda(key: ValueKey(_base), start: _base, calendars: cals)
                  : PageView.builder(
                      key: ValueKey((view, _base)),
                      controller: _pages,
                      onPageChanged: _onPage,
                      itemBuilder: (context, i) => period(shift(view, _base, i - _origin)),
                    );
              if (!wide) return main;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 264,
                    child: _Sidebar(
                      calendars: cals.values.toList(),
                      anchor: _anchor,
                      selected: _selected,
                      onPick: (d) => _goTo(d, view: view == CalView.month ? CalView.month : null),
                      onNew: () => openEventEditor(context, start: _defaultStart()),
                    ),
                  ),
                  VerticalDivider(width: 1, color: p.line),
                  Expanded(child: main),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<DateTime> _days(DateTime from, int n) => [
    for (var i = 0; i < n; i++) DateTime(from.year, from.month, from.day + i),
  ];

  DateTime _defaultStart() {
    final now = DateTime.now();
    final base = _selected == dateOnly(now) ? now : _selected.add(const Duration(hours: 9));
    // Next half hour.
    final m = base.minute < 30 ? 30 : 60;
    return DateTime(base.year, base.month, base.day, base.hour).add(Duration(minutes: m));
  }
}

// Sidebar (wide screens): new event, mini month, calendar list.

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.calendars,
    required this.anchor,
    required this.selected,
    required this.onPick,
    required this.onNew,
  });
  final List<Calendar> calendars;
  final DateTime anchor;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    return Container(
      color: p.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add_rounded), label: const Text('New event')),
          const SizedBox(height: 16),
          MiniMonth(initial: anchor, selected: selected, onPick: onPick),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: SectionLabel('My calendars')),
              PopupMenuButton<String>(
                tooltip: 'Add calendar',
                icon: const Icon(Icons.add_rounded, size: 20),
                onSelected: (v) => v == 'new' ? editCalendar(context, null) : subscribeCalendar(context),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'new', child: Text('New calendar')),
                  PopupMenuItem(value: 'link', child: Text('Subscribe by link')),
                ],
              ),
            ],
          ),
          for (final c in calendars)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => db.saveCalendar(c.toCompanion(false).copyWith(visible: Value(!c.visible))),
              onLongPress: () => editCalendar(context, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: c.visible ? Color(c.color) : Colors.transparent,
                        border: Border.all(color: Color(c.color), width: 2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: c.visible ? const Icon(Icons.check_rounded, size: 11, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.name)),
                    if (c.icsUrl != null) Icon(Icons.link_rounded, size: 16, color: p.muted),
                    IconButton(
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.more_horiz_rounded, size: 18, color: p.muted),
                      onPressed: () => editCalendar(context, c),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MiniMonth extends StatefulWidget {
  const MiniMonth({super.key, required this.initial, required this.selected, required this.onPick});
  final DateTime initial;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;

  @override
  State<MiniMonth> createState() => _MiniMonthState();
}

class _MiniMonthState extends State<MiniMonth> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  @override
  void didUpdateWidget(MiniMonth old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _month = DateTime(widget.initial.year, widget.initial.month);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final start = monthGridStart(_month);
    final today = dateOnly(DateTime.now());
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(DateFormat('MMMM y').format(_month), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = DateTime(start.year, start.month, start.day + w * 7 + i);
                      final isSel = day == widget.selected;
                      final isToday = day == today;
                      final inMonth = day.month == _month.month;
                      return AspectRatio(
                        aspectRatio: 1,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onPick(day),
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSel ? p.accent : (isToday ? p.accent.withValues(alpha: 0.14) : null),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w400,
                                color: isSel ? p.onAccent : (inMonth ? p.ink : p.muted.withValues(alpha: 0.6)),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// Month view

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.anchor,
    required this.selected,
    required this.occ,
    required this.compact,
    required this.onSelect,
    required this.onOpenDay,
  });
  final DateTime anchor;
  final DateTime selected;
  final List<Occurrence> occ;
  final bool compact;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final start = monthGridStart(anchor);
    final today = dateOnly(DateTime.now());
    final grid = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.E().format(addDays(start, i)).toUpperCase(),
                      style: TextStyle(fontSize: 12, letterSpacing: 0.6, color: p.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: p.line),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final day = DateTime(start.year, start.month, start.day + w * 7 + i);
                              return _MonthCell(
                                day: day,
                                inMonth: day.month == anchor.month,
                                isToday: day == today,
                                isSelected: day == selected,
                                occ: occ.where((o) => o.touches(day)).toList(),
                                compact: compact,
                                onTap: () => onSelect(day),
                                onDoubleTap: () => onOpenDay(day),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (!compact) return Container(color: p.surface, child: grid);
    final dayOcc = occ.where((o) => o.touches(selected)).toList();
    return Column(
      children: [
        Expanded(
          flex: 11,
          child: Container(color: p.surface, child: grid),
        ),
        Divider(height: 1, color: p.line),
        Expanded(
          flex: 8,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              Text(
                friendlyDay(selected) == DateFormat.EEEE().format(selected)
                    ? DateFormat('EEEE d MMMM').format(selected)
                    : '${friendlyDay(selected)}, ${DateFormat('d MMMM').format(selected)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (dayOcc.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No events', style: TextStyle(color: p.muted)),
                ),
              for (final o in dayOcc) EventRow(o: o),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.occ,
    required this.compact,
    required this.onTap,
    required this.onDoubleTap,
  });
  final DateTime day;
  final bool inMonth, isToday, isSelected, compact;
  final List<Occurrence> occ;
  final VoidCallback onTap, onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected && compact
              ? p.accent.withValues(alpha: 0.07)
              : (inMonth ? null : p.background.withValues(alpha: 0.5)),
          border: Border(
            right: BorderSide(color: p.line, width: 0.5),
            bottom: BorderSide(color: p.line, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, c) {
            final header = Align(
              alignment: compact ? Alignment.topCenter : Alignment.topLeft,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? p.accent : null),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday ? p.onAccent : (inMonth ? p.ink : p.muted.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            );
            if (compact) {
              return Column(
                children: [
                  header,
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final o in occ.take(4))
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(color: o.color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
              );
            }
            final fit = ((c.maxHeight - 28) / 20).floor().clamp(0, 10);
            final shown = occ.length > fit ? (fit - 1).clamp(0, 10) : occ.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 2),
                for (final o in occ.take(shown)) _MonthChip(o: o, day: day),
                if (occ.length > shown)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Text(
                      '${occ.length - shown} more',
                      style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.o, required this.day});
  final Occurrence o;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final filled = o.allDay || o.end.difference(o.start).inHours >= 24;
    return GestureDetector(
      onTap: () => showEventDetails(context, o),
      child: Container(
        height: 18,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(color: filled ? o.color : null, borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            if (!filled) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: o.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(DateFormat.Hm().format(o.start), style: TextStyle(fontSize: 12, color: p.muted)),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                o.event.title,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: filled ? Colors.white : p.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Time grid (day, 3 days, week)

const _hourHeight = 52.0;
const _gutter = 52.0;

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({required this.days, required this.occ});
  final List<DateTime> days;
  final List<Occurrence> occ;

  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  late final ScrollController _scroll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _scroll = ScrollController(initialScrollOffset: ((now.hour - 1.5).clamp(0, 16)) * _hourHeight);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final today = dateOnly(DateTime.now());
    final allDay = widget.occ.where((o) => o.allDay || o.end.difference(o.start).inHours >= 24).toList();
    final timed = widget.occ.where((o) => !allDay.contains(o)).toList();
    final maxAllDay = widget.days.fold<int>(0, (m, d) {
      final n = allDay.where((o) => o.touches(d)).length;
      return n > m ? n : m;
    });

    return Container(
      color: p.surface,
      child: Column(
        children: [
          // Day headers
          Padding(
            padding: const EdgeInsets.only(left: _gutter, top: 6, bottom: 6),
            child: Row(
              children: [
                for (final d in widget.days)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          DateFormat.E().format(d).toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: d == today ? p.accent : p.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: d == today ? p.accent : null),
                          child: Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: d == today ? p.onAccent : p.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (maxAllDay > 0)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3, right: 8),
                      child: Text(
                        'all-day',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11.5, color: p.muted),
                      ),
                    ),
                  ),
                  for (final d in widget.days)
                    Expanded(
                      child: Column(
                        children: [
                          for (final o in allDay.where((o) => o.touches(d)))
                            GestureDetector(
                              onTap: () => showEventDetails(context, o),
                              child: Container(
                                height: 20,
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(1, 0, 1, 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(color: o.color, borderRadius: BorderRadius.circular(4)),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  o.event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Divider(height: 1, color: p.line),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: 24 * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _gutter,
                      child: Stack(
                        children: [
                          for (var h = 1; h < 24; h++)
                            Positioned(
                              top: h * _hourHeight - 7,
                              right: 8,
                              child: Text(
                                '${h.toString().padLeft(2, '0')}:00',
                                style: TextStyle(fontSize: 11.5, color: p.muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final d in widget.days)
                      Expanded(
                        child: _DayColumn(day: d, occ: timed.where((o) => o.touches(d)).toList(), isToday: d == today),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.occ, required this.isToday});
  final DateTime day;
  final List<Occurrence> occ;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final placed = layoutDay(occ);
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final minutes = (d.localPosition.dy / _hourHeight * 60 / 30).floor() * 30;
            openEventEditor(context, start: day.add(Duration(minutes: minutes)));
          },
          child: Stack(
            children: [
              // Hour lines
              for (var h = 0; h < 24; h++)
                Positioned(
                  top: h * _hourHeight,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: p.line.withValues(alpha: h == 0 ? 0 : 0.8)),
                ),
              Positioned(top: 0, bottom: 0, left: 0, child: Container(width: 1, color: p.line)),
              for (final (o, col, n) in placed)
                Builder(
                  builder: (context) {
                    final s = o.start.isBefore(day) ? day : o.start;
                    final dayEnd = addDays(day, 1);
                    final e = o.end.isAfter(dayEnd) ? dayEnd : o.end;
                    final top = s.difference(day).inMinutes / 60 * _hourHeight;
                    final height = (e.difference(s).inMinutes / 60 * _hourHeight).clamp(20.0, 24 * _hourHeight);
                    final colW = (w - 4) / n;
                    return Positioned(
                      top: top + 1,
                      left: 2 + col * colW,
                      width: colW - 2,
                      height: height - 2,
                      child: _EventBlock(o: o, past: o.end.isBefore(now)),
                    );
                  },
                ),
              if (isToday)
                Positioned(
                  top: (now.hour * 60 + now.minute) / 60 * _hourHeight - 4,
                  left: -4,
                  right: 0,
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
                      ),
                      Expanded(child: Container(height: 2, color: p.danger)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({required this.o, required this.past});
  final Occurrence o;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(o.color.withValues(alpha: dark ? 0.32 : 0.16), Palette.of(context).surface);
    final fg = dark ? Color.lerp(o.color, Colors.white, 0.6)! : Color.lerp(o.color, Colors.black, 0.45)!;
    final minutes = o.end.difference(o.start).inMinutes;
    return Opacity(
      opacity: past ? 0.6 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showEventDetails(context, o),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: o.color, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
            // Short events cut their text off rather than spill out of the block.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.event.title,
                    maxLines: minutes >= 60 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg, height: 1.2),
                  ),
                  if (minutes >= 45)
                    Text(
                      '${DateFormat.Hm().format(o.start)} – ${DateFormat.Hm().format(o.end)}'
                      '${o.event.location.isNotEmpty ? ' · ${o.event.location}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)),
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

// Agenda

class _Agenda extends StatefulWidget {
  const _Agenda({super.key, required this.start, required this.calendars});
  final DateTime start;
  final Map<int, Calendar> calendars;

  @override
  State<_Agenda> createState() => _AgendaState();
}

/// One long list that keeps loading further ahead as you scroll, with month headings.
class _AgendaState extends State<_Agenda> {
  late DateTime _from = dateOnly(widget.start);
  int _days = 120;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600 && _days < 3650) setState(() => _days += 120);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final to = addDays(_from, _days);
    return StreamBuilder<List<Event>>(
      stream: context.db.watchEventsBetween(_from, to),
      builder: (context, snap) {
        final occ = expand(snap.data ?? const [], widget.calendars, _from, to);
        final byDay = <DateTime, List<Occurrence>>{};
        for (final o in occ) {
          final d = dateOnly(o.start.isBefore(_from) ? _from : o.start);
          (byDay[d] ??= []).add(o);
        }
        final today = dateOnly(DateTime.now());
        if (!today.isBefore(_from) && today.isBefore(to)) byDay.putIfAbsent(today, () => []);
        final days = byDay.keys.toList()..sort();
        // Rows: month headings and days.
        final rows = <(bool, DateTime)>[];
        DateTime? month;
        for (final d in days) {
          if (month == null || d.month != month.month || d.year != month.year) {
            month = DateTime(d.year, d.month);
            rows.add((true, month));
          }
          rows.add((false, d));
        }
        return ContentWidth(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            itemCount: rows.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Align(
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _from = addDays(_from, -30);
                      _days += 30;
                    }),
                    icon: const Icon(Icons.expand_less_rounded),
                    label: const Text('Show earlier'),
                  ),
                );
              }
              if (i == rows.length + 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      _days >= 3650 ? 'That is ten years ahead.' : 'Loading further ahead as you scroll…',
                      style: TextStyle(color: p.muted, fontSize: 13.5),
                    ),
                  ),
                );
              }
              final (isMonth, d) = rows[i - 1];
              if (isMonth) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
                  child: Text(
                    DateFormat('MMMM y').format(d),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                );
              }
              final list = byDay[d] ?? const <Occurrence>[];
              final isToday = d == today;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Column(
                        children: [
                          Text(
                            DateFormat.E().format(d).toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              color: isToday ? p.accent : p.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: isToday ? BoxDecoration(color: p.accent, shape: BoxShape.circle) : null,
                            child: Text(
                              '${d.day}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: isToday ? p.onAccent : p.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text('Nothing planned today', style: TextStyle(color: p.muted)),
                            )
                          : Column(children: [for (final o in list) EventRow(o: o)]),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.o});
  final Occurrence o;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: p.raised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showEventDetails(context, o),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(color: o.color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.event.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        [
                          o.allDay
                              ? 'All day'
                              : '${DateFormat.Hm().format(o.start)} – ${DateFormat.Hm().format(o.end)}',
                          if (o.event.location.isNotEmpty) o.event.location,
                        ].join(' · '),
                        style: TextStyle(color: p.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
