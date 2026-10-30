import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../apps/calendar/calendar_model.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/calendar/event_editor.dart';
import '../apps/habits/habits_page.dart';
import '../apps/internships/internships_page.dart';
import '../apps/news/news_page.dart';
import '../apps/news/news_service.dart';
import '../apps/notes/notes_page.dart';
import '../apps/shopping/shopping_model.dart';
import '../apps/shopping/shopping_page.dart';
import '../apps/spaces/space_page.dart';
import '../apps/spaces/work_log.dart';
import '../apps/todo/todo_page.dart';
import '../apps/wallet/accounts_page.dart';
import '../apps/wallet/investing_page.dart';
import '../apps/wallet/wallet_model.dart';
import '../apps/wallet/wallet_page.dart';
import '../core/edition.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'shortcuts.dart';

/// How big a widget is: s takes half a phone row, m and l the whole row
/// (on wide screens m is half and s a third).
const dashSizes = ['s', 'm', 'l'];
const dashSizeLabels = {'s': 'Small', 'm': 'Medium', 'l': 'Large'};

/// Corner shapes, by radius.
const dashShapes = {'square': 6.0, 'soft': 14.0, 'rounded': 22.0, 'round': 32.0};
const dashShapeLabels = {'square': 'Square', 'soft': 'Soft', 'rounded': 'Rounded', 'round': 'Round'};

/// How the widget's card is drawn.
const dashStyles = ['card', 'tinted', 'outline', 'plain'];
const dashStyleLabels = {'card': 'Card', 'tinted': 'Tinted', 'outline': 'Outline', 'plain': 'No card'};

const dashColors = [
  0xFF1F7A5A, 0xFF3A78C9, 0xFF6650AE, 0xFFC0563F, 0xFFCF9418, 0xFF2D8C9E, 0xFFB5487A, 0xFF5F6B7A, //
];

/// One widget on the home screen and how it looks.
class DashItem {
  DashItem({
    required this.id,
    required this.type,
    required this.size,
    this.shape = 'rounded',
    this.style = 'card',
    this.color,
    this.shortcuts = const [],
    this.label,
    this.text,
    this.date,
  });

  final String id;
  final String type;
  String size;
  String shape;
  String style;
  int? color;

  /// For a shortcuts widget: the apps it opens.
  List<Shortcut> shortcuts;

  /// For a countdown: what it counts down to, and when.
  String? label;
  DateTime? date;

  /// For a focus note: the words it shows.
  String? text;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'size': size,
    'shape': shape,
    'style': style,
    if (color != null) 'color': color,
    if (shortcuts.isNotEmpty) 'shortcuts': [for (final s in shortcuts) s.toJson()],
    if (label != null) 'label': label,
    if (text != null) 'text': text,
    if (date != null) 'date': DateFormat('yyyy-MM-dd').format(date!),
  };

  static DashItem fromJson(Map<String, dynamic> j) => DashItem(
    id: j['id'] as String,
    type: j['type'] as String,
    size: j['size'] as String? ?? 'l',
    shape: j['shape'] as String? ?? 'rounded',
    style: j['style'] as String? ?? 'card',
    color: j['color'] as int?,
    shortcuts: [
      for (final s in (j['shortcuts'] as List?) ?? const []) Shortcut.fromJson((s as Map).cast<String, dynamic>()),
    ],
    label: j['label'] as String?,
    text: j['text'] as String?,
    date: DateTime.tryParse(j['date'] as String? ?? ''),
  );
}

/// A kind of widget that can go on the home screen.
class DashKind {
  const DashKind(
    this.type,
    this.title,
    this.description,
    this.icon,
    this.color,
    this.sizes,
    this.size, {
    this.ownCard = false,
  });
  final String type;
  final String title;
  final String description;
  final IconData icon;
  final int color;
  final List<String> sizes;

  /// The size it starts at.
  final String size;

  /// Draws its own coloured card (weather), so style options do not apply.
  final bool ownCard;
}

/// Widget kinds this build offers.
final dashKinds = [
  for (final k in _allKinds)
    if (personalEdition || !personalOnlyWidgets.contains(k.type)) k,
];

const _allKinds = [
  DashKind('search', 'Search', 'Search notes, tasks, events and mail', Icons.search_rounded, 0xFF5F6B7A, [
    'm',
    'l',
  ], 'l'),
  DashKind(
    'weather',
    'Weather',
    'Now, today and rain in the next hours',
    Icons.wb_sunny_rounded,
    0xFF3A78C9,
    ['s', 'm', 'l'],
    'l',
    ownCard: true,
  ),
  DashKind('apps', 'Apps', 'Every Hub app', Icons.apps_rounded, 0xFF1F7A5A, ['m', 'l'], 'l'),
  DashKind('shortcuts', 'Shortcuts', 'Jump straight into X, Instagram, your bank…', Icons.bolt_rounded, 0xFFC0563F, [
    's',
    'm',
    'l',
  ], 'l'),
  DashKind(
    'quick',
    'Quick add',
    'New task, note, expense or event in one tap',
    Icons.add_circle_outline_rounded,
    0xFF1F7A5A,
    ['s', 'm', 'l'],
    'l',
  ),
  DashKind('today', 'Today', 'Events, tasks, deadlines and payments today', Icons.today_rounded, 0xFF3A78C9, [
    's',
    'm',
    'l',
  ], 'l'),
  DashKind('clock', 'Clock', 'Time and date', Icons.schedule_rounded, 0xFF5F6B7A, ['s', 'm'], 's'),
  DashKind('next', 'Next event', 'What is coming up next', Icons.event_rounded, 0xFF2D8C9E, ['s', 'm'], 's'),
  DashKind('tasks', 'Tasks', 'Open tasks, most urgent first', Icons.check_circle_outline_rounded, 0xFF1F7A5A, [
    's',
    'm',
    'l',
  ], 's'),
  DashKind('money', 'This month', 'Spent and earned this month', Icons.account_balance_wallet_outlined, 0xFF6650AE, [
    's',
    'm',
  ], 's'),
  DashKind('accounts', 'Bank cards', 'Balance on each card', Icons.credit_card_rounded, 0xFF00716B, [
    's',
    'm',
    'l',
  ], 'l'),
  DashKind(
    'habits',
    'Habits',
    'Tick off today\'s habits, see streaks',
    Icons.local_fire_department_outlined,
    0xFFD9822B,
    ['s', 'm', 'l'],
    'm',
  ),
  DashKind('shopping', 'Shopping', 'What to buy, and where', Icons.shopping_basket_outlined, 0xFF2F8F5B, [
    's',
    'm',
  ], 's'),
  DashKind('savings', 'Savings', 'Saved towards your goals', Icons.savings_outlined, 0xFF2F8F5B, ['s', 'm'], 's'),
  DashKind('investing', 'Investing', 'Portfolio value and gain', Icons.show_chart_rounded, 0xFF3A78C9, ['s', 'm'], 's'),
  DashKind('deadlines', 'Applications', 'Internship deadlines coming up', Icons.badge_outlined, 0xFFB5487A, [
    's',
    'm',
  ], 's'),
  DashKind('work', 'Work days', 'Days worked this month and holidays left', Icons.work_outline_rounded, 0xFF1F7A5A, [
    's',
    'm',
  ], 's'),
  DashKind('news', 'Headlines', 'The news that matters now', Icons.newspaper_rounded, 0xFF8A5A44, ['s', 'm', 'l'], 'l'),
  DashKind('notes', 'Notes', 'Your latest notes', Icons.sticky_note_2_outlined, 0xFFCF9418, ['s', 'm', 'l'], 'm'),
  DashKind(
    'month',
    'Month',
    'This month at a glance, with days that have plans',
    Icons.calendar_month_rounded,
    0xFF3A78C9,
    ['m', 'l'],
    'm',
  ),
  DashKind(
    'countdown',
    'Countdown',
    'Days left until a date you care about',
    Icons.hourglass_bottom_rounded,
    0xFFB5487A,
    ['s', 'm'],
    's',
  ),
  DashKind('focus', 'Focus', 'One line to keep in mind today', Icons.center_focus_strong_rounded, 0xFFD9822B, [
    's',
    'm',
    'l',
  ], 'm'),
];

