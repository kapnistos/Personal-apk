import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apps/ai/ai_page.dart';
import '../apps/calendar/calendar_page.dart';
import '../apps/todo/todo_page.dart';
import '../apps/wallet/wallet_page.dart';
import '../core/theme.dart';
import 'home_page.dart';
import 'search_page.dart';

/// The bottom tabs, by position. Home's shortcuts open them through [HomePage.onOpenTab].
abstract final class ShellTab {
  static const home = 0;
  static const calendar = 1;
  static const wallet = 2;
  static const todo = 3;
  static const ai = 4;
}

/// Top-level navigation: bottom bar on phones, side rail on wide windows.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = ShellTab.home;

  // Tabs are built the first time they are opened, then kept alive, so start-up only pays for Home.
  final _visited = <int>{ShellTab.home};

  static const _destinations = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Home'),
    (Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Calendar'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
    (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'To-do'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI'),
  ];

  void select(int i) {
    if (i < 0 || i >= _destinations.length) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onOpenTab: select),
      const CalendarPage(),
      // Wallet's lists end with fixed padding, so it stops above the bar instead of running on under it.
      const _AboveBar(child: WalletPage()),
      const TodoPage(),
      const AiPage(),
    ];
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        // Ctrl+1 to Ctrl+5 jump to the tabs in order.
        for (var i = 0; i < pages.length; i++)
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

    // Back on any other tab goes to Home first; only back on Home leaves the app.
    return PopScope(
      canPop: _index == ShellTab.home,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _index != ShellTab.home) select(ShellTab.home);
      },
      child: wide ? _rail(context, body) : _bar(body),
    );
  }

  Widget _rail(BuildContext context, Widget body) => Scaffold(
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
        VerticalDivider(width: 1, color: Palette.of(context).line),
        Expanded(child: body),
      ],
    ),
  );

  Widget _bar(Widget body) => Scaffold(
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

/// Keeps a page that was not made to run on under the bottom bar clear of it: the bar's height becomes real
/// padding, so its last rows and its floating button stay above the glass.
class _AboveBar extends StatelessWidget {
  const _AboveBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: Palette.of(context).background,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
      ),
    );
  }
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
