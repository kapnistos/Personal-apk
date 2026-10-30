import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../apps/ai/ai_chat_page.dart';
import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/internships/internships_page.dart';
import '../apps/news/news_page.dart';
import '../apps/news/news_service.dart';
import '../apps/notes/notes_page.dart';
import '../apps/registry.dart';
import '../apps/spaces/my_spaces.dart';
import '../apps/todo/todo_page.dart';
import '../apps/wallet/insights.dart' show SpendPlan, spendTargetKey;
import '../apps/wallet/wallet_model.dart';
import '../apps/wallet/wallet_page.dart';
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
import 'search_page.dart';
import 'shell.dart' show navFogHeight;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dash = GlobalKey<DashboardState>();
  final _ask = TextEditingController();
  bool _editing = false;

  static const _askHeight = 56.0;

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  void _startEditing() {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() => _editing = true);
  }

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

  /// Hands whatever was typed to the Hub agent, which can add the task, log the expense or just answer.
  void _sendAsk() {
    final text = _ask.text.trim();
    _ask.clear();
    FocusScope.of(context).unfocus();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AiChatPage(agent: true, initialText: text.isEmpty ? null : text)));
  }

  Widget _topRow(BuildContext context, String name) {
    final p = Palette.of(context);
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Me and settings',
          child: GestureDetector(
            // Your profile holds every setting.
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MePage())),
            child: Pressable(
              child: CircleAvatar(
                radius: 24,
                backgroundColor: p.accent,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700, fontSize: 19),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Search',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
              child: Pressable(
                scale: 0.98,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: p.muted, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Search', maxLines: 1, style: TextStyle(color: p.muted, fontSize: 16.5)),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 720)
                        Text(
                          'Ctrl K',
                          style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _RoundButton(icon: Icons.tune_rounded, tooltip: 'Edit home', onTap: _startEditing),
      ],
    );
  }

  Widget _header(BuildContext context, String name, bool greet) {
    final p = Palette.of(context);
    final now = DateTime.now();
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Edit home',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              FilledButton(onPressed: () => setState(() => _editing = false), child: const Text('Done')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RoundButton(
                icon: Icons.restart_alt_rounded,
                tooltip: 'Back to the starting layout',
                onTap: _confirmReset,
              ),
              const SizedBox(width: 8),
              _RoundButton(icon: Icons.apps_rounded, tooltip: 'Choose apps', onTap: () => pickVisibleApps(context)),
              const Spacer(),
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Add a widget',
                onTap: () => _dash.currentState?.addWidget(),
              ),
            ],
          ),
        ],
      );
    }
    return GestureDetector(
      // Holding any part of Home starts arranging.
      onLongPress: _startEditing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topRow(context, name),
          if (greet) ...[
            const SizedBox(height: 18),
            Text(
              DateFormat('EEEE d MMMM').format(now),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.muted),
            ),
            const SizedBox(height: 2),
            Text(
              name.isEmpty ? greeting(now) : '${greeting(now)}, $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.9, height: 1.15),
            ),
          ],
        ],
      ),
    );
  }

  /// Weather, the three numbers for today and the apps: the fixed top of Home. Holding it starts arranging.
  Widget _hero(BuildContext context) => GestureDetector(
    onLongPress: _startEditing,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const WeatherHero(),
        _TodayStrip(
          onCalendar: () => widget.onOpenTab(1),
          onTasks: () => widget.onOpenTab(2),
          onWallet: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage())),
        ),
        const SizedBox(height: 6),
        const AppGrid(),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // The page runs on under the bottom bar; padding.bottom is the bar and its fog.
    final pad = MediaQuery.paddingOf(context).bottom;
    final underBar = pad > navFogHeight;
    // The ask bar rests just above the bar's fog, so the fog never dims it.
    final askBottom = underBar ? pad + 2 : pad + 12;
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) setState(() => _editing = false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, askBottom + _askHeight + 24),
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
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'Hold and drag a widget to move it. Tap one to change its size, shape and colour.',
                                style: TextStyle(color: p.muted),
                              ),
                            ),
                          )
                        : ContentWidth(maxWidth: 960, child: _hero(context)),
                  ),
                  const SizedBox(height: 16),
                  ContentWidth(
                    maxWidth: 960,
                    child: Dashboard(key: _dash, editing: _editing, onEditing: (v) => setState(() => _editing = v)),
                  ),
                ],
              ),
            ),
            if (!_editing) ...[
              // A soft fog behind the ask bar, so the page fades out under it as it does under the bottom bar.
              Positioned(
                left: 0,
                right: 0,
                bottom: underBar ? pad - navFogHeight : 0,
                height: (underBar ? navFogHeight + 2 : askBottom) + _askHeight + 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [p.background.withValues(alpha: 0), p.background.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: askBottom,
                child: ContentWidth(
                  child: _QuickAsk(controller: _ask, height: _askHeight, onSend: _sendAsk),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A neutral grey circle with one icon: the tune button and the edit-mode actions.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Pressable(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
              child: Icon(icon, color: p.ink, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Add a task, expense or question": one line that goes straight to the Hub agent.
class _QuickAsk extends StatelessWidget {
  const _QuickAsk({required this.controller, required this.height, required this.onSend});
  final TextEditingController controller;
  final double height;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height,
          padding: const EdgeInsets.only(left: 18, right: 6),
          decoration: BoxDecoration(
            color: (dark ? p.raised : p.surface).withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: p.line.withValues(alpha: dark ? 0.9 : 1), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: p.muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Add a task, expense or question',
                    hintMaxLines: 1,
                    hintStyle: TextStyle(color: p.muted, fontSize: 16, overflow: TextOverflow.ellipsis),
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Ask Hub',
                child: Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: onSend,
                    child: Pressable(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                        child: Icon(Icons.arrow_upward_rounded, color: p.background, size: 23),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whole currency units, the way a glance needs them: €261, not €261.40.
String _wholeMoney(int cents, String currency) =>
    NumberFormat.simpleCurrency(name: currency, decimalDigits: 0).format(cents / 100);

/// Next up, due today and left to spend, in one strip. Each cell opens where the number comes from.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.onCalendar, required this.onTasks, required this.onWallet});
  final VoidCallback onCalendar;
  final VoidCallback onTasks;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = addDays(today, 1);
    final month = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    final currency = context.settings.currency;
    final target = int.tryParse(context.settings.raw(spendTargetKey) ?? '');
    Widget gap() => Container(width: 1.5, color: p.background);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ColoredBox(
          color: p.surface,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StreamBuilder<List<Calendar>>(
                    stream: db.watchCalendars(),
                    builder: (context, cSnap) {
                      final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
                      return StreamBuilder<List<Event>>(
                        stream: db.watchEventsBetween(today, tomorrow),
                        builder: (context, snap) {
                          final next =
                              expand(
                                  snap.data ?? const [],
                                  cals,
                                  today,
                                  tomorrow,
                                ).where((o) => !o.allDay && o.start.isAfter(now)).toList()
                                ..sort((a, b) => a.start.compareTo(b.start));
                          final o = next.firstOrNull;
                          return _StripCell(
                            value: o == null ? 'Free' : DateFormat.Hm().format(o.start),
                            label: o == null ? 'Rest of day' : 'Next up',
                            onTap: onCalendar,
                          );
                        },
                      );
                    },
                  ),
                ),
                gap(),
                Expanded(
                  child: StreamBuilder<List<Todo>>(
                    stream: db.watchTodos(),
                    builder: (context, snap) => _StripCell(
                      value: '${(snap.data ?? const <Todo>[]).where((t) => isTodayTask(t, now: now)).length}',
                      label: 'Due today',
                      onTap: onTasks,
                    ),
                  ),
                ),
                gap(),
                Expanded(
                  child: StreamBuilder<List<Entry>>(
                    stream: db.watchEntries(month, monthEnd),
                    builder: (context, eSnap) => StreamBuilder<List<Subscription>>(
                      stream: db.watchSubscriptions(),
                      builder: (context, sSnap) {
                        final entries = eSnap.data ?? const <Entry>[];
                        // Booked payments are entries already; count only what is still to leave this month.
                        final spent = MonthSummary(entries.where((e) => !e.date.isAfter(now)).toList()).out;
                        if (target == null || target <= 0) {
                          return _StripCell(value: _wholeMoney(spent, currency), label: 'Spent', onTap: onWallet);
                        }
                        final billsAhead = (sSnap.data ?? const <Subscription>[])
                            .where(
                              (s) =>
                                  s.active &&
                                  s.kind.sign < 0 &&
                                  !s.nextDate.isBefore(today) &&
                                  s.nextDate.isBefore(monthEnd),
                            )
                            .fold<int>(0, (t, s) => t + s.amountCents);
                        final plan = SpendPlan(target: target, spent: spent, billsAhead: billsAhead, now: now);
                        return _StripCell(
                          value: _wholeMoney(plan.left.abs(), currency),
                          label: plan.over ? 'Over target' : 'To spend',
                          warn: plan.over,
                          onTap: onWallet,
                        );
                      },
                    ),
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

class _StripCell extends StatelessWidget {
  const _StripCell({required this.value, required this.label, required this.onTap, this.warn = false});
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Pressable(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                            height: 1.15,
                            color: warn ? p.danger : p.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted.withValues(alpha: 0.7), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where each app sits on Home. Your own spaces join Life; anything new lands under More.
const _appGroups = [
  ('Plan', ['calendar', 'todo', 'notes', 'habits', 'weather']),
  ('Life', ['wallet', 'shopping', 'space:', 'news']),
  ('Work and chat', ['job', 'uni', 'lab', 'internships', 'spaces', 'mail', 'claude']),
];

/// Splits the apps into Home's groups, keeping each group's own order. Empty groups are left out.
List<(String, List<MiniApp>)> groupApps(List<MiniApp> apps) {
  int rank(List<String> ids, MiniApp a) => ids.indexOf(a.id.startsWith('space:') ? 'space:' : a.id);
  final out = <(String, List<MiniApp>)>[];
  final placed = <MiniApp>{};
  for (final (title, ids) in _appGroups) {
    final members = apps.where((a) => rank(ids, a) >= 0).toList();
    // A stable sort, so your spaces keep their own order.
    final ranked = [for (final (i, a) in members.indexed) (rank(ids, a), i, a)]
      ..sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));
    placed.addAll(members);
    if (ranked.isNotEmpty) out.add((title, [for (final r in ranked) r.$3]));
  }
  final rest = apps.where((a) => !placed.contains(a)).toList();
  if (rest.isNotEmpty) out.add(('More', rest));
  return out;
}

/// Every app as a round button, grouped under Plan, Life and Work and chat, five to a row on a phone.
class AppGrid extends StatelessWidget {
  const AppGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final hidden = hiddenApps(context.settings);
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 640 ? (c.maxWidth / 104).floor().clamp(5, 9) : 5;
        final w = c.maxWidth / perRow;
        final glyph = (w - 14).clamp(40.0, 54.0);
        return StreamBuilder<List<Space>>(
          stream: db.watchSpaces(),
          builder: (context, sSnap) => StreamBuilder<List<Todo>>(
            stream: db.watchTodos(),
            builder: (context, tSnap) {
              final now = DateTime.now();
              final due = (tSnap.data ?? const <Todo>[]).where((t) => isTodayTask(t, now: now)).length;
              final apps = [
                for (final a in [...miniApps, ...customSpaceApps(sSnap.data ?? const [])])
                  if (!hidden.contains(a.id)) a,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, group) in groupApps(apps)) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 4), child: SectionLabel(title)),
                    // No gap between rows: the space between circles belongs to the circles, so every tap lands.
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final app in group)
                          SizedBox(
                            width: w,
                            child: AppCircle(
                              icon: app.icon,
                              color: app.color,
                              label: app.title,
                              size: glyph,
                              dimmed: !app.available,
                              badge: app.id == 'todo' ? due : 0,
                              onTap: () => app.open(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

bool _rainy(int code) => (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;

/// The big weather card at the top of Home: now, today's range, when rain comes, and the next four hours.
class WeatherHero extends StatelessWidget {
  const WeatherHero({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<City>>(
      stream: context.db.watchCities(),
      builder: (context, snap) {
        final city = selectedCity(context, snap.data ?? const <City>[]);
        if (city == null) return const SizedBox.shrink();
        return _WeatherHeroCard(key: ValueKey(city.id), city: city);
      },
    );
  }
}

class _WeatherHeroCard extends StatefulWidget {
  const _WeatherHeroCard({super.key, required this.city});
  final City city;

  @override
  State<_WeatherHeroCard> createState() => _WeatherHeroCardState();
}

class _WeatherHeroCardState extends State<_WeatherHeroCard> {
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

  /// "Rain from 15:05", "Rain until 16:20", or nothing when it stays dry.
  String? _rainLine(Forecast? f) {
    final hm = DateFormat.Hm().format;
    final n = _n;
    if (n != null && n.points.isNotEmpty) {
      if (n.dry) return null;
      if (n.points.first.mmPerHour >= 0.1) {
        final stop = n.points.where((p) => p.mmPerHour < 0.1).firstOrNull;
        return stop == null ? 'Rain for a while' : 'Rain until ${hm(stop.time)}';
      }
      return 'Rain from ${hm(n.points.firstWhere((p) => p.mmPerHour >= 0.1).time)}';
    }
    // No radar here: fall back to the hourly forecast.
    final h = f?.hours.take(5).where((h) => _rainy(h.code) && h.rainChance >= 50).firstOrNull;
    return h == null ? null : 'Rain around ${hm(h.time)}';
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final unit = context.settings.tempUnit;
    final today = f?.days.firstOrNull;
    final night = f != null && !f.isDay;
    final rain = _rainLine(f);
    const white = Colors.white;
    final soft = white.withValues(alpha: 0.82);

    final now = DateTime.now();
    final thisHour = DateTime(now.year, now.month, now.day, now.hour);
    bool dayAt(DateTime t) => today == null || (t.isAfter(today.sunrise) && t.isBefore(today.sunset));
    final slots = <(String, int, double, bool, bool)>[
      if (f != null) ('Now', f.code, f.temperature, f.isDay, false),
      if (f != null)
        for (final h in f.hours.where((h) => h.time.isAfter(thisHour)).take(4))
          (DateFormat.Hm().format(h.time), h.code, h.temperature, dayAt(h.time), _rainy(h.code) || h.rainChance >= 60),
    ];
    // Only the first wet hour stands out.
    final wetAt = slots.indexWhere((s) => s.$5);

    return Semantics(
      button: true,
      label: 'Weather in ${widget.city.name}',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeatherPage())),
        child: Pressable(
          scale: 0.98,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: night ? SkyColors.night : SkyColors.day,
              ),
              // A faint rim of light along the top edge, like glass catching the sky.
              border: Border.all(color: white.withValues(alpha: 0.10), width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.city.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (today != null)
                      Text(
                        'H ${formatTemp(today.max, unit)}  L ${formatTemp(today.min, unit)}',
                        style: TextStyle(color: soft, fontSize: 15.5, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              f == null ? '--' : formatTemp(f.temperature, unit),
                              style: const TextStyle(
                                color: white,
                                fontSize: 72,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -3,
                                height: 1.1,
                              ),
                            ),
                          ),
                          Text(
                            f == null ? 'Loading' : WeatherCode.label(f.code),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          if (rain != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.fromLTRB(11, 7, 14, 7),
                              decoration: BoxDecoration(
                                color: white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.water_drop_rounded, color: white, size: 15),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      rain,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: white, fontSize: 14.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (f != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(WeatherCode.icon(f.code, isDay: f.isDay), color: white, size: 76),
                      ),
                  ],
                ),
                if (slots.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Container(height: 1, color: white.withValues(alpha: 0.2)),
                  ),
                  Row(
                    children: [
                      for (final (i, (label, code, temp, isDay, _)) in slots.indexed)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: i == wetAt ? white.withValues(alpha: 0.14) : null,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: i == wetAt ? white : soft,
                                      fontSize: 14.5,
                                      fontWeight: i == wetAt ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Icon(WeatherCode.icon(code, isDay: isDay), color: white, size: 22),
                                const SizedBox(height: 7),
                                Text(
                                  formatTemp(temp, unit),
                                  maxLines: 1,
                                  style: const TextStyle(color: white, fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
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