DashKind kindOf(String type) => dashKinds.firstWhere((k) => k.type == type, orElse: () => dashKinds.first);

/// What a new install shows.
List<DashItem> defaultDashboard() => [
  for (final (i, (type, size)) in [
    ('search', 'l'),
    ('weather', 'l'),
    ('apps', 'l'),
    ('shortcuts', 'l'),
    ('today', 'l'),
    ('tasks', 's'),
    ('money', 's'),
    ('accounts', 'l'),
    ('news', 'l'),
    ('notes', 'm'),
  ].indexed)
    DashItem(
      id: 'd$i',
      type: type,
      size: size,
      shortcuts: type == 'shortcuts'
          ? [
              for (final s in shortcutCatalog)
                if (['X', 'Instagram', 'Reddit', 'Gmail'].contains(s.name)) s,
            ]
          : const [],
    ),
];

const _layoutKey = 'home.layout';

/// Home preferences kept in raw settings.
const homeGreetingKey = 'home.greeting';
const homeDensityKey = 'home.density';

List<DashItem> loadDashboard(AppSettings s) {
  final raw = s.raw(_layoutKey);
  if (raw == null) return defaultDashboard();
  try {
    return [for (final j in jsonDecode(raw) as List) DashItem.fromJson((j as Map).cast<String, dynamic>())]
        .where((i) => dashKinds.any((k) => k.type == i.type))
        .toList();
  } catch (_) {
    return defaultDashboard();
  }
}

Future<void> saveDashboard(AppSettings s, List<DashItem> items) =>
    s.setRaw(_layoutKey, jsonEncode([for (final i in items) i.toJson()]));

/// The home screen's widgets. Hold any of them (or tap Edit) to arrange; then tap one to restyle it, drag to move it.
class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.editing, required this.onEditing});
  final bool editing;
  final ValueChanged<bool> onEditing;

  @override
  State<Dashboard> createState() => DashboardState();
}

