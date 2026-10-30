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

  static const _destinations = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Home'),
    (Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Calendar'),
    (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'To-do'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI'),
  ];

  void select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onOpenTab: select),
      const CalendarPage(),
      const TodoPage(),
      const AiPage(),
    ];
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        for (var i = 0; i < 4; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => select(i),
      },
      child: Focus(autofocus: true, child: IndexedStack(index: _index, children: pages)),
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final p = Palette.of(context);

    if (wide) {
      return Scaffold(
        body: Row(children: [
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
        ]),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
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
