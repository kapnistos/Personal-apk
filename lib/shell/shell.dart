import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps/ai/ai_page.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/todo/todo_page.dart';
import '../core/theme.dart';
import 'home_page.dart';
import 'search_page.dart';

/// Top-level navigation: bottom bar on phones, side rail on wide windows.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  // Tabs are built the first time they are opened, then kept alive, so start-up only pays for Home.
  final _visited = <int>{0};

  static const _destinations = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Home'),
    (Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Calendar'),
    (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'To-do'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI'),
  ];

  void select(int i) => setState(() {
    _index = i;
    _visited.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final pages = [HomePage(onOpenTab: select), const CalendarPage(), const TodoPage(), const AiPage()];
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        for (var i = 0; i < 4; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => select(i),
      },
      child: Focus(
        autofocus: true,
        child: IndexedStack(
          index: _index,
          children: [for (var i = 0; i < pages.length; i++) _visited.contains(i) ? pages[i] : const SizedBox.shrink()],
        ),
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final p = Palette.of(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              minWidth: 76,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
              ),
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
              ],
            ),
            VerticalDivider(width: 1, color: p.line),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      // Pages run on under the bar; it blurs what passes beneath and fades it out above its top edge.
      extendBody: true,
      body: body,
      bottomNavigationBar: _FrostedBar(
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
          backgroundColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      ),
    );
  }
}

/// How far the fog above the bottom bar reaches up into the page.
const navFogHeight = 18.0;

/// The bottom bar as a pane of frosted glass: the page shows through, blurred, at about three quarters
/// opacity, and a soft fog above the top edge lets scrolling content fade out instead of being cut off.
class _FrostedBar extends StatelessWidget {
  const _FrostedBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = p.background.withValues(alpha: dark ? 0.72 : 0.78);
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
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: glass,
                border: Border(top: BorderSide(color: p.line.withValues(alpha: 0.6), width: 0.5)),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