class DashboardState extends State<Dashboard> {
  late List<DashItem> _items = loadDashboard(context.settings);
  late String? _layout = context.settings.raw(_layoutKey);
  String? _dragging;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A layout changed somewhere else (sync, a restore) shows up without a restart.
    final raw = context.settings.raw(_layoutKey);
    if (raw != _layout && _dragging == null) {
      _layout = raw;
      _items = loadDashboard(context.settings);
    }
  }

  void _save() {
    if (!mounted) return;
    setState(() {});
    _layout = jsonEncode([for (final i in _items) i.toJson()]);
    context.settings.setRaw(_layoutKey, _layout!);
  }

  /// Moves the dragged widget to where the finger is, right away, so the rest reflow around it.
  bool _moveLive(String id, String targetId) {
    if (id == targetId) return false;
    final from = _items.indexWhere((i) => i.id == id);
    final to = _items.indexWhere((i) => i.id == targetId);
    if (from < 0 || to < 0) return false;
    setState(() => _items.insert(to, _items.removeAt(from)));
    HapticFeedback.selectionClick();
    return true;
  }

  void _moveToEnd(String id) {
    final from = _items.indexWhere((i) => i.id == id);
    if (from < 0 || from == _items.length - 1) return;
    _items.add(_items.removeAt(from));
    HapticFeedback.selectionClick();
    _save();
  }

  void _remove(DashItem item) {
    final at = _items.indexOf(item);
    if (at < 0) return;
    HapticFeedback.lightImpact();
    _items.removeAt(at);
    _save();
    showUndo(context, '${kindOf(item.type).title} removed', () {
      if (!mounted || _items.contains(item)) return;
      _items.insert(at.clamp(0, _items.length), item);
      _save();
    });
  }

  /// Scrolls the page while a widget is dragged near the top or bottom edge.
  void _autoScroll(DragUpdateDetails d) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    final h = MediaQuery.sizeOf(context).height;
    const edge = 80.0;
    final y = d.globalPosition.dy;
    final step = y < edge ? -(edge - y) / 4 : (y > h - edge ? (y - (h - edge)) / 4 : 0.0);
    if (step == 0) return;
    position.jumpTo((position.pixels + step).clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  Future<void> addWidget() async {
    final kind = await showModalBottomSheet<DashKind>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _Gallery(),
    );
    if (kind == null || !mounted) return;
    final item = DashItem(id: 'w${DateTime.now().microsecondsSinceEpoch}', type: kind.type, size: kind.size);
    if (kind.type == 'shortcuts') {
      final picked = await pickShortcuts(context, const []);
      if (picked == null || picked.isEmpty) return;
      item.shortcuts = picked;
    }
    if (!mounted) return;
    if (kind.type == 'countdown' && !await editCountdown(context, item)) return;
    if (!mounted) return;
    if (kind.type == 'focus' && !await editFocus(context, item)) return;
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _items.add(item);
    _save();
  }

  void resetLayout() {
    _items = defaultDashboard();
    _save();
  }

  Future<void> _customise(DashItem item) async {
    if (!widget.editing) widget.onEditing(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void change(VoidCallback f) {
            f();
            setSheet(() {});
            _save();
          }

          final kind = kindOf(item.type);
          final index = _items.indexOf(item);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AppGlyph(icon: kind.icon, color: Color(kind.color), size: 36),
                      const SizedBox(width: 12),
                      Expanded(child: Text(kind.title, style: Theme.of(context).textTheme.titleLarge)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _Label('Size'),
                  PillToggle<String>(
                    options: [for (final s in kind.sizes) (s, dashSizeLabels[s]!)],
                    value: kind.sizes.contains(item.size) ? item.size : kind.size,
                    onChanged: (v) => change(() => item.size = v),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Shape'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in dashShapes.entries)
                        ChoiceChip(
                          showCheckmark: false,
                          avatar: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              border: Border.all(
                                // The chosen chip is filled with ink, so its outline flips to stay visible.
                                color: item.shape == e.key ? Palette.of(context).background : Palette.of(context).ink,
                                width: 1.6,
                              ),
                              borderRadius: BorderRadius.circular(e.value / 3),
                            ),
                          ),
                          label: Text(dashShapeLabels[e.key]!),
                          selected: item.shape == e.key,
                          onSelected: (_) => change(() => item.shape = e.key),
                        ),
                    ],
                  ),
                  if (!kind.ownCard) ...[
                    const SizedBox(height: 16),
                    const _Label('Style'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in dashStyles)
                          ChoiceChip(
                            showCheckmark: false,
                            label: Text(dashStyleLabels[s]!),
                            selected: item.style == s,
                            onSelected: (_) => change(() => item.style = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _Label('Colour'),
                    ColorDots(
                      colors: [for (final c in dashColors) Color(c)],
                      selected: dashColors.indexOf(item.color ?? kind.color),
                      onSelected: (i) => change(() => item.color = dashColors[i]),
                    ),
                  ],
                  if (item.type == 'countdown') ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (await editCountdown(context, item)) change(() {});
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: const Text('Change name and date'),
                    ),
                  ],
                  if (item.type == 'focus') ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (await editFocus(context, item)) change(() {});
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Change the words'),
                    ),
                  ],
                  if (item.type == 'apps') ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => pickVisibleApps(context),
                      icon: const Icon(Icons.apps_rounded, size: 18),
                      label: const Text('Choose apps'),
                    ),
                  ],
                  if (item.type == 'shortcuts') ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pickShortcuts(context, item.shortcuts);
                        if (picked != null) change(() => item.shortcuts = picked);
                      },
                      icon: const Icon(Icons.apps_rounded, size: 18),
                      label: const Text('Choose apps'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _Label('Position'),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: index <= 0 ? null : () => change(() => _items.insert(0, _items.removeAt(index))),
                          icon: const Icon(Icons.vertical_align_top_rounded, size: 18),
                          label: const Text('Top'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Move up',
                        onPressed: index <= 0
                            ? null
                            : () => change(() => _items.insert(index - 1, _items.removeAt(index))),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Move down',
                        onPressed: index >= _items.length - 1
                            ? null
                            : () => change(() => _items.insert(index + 1, _items.removeAt(index))),
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Palette.of(context).danger),
                        onPressed: () {
                          Navigator.pop(context);
                          _remove(item);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Remove'),
                      ),
                      const Spacer(),
                      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingSelector<bool>(
      select: (s) => s.raw(homeDensityKey) == 'compact',
      builder: (context, compact) => LayoutBuilder(
        builder: (context, c) {
          final gap = compact ? 8.0 : 12.0;
          final wide = c.maxWidth >= 600;
          final cols = wide ? 6 : 2;
          final unit = (c.maxWidth - gap * (cols - 1)) / cols;
          double widthOf(String size) {
            final span = switch (size) {
              's' => wide ? 2 : 1,
              'm' => wide ? 3 : 2,
              _ => cols,
            };
            return unit * span + gap * (span - 1);
          }

          return Wrap(
            spacing: gap,
            runSpacing: widget.editing ? gap + 4 : gap,
            children: [
              for (final item in _items)
                SizedBox(
                  key: ValueKey(item.id),
                  width: widthOf(_sizeOf(item)),
                  child: _slot(item, widthOf(_sizeOf(item)), compact ? 150 : 164),
                ),
              if (widget.editing)
                SizedBox(
                  width: c.maxWidth,
                  child: DragTarget<String>(
                    onAcceptWithDetails: (d) => _moveToEnd(d.data),
                    builder: (context, hover, _) => _AddButton(onTap: addWidget, highlight: hover.isNotEmpty),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _sizeOf(DashItem item) {
    final kind = kindOf(item.type);
    return kind.sizes.contains(item.size) ? item.size : kind.size;
  }

  Widget _slot(DashItem item, double width, double smallHeight) {
    final kind = kindOf(item.type);
    final size = _sizeOf(item);
    Widget body = DashFrame(
      item: item,
      kind: kind,
      child: _DashBody(item: item, size: size),
    );
    if (size == 's') body = SizedBox(height: smallHeight, child: body);
    if (!widget.editing) {
      // Like an Android home screen: hold any widget to start arranging.
      return GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onEditing(true);
        },
        child: body,
      );
    }
    final p = Palette.of(context);
    final dragging = _dragging == item.id;
    // Controls sit in a bar above the widget, never on top of its content.
    final bar = SizedBox(
      height: 34,
      child: Row(
        children: [
          Icon(Icons.drag_indicator_rounded, size: 18, color: p.muted),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              kind.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted),
            ),
          ),
          _Badge(icon: Icons.tune_rounded, tooltip: 'Customise', onTap: () => _customise(item)),
          const SizedBox(width: 6),
          _Badge(icon: Icons.close_rounded, tooltip: 'Remove', onTap: () => _remove(item)),
        ],
      ),
    );
    final editingBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        GestureDetector(
          onTap: () => _customise(item),
          child: AnimatedScale(
            // A slight shrink tells you the widgets can be moved.
            scale: 0.97,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(child: body),
          ),
        ),
      ],
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        if (d.data == item.id) return false;
        _moveLive(d.data, item.id);
        return true;
      },
      onAcceptWithDetails: (_) => _save(),
      builder: (context, hover, _) => LongPressDraggable<String>(
        data: item.id,
        delay: const Duration(milliseconds: 180),
        hapticFeedbackOnStart: true,
        onDragStarted: () => setState(() => _dragging = item.id),
        onDragUpdate: _autoScroll,
        onDragEnd: (_) {
          _dragging = null;
          _save();
        },
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1.03,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(dashShapes[item.shape] ?? 22),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: IgnorePointer(child: body),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: IgnorePointer(child: editingBody)),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: dragging ? 0.25 : 1,
          child: editingBody,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: SectionLabel(text));
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 17, color: p.ink),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.highlight});
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: highlight ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: p.accent),
                const SizedBox(width: 8),
                Text(
                  highlight ? 'Drop to move it to the end' : 'Add a widget',
                  style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks a widget to add, with a live preview of each.
class _Gallery extends StatelessWidget {
  const _Gallery();

  static DashItem _sample(DashKind k) => DashItem(
    id: 'preview-${k.type}',
    type: k.type,
    size: k.size,
    label: k.type == 'countdown' ? 'Holidays' : null,
    date: k.type == 'countdown' ? addDays(dateOnly(DateTime.now()), 24) : null,
    text: k.type == 'focus' ? 'Finish the report before lunch' : null,
    shortcuts: k.type == 'shortcuts'
        ? [
            for (final s in shortcutCatalog)
              if (['X', 'Instagram', 'Reddit', 'Gmail'].contains(s.name)) s,
          ]
        : const [],
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Add a widget', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Tap one to put it at the end of Home.', style: TextStyle(color: p.muted)),
            ),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 640 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 236,
                    ),
                    itemCount: dashKinds.length,
                    itemBuilder: (context, i) => _GalleryTile(kind: dashKinds[i], item: _sample(dashKinds[i])),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.kind, required this.item});
  final DashKind kind;
  final DashItem item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // The preview is drawn at phone width, then scaled down to fit.
    final previewWidth = item.size == 's' ? 180.0 : 360.0;
    Widget preview = DashFrame(
      item: item,
      kind: kind,
      child: _DashBody(item: item, size: item.size),
    );
    if (item.size == 's') preview = SizedBox(height: 164, child: preview);
    return Material(
      color: p.raised,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, kind),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: ClipRect(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(width: previewWidth, child: preview),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  AppGlyph(icon: kind.icon, color: Color(kind.color), size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kind.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          kind.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.add_circle_rounded, color: p.accent, size: 26),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Applies the item's shape, style and colour to whatever it draws.
class DashFrame extends StatelessWidget {
  const DashFrame({super.key, required this.item, required this.kind, required this.child});
  final DashItem item;
  final DashKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = Palette.of(context);
    final radius = dashShapes[item.shape] ?? 22;
    final accent = Color(item.color ?? kind.color);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: switch (item.style) {
        'outline' => BorderSide(color: accent.withValues(alpha: 0.6), width: 1.5),
        _ => BorderSide.none,
      },
    );
    final color = switch (item.style) {
      'tinted' => Color.alphaBlend(
        accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12),
        p.surface,
      ),
      'outline' || 'plain' => Colors.transparent,
      _ => p.surface,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Theme(
        data: theme.copyWith(
          cardTheme: theme.cardTheme.copyWith(shape: shape, color: color),
        ),
        child: DashAccent(color: accent, child: child),
      ),
    );
  }
}

