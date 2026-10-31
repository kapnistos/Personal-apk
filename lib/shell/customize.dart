import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/press.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'dashboard.dart' show homeDensityKey, homeGreetingKey;
import 'home_page.dart' show pickVisibleApps;
import 'shell.dart';

/// Parts of the fixed top of Home the owner switched off: 'weather', 'today' and 'apps'.
const homeHiddenTopKey = 'home.hiddenTop';

/// 'off' shows the apps as one grid instead of under Plan, Life and Work and chat.
const homeAppGroupsKey = 'home.appGroups';

/// The parts of Home's top, in the order they appear.
const homeTopParts = [
  ('weather', 'Weather', 'The forecast for your city', Icons.wb_sunny_outlined),
  ('today', 'Today strip', 'Next event, tasks and money', Icons.view_week_outlined),
  ('apps', 'Apps', 'Every app as a round button', Icons.apps_rounded),
];

Set<String> _hiddenTop(AppSettings s) => {...?s.raw(homeHiddenTopKey)?.split(',').where((x) => x.isNotEmpty)};

/// Whether a part of Home's top ([homeTopParts]) is shown.
bool homeShows(AppSettings s, String part) => !_hiddenTop(s).contains(part);

Future<void> setHomeShows(AppSettings s, String part, bool show) {
  final hidden = _hiddenTop(s);
  show ? hidden.remove(part) : hidden.add(part);
  return s.setRaw(homeHiddenTopKey, (hidden.toList()..sort()).join(','));
}

/// Whether Home's apps sit under group headings.
bool homeGroupsApps(AppSettings s) => s.raw(homeAppGroupsKey) != 'off';

/// The switches for what Home shows above your widgets. Used in Me and from Home's edit mode.
class HomeTopOptions extends StatelessWidget {
  const HomeTopOptions({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final apps = homeShows(s, 'apps');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switch(
          context,
          icon: Icons.waving_hand_outlined,
          title: 'Greeting',
          subtitle: 'The date and a hello',
          value: s.raw(homeGreetingKey) != 'off',
          onChanged: (v) => s.setRaw(homeGreetingKey, v ? 'on' : 'off'),
        ),
        for (final (id, title, subtitle, icon) in homeTopParts)
          _switch(
            context,
            icon: icon,
            title: title,
            subtitle: subtitle,
            value: homeShows(s, id),
            onChanged: (v) => setHomeShows(s, id, v),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: apps
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _switch(
                      context,
                      icon: Icons.segment_rounded,
                      title: 'Group apps',
                      subtitle: 'Under Plan, Life and Work and chat',
                      value: homeGroupsApps(s),
                      onChanged: (v) => s.setRaw(homeAppGroupsKey, v ? 'on' : 'off'),
                    ),
                    Press(
                      child: ListTile(
                        leading: const RowIcon(Icons.swap_vert_rounded),
                        title: const Text('Choose and order apps'),
                        subtitle: const Text('Hide the ones you never use'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => pickVisibleApps(context),
                      ),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        _Spacing(settings: s),
      ],
    );
  }

  Widget _switch(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    secondary: RowIcon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: (v) {
      HapticFeedback.selectionClick();
      onChanged(v);
    },
  );
}

class _Spacing extends StatelessWidget {
  const _Spacing({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const RowIcon(Icons.density_medium_rounded),
    title: const Text('Spacing'),
    trailing: PillToggle<String>(
      dense: true,
      options: const [('comfortable', 'Roomy'), ('compact', 'Compact')],
      value: settings.raw(homeDensityKey) == 'compact' ? 'compact' : 'comfortable',
      onChanged: (v) => settings.setRaw(homeDensityKey, v),
    ),
  );
}

/// What Home shows, as a sheet over Home's edit mode.
Future<void> showHomeTopSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_sheetTitle(ctx, 'Top of Home', 'What sits above your widgets'), const HomeTopOptions()],
      ),
    ),
  ),
);

Widget _sheetTitle(BuildContext context, String title, String subtitle) {
  final p = Palette.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: p.muted, height: 1.35)),
      ],
    ),
  );
}

/// A short line naming the tabs on the bar, for the row in Me.
String tabsSummary(AppSettings s) => ['Home', for (final t in barTabs(s)) tabSpec(t).label].join(', ');

/// Choose the bottom tabs, put them in order and pick the one Hub opens on. Home always comes first.
Future<void> showTabsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => const SafeArea(child: _TabsSheet()),
);

class _TabsSheet extends StatefulWidget {
  const _TabsSheet();

  @override
  State<_TabsSheet> createState() => _TabsSheetState();
}

class _TabsSheetState extends State<_TabsSheet> {
  // Read once: the sheet keeps its own list while open, so a tab switched off stays where it was.
  late final AppSettings _s = context.getInheritedWidgetOfExactType<Hub>()!.settings;
  late final List<int> _all;
  late final Set<int> _on;

  @override
  void initState() {
    super.initState();
    final bar = barTabs(_s);
    _on = bar.toSet();
    _all = [
      ...bar,
      for (final t in tabSpecs.skip(1))
        if (!bar.contains(t.tab)) t.tab,
    ];
  }

  List<int> get _bar => [
    for (final t in _all)
      if (_on.contains(t)) t,
  ];

  void _save() => setBarTabs(_s, _bar);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final full = _on.length >= maxExtraTabs;
    final start = startTab(_s);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetTitle(context, 'Bottom tabs', 'Home is always first. Drag to reorder; up to ${maxExtraTabs + 1} fit.'),
          ListTile(
            leading: RowIcon(tabSpec(ShellTab.home).selectedIcon),
            title: const Text('Home'),
            trailing: Icon(Icons.lock_outline_rounded, size: 20, color: p.muted),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              HapticFeedback.selectionClick();
              setState(() {
                _all.insert(to, _all.removeAt(from));
              });
              _save();
            },
            children: [
              for (final (i, t) in _all.indexed)
                Material(
                  key: ValueKey(t),
                  color: Colors.transparent,
                  child: ListTile(
                    leading: RowIcon(tabSpec(t).selectedIcon),
                    title: Text(tabSpec(t).label),
                    // The last tab after Home stays: the bar needs two.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _on.contains(t),
                          onChanged: (_on.contains(t) && _on.length == 1) || (!_on.contains(t) && full)
                              ? null
                              : (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => v ? _on.add(t) : _on.remove(t));
                                  _save();
                                },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                            child: Icon(Icons.drag_handle_rounded, color: p.muted, semanticLabel: 'Drag to reorder'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (full)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'The bar is full. Turn one off to add another; tabs off the bar still open from Home.',
                style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open on start',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in [ShellTab.home, ..._bar])
                      ChoiceChip(
                        label: Text(tabSpec(t).label),
                        selected: start == t,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() {});
                          _s.setRaw(startTabKey, tabSpec(t).id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
