import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps/ai/ai_page.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/lists/lists_page.dart';
import '../apps/wallet/wallet_page.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import 'customize.dart';
import 'home_page.dart';
import 'search_page.dart';

/// The bottom tabs, by a fixed id that does not change when the owner reorders them (Me → Bottom tabs).
/// Home's shortcuts open them through [HomePage.onOpenTab]; a tab that is not on the bar opens as a page.
abstract final class ShellTab {
  static const home = 0;
  static const calendar = 1;
  static const wallet = 2;

  /// Lists: To-do and Notes together.
  static const todo = 3;
  static const ai = 4;
}

/// One tab the bar can hold.
class TabSpec {
  const TabSpec(this.tab, this.id, this.icon, this.selectedIcon, this.label, this.page);
  final int tab;

  /// The name kept in settings.
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() page;
}

/// Every tab, Home first, then the rest in their starting order.
final tabSpecs = <TabSpec>[
  TabSpec(ShellTab.home, 'home', Icons.grid_view_outlined, Icons.grid_view_rounded, 'Home', () => const SizedBox()),
  TabSpec(
    ShellTab.calendar,
    'calendar',
    Icons.calendar_today_outlined,
    Icons.calendar_today_rounded,
    'Calendar',
    () => const CalendarPage(),
  ),
  TabSpec(
    ShellTab.wallet,
    'wallet',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
    'Wallet',
    () => const WalletPage(),
  ),
  TabSpec(
    ShellTab.todo,
    'todo',
    Icons.check_circle_outline_rounded,
    Icons.check_circle_rounded,
    'Lists',
    () => const ListsPage(),
  ),
  TabSpec(ShellTab.ai, 'ai', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI', () => const AiPage()),
];

TabSpec tabSpec(int tab) => tabSpecs.firstWhere((t) => t.tab == tab);

/// Which tabs follow Home on the bar, in order, and which one opens on start.
const tabsKey = 'shell.tabs';
const startTabKey = 'shell.startTab';

/// The bar holds Home and at most this many more, so labels stay readable on a phone.
const maxExtraTabs = 4;
const defaultTabs = [ShellTab.calendar, ShellTab.wallet, ShellTab.todo, ShellTab.ai];

/// The tabs after Home, in the owner's order. Unknown names are skipped, and an empty or broken value falls
/// back to the starting four, so the bar always has at least two tabs.
List<int> barTabs(AppSettings s) {
  final raw = s.raw(tabsKey);
  if (raw == null) return defaultTabs;
  // Notes had a tab of its own before it joined To-do in Lists.
  final byId = {for (final t in tabSpecs.skip(1)) t.id: t.tab, 'notes': ShellTab.todo};
  final out = <int>[];
  for (final id in raw.split(',')) {
    final t = byId[id];
    if (t != null && !out.contains(t) && out.length < maxExtraTabs) out.add(t);
  }
  return out.isEmpty ? defaultTabs : out;
}

Future<void> setBarTabs(AppSettings s, List<int> tabs) =>
    s.setRaw(tabsKey, [for (final t in tabs) tabSpec(t).id].join(','));

/// The tab Hub opens on, if it is still on the bar; Home otherwise.
int startTab(AppSettings s) {
  final raw = s.raw(startTabKey);
  final id = raw == 'notes' ? 'todo' : raw;
  final tabs = barTabs(s);
  for (final t in tabs) {
    if (tabSpec(t).id == id) return t;
  }
  return ShellTab.home;
}

/// Top-level navigation: bottom bar on phones, side rail on wide windows.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  /// The open tab, by [ShellTab] id.
  int _tab = ShellTab.home;
  List<int> _order = [ShellTab.home, ...defaultTabs];
  AppSettings? _settings;

  // Tabs are built the first time they are opened, then kept alive, so start-up only pays for Home.
  final _visited = <int>{ShellTab.home};

  // Made once, so a redraw of the shell (a tab added, say) does not rebuild the pages under it.
  late final Map<int, Widget> _pages = {
    for (final t in tabSpecs)
      t.tab: KeyedSubtree(
        key: ValueKey(t.id),
        child: switch (t.tab) {
          ShellTab.home => HomePage(onOpenTab: openTab),
          _ => t.page(),
        },
      ),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listened to directly, not through Hub, so the shell only redraws when the tabs change.
    final s = context.getInheritedWidgetOfExactType<Hub>()?.settings;
    if (s == null || s == _settings) return;
    _settings?.removeListener(_settingsChanged);
    _settings = s..addListener(_settingsChanged);
    _order = [ShellTab.home, ...barTabs(s)];
    _tab = startTab(s);
    _visited.add(_tab);
  }

  @override
  void dispose() {
    _settings?.removeListener(_settingsChanged);
    super.dispose();
  }

  void _settingsChanged() {
    final next = [ShellTab.home, ...barTabs(_settings!)];
    if (listEquals(next, _order)) return;
    setState(() {
      _order = next;
      if (!_order.contains(_tab)) _tab = ShellTab.home;
    });
  }

  /// Opens a tab by position on the bar (taps, Ctrl+1 to Ctrl+N).
  void select(int position) {
    if (position < 0 || position >= _order.length) return;
    _show(_order[position]);
  }

  void _show(int tab) {
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  /// Opens a tab by [ShellTab] id. One the owner took off the bar opens as an ordinary page instead.
  void openTab(int tab) {
    if (_order.contains(tab)) {
      _show(tab);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => tabSpec(tab).page()));
    }
  }

  void _customize() {
    HapticFeedback.mediumImpact();
    showTabsSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        // Ctrl+1, Ctrl+2 and on jump to the tabs in their order on the bar.
        for (var i = 0; i < _order.length; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => select(i),
      },
      child: Focus(
        autofocus: true,
        child: IndexedStack(
          index: _order.indexOf(_tab),
          children: [
            for (final t in _order)
              _visited.contains(t) ? _pages[t]! : KeyedSubtree(key: ValueKey('empty-$t'), child: const SizedBox()),
          ],
        ),
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;

    // Back on any other tab goes to Home first; only back on Home leaves the app.
    return PopScope(
      canPop: _tab == ShellTab.home,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _tab != ShellTab.home) _show(ShellTab.home);
      },
      child: wide ? _rail(context, body) : _bar(body),
    );
  }

  Widget _rail(BuildContext context, Widget body) => Scaffold(
    body: Row(
      children: [
        GestureDetector(
          onLongPress: _customize,
          child: NavigationRail(
            selectedIndex: _order.indexOf(_tab),
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            minWidth: 76,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
            ),
            destinations: [
              for (final t in _order.map(tabSpec))
                NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: Text(t.label)),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: Palette.of(context).line),
        Expanded(child: body),
      ],
    ),
  );

  Widget _bar(Widget body) => Scaffold(
    // Pages run on under the bar; it blurs what passes beneath and fades it out above its top edge.
    extendBody: true,
    body: body,
    // Holding the bar opens the tab picker.
    bottomNavigationBar: GestureDetector(
      onLongPress: _customize,
      child: _FrostedBar(
        child: NavigationBar(
          selectedIndex: _order.indexOf(_tab),
          onDestinationSelected: select,
          backgroundColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final t in _order.map(tabSpec))
              NavigationDestination(
                // No tooltip: labels always show, and holding the bar opens the tab picker instead.
                tooltip: '',
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    ),
  );
}

/// How far the fog above the bottom bar reaches up into the page.
const navFogHeight = 18.0;

/// The see-through glass the bottom bar is made of, and Home's ask bar with it.
Color frostedGlass(BuildContext context) {
  final p = Palette.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return p.background.withValues(alpha: dark ? 0.72 : 0.78);
}

/// How much the glass blurs what passes beneath it.
const frostedBlur = 22.0;

/// The hairline along the glass's edge.
BorderSide frostedEdge(BuildContext context) =>
    BorderSide(color: Palette.of(context).line.withValues(alpha: 0.6), width: 0.5);

/// The bottom bar as a pane of frosted glass: the page shows through, blurred, at about three quarters
/// opacity, and a soft fog above the top edge lets scrolling content fade out instead of being cut off.
class _FrostedBar extends StatelessWidget {
  const _FrostedBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final glass = frostedGlass(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Taps pass straight through the fog to the page.
        IgnorePointer(
          child: Container(
            height: navFogHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.background.withValues(alpha: 0), glass],
                stops: const [0, 1],
              ),
            ),
          ),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: frostedBlur, sigmaY: frostedBlur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: glass,
                border: Border(top: frostedEdge(context)),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