/// The colour a widget was given, for its icons and highlights.
class DashAccent extends InheritedWidget {
  const DashAccent({super.key, required this.color, required super.child});
  final Color color;

  static Color of(BuildContext context, Color fallback) =>
      context.dependOnInheritedWidgetOfExactType<DashAccent>()?.color ?? fallback;

  @override
  bool updateShouldNotify(DashAccent old) => old.color != color;
}

class _DashBody extends StatelessWidget {
  const _DashBody({required this.item, required this.size});
  final DashItem item;
  final String size;

  @override
  Widget build(BuildContext context) {
    final small = size == 's';
    return switch (item.type) {
      'search' => const _SearchBar(),
      'weather' => WeatherGlance(compact: small),
      'apps' => const AppGrid(),
      'shortcuts' => _ShortcutsWidget(item: item, size: size),
      'quick' => _QuickAdd(small: small),
      'today' => small ? const _TodaySmall() : const TodayCard(),
      'clock' => _Clock(small: small),
      'next' => _NextEvent(small: small),
      'tasks' => _Tasks(size: size),
      'money' => _Money(small: small),
      'accounts' => small ? const _AccountsSmall() : _AccountsWide(),
      'shopping' => _Shopping(small: small),
      'habits' => _HabitsWidget(size: size),
      'savings' => _Savings(small: small),
      'investing' => _Investing(small: small),
      'deadlines' => _Deadlines(small: small),
      'work' => _Work(small: small),
      'news' => small ? const _NewsSmall() : const HeadlinesCard(),
      'notes' => small ? const _NoteSmall() : const RecentNotesCard(),
      'month' => _MonthView(large: size == 'l'),
      'countdown' => _Countdown(item: item, small: small),
      'focus' => _Focus(item: item, size: size),
      _ => const SizedBox.shrink(),
    };
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

/// The common look of a small widget: an icon and label on top, a big value, a line under it.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.color,
    this.onTap,
    this.extra,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = DashAccent.of(context, color ?? p.accent);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.15),
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 13, height: 1.3),
                ),
              if (extra != null) ...[const SizedBox(height: 6), extra!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A wider widget: section title, then rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.onMore, this.moreLabel = 'Open'});
  final String title;
  final List<Widget> children;
  final VoidCallback? onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) => Section(
    title: title,
    trailing: onMore == null ? null : TextButton(onPressed: onMore, child: Text(moreLabel)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
    child: Text(text, style: TextStyle(color: Palette.of(context).muted)),
  );
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Card(
      color: p.raised,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _push(context, const SearchPage()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Search everything', style: TextStyle(color: p.muted)),
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
    );
  }
}

