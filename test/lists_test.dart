import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/lists/lists_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/core/settings.dart';

import 'widget_test.dart' show pumpWithDb;

void main() {
  bool onStage(WidgetTester t, Type type) {
    final stack = t.widget<IndexedStack>(
      find.descendant(of: find.byType(ListsPage), matching: find.byType(IndexedStack)).first,
    );
    return stack.index == (type == TodoPage ? 0 : 1);
  }

  testWidgets('Lists switches between To-do and Notes from its title, and remembers the choice', (tester) async {
    late AppSettings settings;
    await pumpWithDb(
      tester,
      (db, s) {
        settings = s;
        return Hub(db: db, settings: s, child: const MaterialApp(home: ListsPage()));
      },
      (db) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(onStage(tester, TodoPage), isTrue);
        await tester.tap(find.text('Notes').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(onStage(tester, NotesPage), isTrue);
        expect(settings.raw(listsViewKey), 'notes');
        await tester.tap(find.text('To-do').last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(onStage(tester, TodoPage), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('Lists opens on the half it is asked for', (tester) async {
    await pumpWithDb(
      tester,
      (db, s) => Hub(db: db, settings: s, child: const MaterialApp(home: ListsPage(initial: ListsView.notes))),
      (db) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(onStage(tester, NotesPage), isTrue);
      },
    );
  });
}