class _ShortcutsWidget extends StatelessWidget {
  const _ShortcutsWidget({required this.item, required this.size});
  final DashItem item;
  final String size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final list = item.shortcuts;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: size == 's' ? 10 : 14, horizontal: 6),
        child: list.isEmpty
            ? Center(
                child: Text('Hold to choose apps', style: TextStyle(color: p.muted)),
              )
            : LayoutBuilder(
                builder: (context, c) {
                  final perRow = size == 's' ? 2 : (c.maxWidth >= 640 ? 6 : 4);
                  final w = c.maxWidth / perRow;
                  final shown = size == 's' ? list.take(4) : list;
                  return Wrap(
                    runSpacing: size == 's' ? 4 : 12,
                    children: [
                      for (final s in shown)
                        SizedBox(
                          width: w,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => openShortcut(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  ShortcutGlyph(shortcut: s, size: size == 's' ? 44 : 50),
                                  if (size != 's') ...[
                                    const SizedBox(height: 7),
                                    Text(
                                      s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ],
                              ),
                            ),
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

class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.check_circle_outline_rounded, 'Task', TileColors.todo, () => _push(context, const TodoPage())),
      (Icons.sticky_note_2_outlined, 'Note', TileColors.notes, () => openNote(context)),
      (Icons.receipt_long_outlined, 'Expense', TileColors.finance, () => editEntry(context)),
      (Icons.event_outlined, 'Event', TileColors.weather, () => openEventEditor(context)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, c) {
            final perRow = small ? 2 : 4;
            final w = c.maxWidth / perRow;
            return Wrap(
              runSpacing: 6,
              children: [
                for (final (icon, label, color, onTap) in actions)
                  SizedBox(
                    width: w,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Container(
                              width: small ? 40 : 46,
                              height: small ? 40 : 46,
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
                              child: Icon(icon, color: color),
                            ),
                            const SizedBox(height: 5),
                            Text('+ $label', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
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

class _Clock extends StatefulWidget {
  const _Clock({required this.small});
  final bool small;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // ISO week: the week that holds this week's Thursday.
    final thursday = addDays(dateOnly(_now), DateTime.thursday - _now.weekday);
    final week = daysBetween(DateTime(thursday.year), thursday) ~/ 7 + 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE').format(_now),
              style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
            ),
            if (widget.small) const Spacer() else const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat.Hm().format(_now),
                style: TextStyle(
                  fontSize: widget.small ? 44 : 56,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${DateFormat(widget.small ? 'd MMM' : 'd MMMM').format(_now)} · week $week',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextEvent extends StatelessWidget {
  const _NextEvent({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final now = DateTime.now();
    final until = addDays(dateOnly(now), 30);
    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, cSnap) {
        final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
        return StreamBuilder<List<Event>>(
          stream: db.watchEventsBetween(dateOnly(now), until),
          builder: (context, snap) {
            final list =
                expand(snap.data ?? const [], cals, dateOnly(now), until)
                    .where(
                      (o) => o.allDay
                          ? !dateOnly(o.end).isBefore(addDays(dateOnly(now), 1)) || o.touches(now)
                          : o.end.isAfter(now),
                    )
                    .toList()
                  ..sort((a, b) => a.start.compareTo(b.start));
            final o = list.firstOrNull;
            String when(Occurrence o) => o.allDay
                ? friendlyDay(o.start)
                : (o.start.isBefore(now)
                      ? 'Now, until ${DateFormat.Hm().format(o.end)}'
                      : '${friendlyDay(o.start)}, ${DateFormat.Hm().format(o.start)}');
            if (small) {
              return StatTile(
                icon: Icons.event_rounded,
                label: 'Next',
                color: o?.color ?? TileColors.weather,
                value: o == null ? 'Free' : o.event.title,
                caption: o == null ? 'Nothing in the next 30 days' : when(o),
                onTap: () => o == null ? _push(context, const CalendarPage()) : showEventDetails(context, o),
              );
            }
            return _Panel(
              title: 'Coming up',
              onMore: () => _push(context, const CalendarPage()),
              moreLabel: 'Calendar',
              children: [
                if (list.isEmpty) const _Muted('Nothing in the next 30 days.'),
                for (final o in list.take(4))
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 5, backgroundColor: o.color),
                    title: Text(o.event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(when(o)),
                    onTap: () => showEventDetails(context, o),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Tasks extends StatelessWidget {
  const _Tasks({required this.size});
  final String size;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Todo>>(
      stream: context.db.watchTodos(),
      builder: (context, snap) {
        final now = DateTime.now();
        final open = (snap.data ?? const <Todo>[]).where((t) => !t.done).toList()
          ..sort((a, b) {
            if (a.important != b.important) return a.important ? -1 : 1;
            final x = a.due ?? a.remindAt, y = b.due ?? b.remindAt;
            if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
            return x.compareTo(y);
          });
        final today = open.where((t) => isTodayTask(t, now: now)).length;
        if (size == 's') {
          return StatTile(
            icon: Icons.check_circle_outline_rounded,
            label: 'Tasks',
            color: TileColors.todo,
            value: '${open.length} open',
            caption: open.isEmpty ? 'All done' : (today > 0 ? '$today today · ${open.first.title}' : open.first.title),
            onTap: () => _push(context, const TodoPage()),
          );
        }
        final max = size == 'm' ? 4 : 8;
        return _Panel(
          title: 'Tasks · ${open.length} open',
          onMore: () => _push(context, const TodoPage()),
          moreLabel: 'All',
          children: [
            if (open.isEmpty) const _Muted('Nothing open. Nice.'),
            for (final t in open.take(max)) TodoTile(todo: t, dense: true),
          ],
        );
      },
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final currency = context.settings.currency;
    return StreamBuilder<List<Entry>>(
      stream: context.db.watchEntries(month, DateTime(now.year, now.month + 1)),
      builder: (context, snap) {
        final s = MonthSummary(snap.data ?? const <Entry>[]);
        if (small) {
          return StatTile(
            icon: Icons.account_balance_wallet_outlined,
            label: DateFormat('MMMM').format(now),
            color: TileColors.finance,
            value: money(s.out, currency),
            caption: 'spent · ${money(s.income - s.out, currency, signed: true)} net',
            onTap: () => _push(context, const WalletPage()),
          );
        }
        final p = Palette.of(context);
        return _Panel(
          title: 'This month',
          onMore: () => _push(context, const WalletPage()),
          moreLabel: 'Wallet',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  for (final (label, value, color) in [
                    ('In', s.income, p.positive),
                    ('Out', s.out, p.ink),
                    ('Net', s.income - s.out, s.income >= s.out ? p.positive : p.danger),
                  ])
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              money(value, currency, signed: label == 'Net'),
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color),
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
      },
    );
  }
}

/// Total over all cards.
class _AccountsSmall extends StatelessWidget {
  const _AccountsSmall();

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final currency = context.settings.currency;
    return StreamBuilder<List<Account>>(
      stream: db.watchAccounts(),
      builder: (context, aSnap) => StreamBuilder<List<Entry>>(
        stream: db.watchEntries(DateTime(2000), DateTime(2100)),
        builder: (context, eSnap) {
          final accounts = aSnap.data ?? const <Account>[];
          final entries = eSnap.data ?? const <Entry>[];
          final states = [
            for (final a in accounts)
              AccountState(
                a,
                entries.where((e) => e.account.trim().toLowerCase() == a.name.trim().toLowerCase()).toList(),
                const [],
              ),
          ];
          final set = states.where((s) => s.hasBalance).toList();
          return StatTile(
            icon: Icons.credit_card_rounded,
            label: 'All cards',
            color: const Color(0xFF00716B),
            value: set.isEmpty ? 'Set balances' : money(set.fold(0, (t, s) => t + s.balance), currency),
            caption: set.map((s) => '${s.account.name} ${money(s.balance, currency)}').join(' · '),
            onTap: () => _push(context, const WalletPage()),
          );
        },
      ),
    );
  }
}

class _AccountsWide extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      child: AccountsStrip(currency: context.settings.currency),
    ),
  );
}

class _Savings extends StatelessWidget {
  const _Savings({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final currency = context.settings.currency;
    return StreamBuilder<List<SavingsGoal>>(
      stream: db.watchGoals(),
      builder: (context, gSnap) => StreamBuilder<List<SavingsMove>>(
        stream: db.watchMoves(),
        builder: (context, mSnap) {
          final goals = (gSnap.data ?? const <SavingsGoal>[]).where((g) => !g.archived).toList();
          final moves = mSnap.data ?? const <SavingsMove>[];
          int saved(SavingsGoal g) => moves.where((m) => m.goalId == g.id).fold(0, (t, m) => t + m.amountCents);
          final total = goals.fold(0, (t, g) => t + saved(g));
          final target = goals.fold(0, (t, g) => t + g.targetCents);
          final bar = LinearProgressIndicator(
            value: target == 0 ? 0 : (total / target).clamp(0, 1).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: DashAccent.of(context, const Color(0xFF2F8F5B)),
          );
          if (small) {
            return StatTile(
              icon: Icons.savings_outlined,
              label: 'Savings',
              color: const Color(0xFF2F8F5B),
              value: money(total, currency),
              caption: goals.isEmpty ? 'No goals yet' : 'of ${money(target, currency)}',
              extra: goals.isEmpty ? null : bar,
              onTap: () => _push(context, const WalletPage(initialTab: 1)),
            );
          }
          return _Panel(
            title: 'Savings · ${money(total, currency)}',
            onMore: () => _push(context, const WalletPage(initialTab: 1)),
            children: [
              if (goals.isEmpty) const _Muted('Make a goal in Wallet → Savings.'),
              for (final g in goals.take(4))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          Text(
                            '${money(saved(g), currency)} / ${money(g.targetCents, currency)}',
                            style: TextStyle(color: Palette.of(context).muted, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: g.targetCents == 0 ? 0 : (saved(g) / g.targetCents).clamp(0, 1).toDouble(),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: Color(g.color),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Investing extends StatelessWidget {
  const _Investing({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final currency = context.settings.currency;
    final p = Palette.of(context);
    return StreamBuilder<List<Holding>>(
      stream: context.db.watchHoldings(),
      builder: (context, snap) {
        final list = snap.data ?? const <Holding>[];
        final value = list.fold<int>(0, (t, h) => t + holdingValueCents(h));
        final invested = list.fold<int>(0, (t, h) => t + h.investedCents);
        final gain = value - invested;
        final pct = invested == 0 ? 0 : gain / invested * 100;
        final gainText = '${money(gain, currency, signed: true)} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)';
        if (small) {
          return StatTile(
            icon: Icons.show_chart_rounded,
            label: 'Investing',
            color: TileColors.weather,
            value: money(value, currency),
            caption: list.isEmpty ? 'No holdings yet' : gainText,
            onTap: () => _push(context, const WalletPage(initialTab: 2)),
          );
        }
        return _Panel(
          title: 'Investing · ${money(value, currency)}',
          onMore: () => _push(context, const WalletPage(initialTab: 2)),
          children: [
            if (list.isEmpty) const _Muted('Add holdings in Wallet → Investing.'),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  gainText,
                  style: TextStyle(fontWeight: FontWeight.w600, color: gain >= 0 ? p.positive : p.danger),
                ),
              ),
            for (final h in (list.toList()..sort((a, b) => holdingValueCents(b).compareTo(holdingValueCents(a)))).take(
              4,
            ))
              ListTile(
                dense: true,
                title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: h.symbol.isEmpty ? null : Text(h.symbol),
                trailing: Text(
                  money(holdingValueCents(h), currency),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Deadlines extends StatelessWidget {
  const _Deadlines({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Application>>(
      stream: context.db.watchApplications(),
      builder: (context, snap) {
        final today = dateOnly(DateTime.now());
        final todo =
            (snap.data ?? const <Application>[])
                .where((a) => (a.status == 'wishlist' || a.status == 'preparing'))
                .toList()
              ..sort((a, b) => (a.deadline ?? DateTime(2100)).compareTo(b.deadline ?? DateTime(2100)));
        final next = todo.where((a) => a.deadline != null && !a.deadline!.isBefore(today)).firstOrNull;
        if (small) {
          return StatTile(
            icon: Icons.badge_outlined,
            label: 'To apply',
            color: internshipColor,
            value: '${todo.length}',
            caption: next == null
                ? (todo.isEmpty ? 'Nothing waiting' : 'No deadlines set')
                : '${next.company} · ${friendlyDay(next.deadline!).toLowerCase()}',
            onTap: () => _push(context, const InternshipsPage()),
          );
        }
        return _Panel(
          title: 'To apply · ${todo.length}',
          onMore: () => _push(context, const InternshipsPage()),
          children: [
            if (todo.isEmpty) const _Muted('Nothing waiting. Add places in Internships.'),
            for (final a in todo.take(4))
              ListTile(
                dense: true,
                title: Text(a.company, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.role, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: a.deadline == null
                    ? null
                    : Text(
                        '${daysBetween(today, a.deadline!)} d',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: daysBetween(today, a.deadline!) <= 3 ? Palette.of(context).danger : null,
                        ),
                      ),
                onTap: () => editApplication(context, application: a),
              ),
          ],
        );
      },
    );
  }
}

class _Work extends StatelessWidget {
  const _Work({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final allowance = int.tryParse(context.settings.raw('job.holidayAllowance') ?? '') ?? 25;
    return StreamBuilder<List<WorkDay>>(
      stream: context.db.watchWorkDays(DateTime(now.year), DateTime(now.year + 1)),
      builder: (context, snap) {
        final all = snap.data ?? const <WorkDay>[];
        final key = AppDatabase.dayKey(now).substring(0, 7);
        final month = WorkTotals(all.where((d) => d.day.startsWith(key)));
        final year = WorkTotals(all);
        final left = allowance - year.of('holiday');
        void open() => _push(context, const SpaceLauncher(gid: 'seed-job', fallbackName: 'Job'));
        if (small) {
          return StatTile(
            icon: Icons.work_outline_rounded,
            label: 'Worked in ${DateFormat('MMMM').format(now)}',
            color: TileColors.todo,
            value: '${month.worked} days',
            caption: '$left holidays left this year',
            onTap: open,
          );
        }
        final p = Palette.of(context);
        return _Panel(
          title: 'Work',
          onMore: open,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  for (final (label, value) in [
                    ('Worked', '${month.worked}'),
                    ('Off', '${month.of('off')}'),
                    ('Sick', '${month.of('sick')}'),
                    ('Holidays left', '$left'),
                  ])
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TodaySmall extends StatelessWidget {
  const _TodaySmall();

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = addDays(today, 1);
    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, cSnap) {
        final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
        return StreamBuilder<List<Event>>(
          stream: db.watchEventsBetween(today, tomorrow),
          builder: (context, eSnap) => StreamBuilder<List<Todo>>(
            stream: db.watchTodos(),
            builder: (context, tSnap) {
              final events = expand(eSnap.data ?? const [], cals, today, tomorrow);
              final left = events.where((o) => o.allDay || o.end.isAfter(now)).toList();
              final todos = (tSnap.data ?? const <Todo>[]).where((t) => isTodayTask(t, now: now)).length;
              final next = left.where((o) => !o.allDay).firstOrNull ?? left.firstOrNull;
              return StatTile(
                icon: Icons.today_rounded,
                label: 'Today',
                color: TileColors.weather,
                value: left.isEmpty && todos == 0 ? 'Free' : '${left.length} · $todos',
                caption: left.isEmpty && todos == 0
                    ? 'Nothing left today'
                    : '${left.length == 1 ? '1 event' : '${left.length} events'}, $todos ${todos == 1 ? 'task' : 'tasks'}'
                          '${next == null ? '' : ' · ${next.allDay ? '' : '${DateFormat.Hm().format(next.start)} '}${next.event.title}'}',
                onTap: () => _push(context, const CalendarPage()),
              );
            },
          ),
        );
      },
    );
  }
}

class _NewsSmall extends StatefulWidget {
  const _NewsSmall();

  @override
  State<_NewsSmall> createState() => _NewsSmallState();
}

class _NewsSmallState extends State<_NewsSmall> {
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final news = NewsService.instance..loadCache(context.settings);
    if (news.stale && !_failed) {
      news
          .refresh(context.settings)
          // An offline refresh finishes without news rather than throwing.
          .then((_) {
            if (mounted) setState(() => _failed = news.briefing(perTopic: 1, max: 1).isEmpty);
          })
          .catchError((_) {
            if (mounted) setState(() => _failed = true);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final top = NewsService.instance.briefing(perTopic: 1, max: 1).firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => top == null ? _push(context, const NewsPage()) : openArticle(top.link),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.newspaper_rounded, size: 18, color: DashAccent.of(context, newsColor)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      top == null ? 'Headlines' : top.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  top?.title ?? (_failed ? 'Could not load the news' : 'Loading the news…'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteSmall extends StatelessWidget {
  const _NoteSmall();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<Note>>(
      stream: context.db.watchNotes(),
      builder: (context, snap) {
        final n = (snap.data ?? const <Note>[]).firstOrNull;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openNote(context, note: n),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined, size: 18, color: DashAccent.of(context, TileColors.notes)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          n == null ? 'Notes' : relativeTime(n.updatedAt),
                          style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    n == null ? 'Tap to write' : (n.title.trim().isEmpty ? 'Untitled' : n.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (n != null)
                    Expanded(
                      child: Text(
                        n.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Shopping extends StatelessWidget {
  const _Shopping({required this.small});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShoppingItem>>(
      stream: context.db.watchShopping(),
      builder: (context, snap) {
        final open = (snap.data ?? const <ShoppingItem>[]).where((i) => !i.done).toList();
        final byStore = <String, int>{};
        for (final i in open) {
          byStore[i.store.isEmpty ? 'Anywhere' : i.store] = (byStore[i.store.isEmpty ? 'Anywhere' : i.store] ?? 0) + 1;
        }
        final shops = byStore.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        if (small) {
          return StatTile(
            icon: Icons.shopping_basket_outlined,
            label: 'Shopping',
            color: shoppingColor,
            value: open.isEmpty ? 'All set' : '${open.length} to buy',
            caption: shops.map((e) => '${e.key} ${e.value}').join(' · '),
            onTap: () => _push(context, const ShoppingPage()),
          );
        }
        return _Panel(
          title: 'Shopping · ${open.length}',
          onMore: () => _push(context, const ShoppingPage()),
          children: [
            if (open.isEmpty) const _Muted('Nothing to buy.'),
            for (final e in shops.take(4))
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 6, backgroundColor: storeColor(e.key)),
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  open.where((i) => (i.store.isEmpty ? 'Anywhere' : i.store) == e.key).map((i) => i.name).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${e.value}'),
              ),
          ],
        );
      },
    );
  }
}

class _HabitsWidget extends StatelessWidget {
  const _HabitsWidget({required this.size});
  final String size;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final today = dateOnly(DateTime.now());
    return StreamBuilder<List<Habit>>(
      stream: db.watchHabits(),
      builder: (context, hSnap) => StreamBuilder<List<HabitCheck>>(
        stream: db.watchHabitChecks(addDays(today, -400)),
        builder: (context, cSnap) {
          final habits = hSnap.data ?? const <Habit>[];
          final byHabit = <int, Set<String>>{};
          for (final c in cSnap.data ?? const <HabitCheck>[]) {
            (byHabit[c.habitId] ??= {}).add(c.day);
          }
          final due = habits.where((h) => habitDueOn(h, today)).toList();
          final key = AppDatabase.dayKey(today);
          final doneCount = due.where((h) => byHabit[h.id]?.contains(key) ?? false).length;
          if (size == 's') {
            final best = habits.isEmpty
                ? 0
                : habits.map((h) => habitStreak(h, byHabit[h.id] ?? const {})).reduce((a, b) => a > b ? a : b);
            return StatTile(
              icon: Icons.local_fire_department_outlined,
              label: 'Habits',
              color: habitColor,
              value: habits.isEmpty ? 'Start one' : '$doneCount/${due.length}',
              caption: habits.isEmpty ? 'Read, gym, water…' : 'done today · best streak $best',
              onTap: () => _push(context, const HabitsPage()),
            );
          }
          return _Panel(
            title: 'Habits · $doneCount/${due.length} today',
            onMore: () => _push(context, const HabitsPage()),
            children: [
              if (habits.isEmpty) const _Muted('Add a habit to track it here.'),
              for (final h in (size == 'm' ? due.take(4) : due))
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: HabitCard(habit: h, done: byHabit[h.id] ?? const {}, compact: size == 'm'),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Asks what a countdown counts down to. Returns false if the person backs out.
Future<bool> editCountdown(BuildContext context, DashItem item) async {
  final name = TextEditingController(text: item.label ?? '');
  var date = item.date ?? addDays(dateOnly(DateTime.now()), 7);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) => AlertDialog(
        title: const Text('Count down to'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Name, e.g. Holidays'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormat('EEE d MMMM y').format(date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: d,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setD(() => date = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  item.label = name.text.trim().isEmpty ? null : name.text.trim();
  item.date = date;
  return true;
}

/// Asks for the words a focus widget shows. Returns false if the person backs out.
Future<bool> editFocus(BuildContext context, DashItem item) async {
  final c = TextEditingController(text: item.text ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Your focus'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        maxLength: 140,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'What matters most today?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return false;
  item.text = c.text.trim();
  return true;
}

/// Saves a change made to one widget from inside it (a countdown date, focus words).
void _saveItem(BuildContext context, DashItem item) => context.findAncestorStateOfType<DashboardState>()?._save();

class _Countdown extends StatelessWidget {
  const _Countdown({required this.item, required this.small});
  final DashItem item;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final date = item.date;
    final days = date == null ? null : daysBetween(dateOnly(DateTime.now()), date);
    final value = switch (days) {
      null => 'Pick a date',
      0 => 'Today',
      1 => '1 day',
      -1 => '1 day ago',
      final d when d < 0 => '${-d} days ago',
      final d => '$d days',
    };
    final caption = date == null ? 'Tap to choose what to count down to' : DateFormat('EEE d MMMM y').format(date);
    Future<void> edit() async {
      if (await editCountdown(context, item) && context.mounted) _saveItem(context, item);
    }

    if (small) {
      return StatTile(
        icon: Icons.hourglass_bottom_rounded,
        label: item.label ?? 'Countdown',
        color: Color(kindOf('countdown').color),
        value: value,
        caption: caption,
        onTap: edit,
      );
    }
    final c = DashAccent.of(context, p.accent);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: edit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(Icons.hourglass_bottom_rounded, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label ?? 'Countdown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BigAmount(value, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _Focus extends StatelessWidget {
  const _Focus({required this.item, required this.size});
  final DashItem item;
  final String size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = DashAccent.of(context, p.accent);
    final text = (item.text ?? '').trim();
    final small = size == 's';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (await editFocus(context, item) && context.mounted) _saveItem(context, item);
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, small ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.center_focus_strong_rounded, size: 18, color: c),
                  const SizedBox(width: 6),
                  Text(
                    'Focus',
                    style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ],
              ),
              SizedBox(height: small ? 8 : 10),
              Flexible(
                child: Text(
                  text.isEmpty ? 'Tap to write what matters today' : text,
                  maxLines: small ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: small ? 17 : (size == 'l' ? 24 : 20),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: text.isEmpty ? p.muted : null,
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

/// A small month calendar; days with plans get a dot in the calendar's colour.
class _MonthView extends StatelessWidget {
  const _MonthView({required this.large});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    final now = DateTime.now();
    final today = dateOnly(now);
    final first = DateTime(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    final days = daysBetween(first, next);
    final lead = first.weekday - 1;
    final c = DashAccent.of(context, p.accent);
    return StreamBuilder<List<Calendar>>(
      stream: db.watchCalendars(),
      builder: (context, cSnap) {
        final cals = {for (final c in cSnap.data ?? const <Calendar>[]) c.id: c};
        return StreamBuilder<List<Event>>(
          stream: db.watchEventsBetween(first, next),
          builder: (context, snap) {
            final occ = expand(snap.data ?? const [], cals, first, next);
            final dots = <int, Color>{};
            for (var d = 1; d <= days; d++) {
              final day = DateTime(now.year, now.month, d);
              final o = occ.where((o) => o.touches(day)).firstOrNull;
              if (o != null) dots[d] = o.color;
            }
            final cell = large ? 40.0 : 32.0;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _push(context, const CalendarPage()),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('MMMM y').format(now),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          Text(
                            dots.isEmpty
                                ? 'Nothing planned'
                                : '${dots.length} busy ${dots.length == 1 ? 'day' : 'days'}',
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                            Expanded(
                              child: Text(
                                d,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (var w = 0; w * 7 < lead + days; w++)
                        Row(
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: SizedBox(
                                  height: cell,
                                  child: Builder(
                                    builder: (context) {
                                      final d = w * 7 + i - lead + 1;
                                      if (d < 1 || d > days) return const SizedBox.shrink();
                                      final isToday = DateTime(now.year, now.month, d) == today;
                                      final past = d < today.day;
                                      return Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: cell - 8,
                                            height: cell - 12,
                                            alignment: Alignment.center,
                                            decoration: isToday
                                                ? BoxDecoration(color: c, borderRadius: BorderRadius.circular(99))
                                                : null,
                                            child: Text(
                                              '$d',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                                                color: isToday ? Colors.white : (past ? p.muted : null),
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          CircleAvatar(radius: 2, backgroundColor: dots[d] ?? Colors.transparent),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
