import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../notes/notes_page.dart';
import '../todo/todo_page.dart';

/// The two halves of Lists.
enum ListsView { todo, notes }

/// Which half Lists opened on last time.
const listsViewKey = 'lists.view';

/// To-do and Notes in one app: the title is the switch between them, and each keeps its own tools.
class ListsPage extends StatefulWidget {
  const ListsPage({super.key, this.initial});

  /// Opens on this half; the one used last when null.
  final ListsView? initial;

  @override
  State<ListsPage> createState() => _ListsPageState();
}

class _ListsPageState extends State<ListsPage> {
  ListsView? _view;

  ListsView get view =>
      _view ?? widget.initial ?? ListsView.values.asNameMap()[context.settings.raw(listsViewKey)] ?? ListsView.todo;

  void _show(ListsView v) {
    if (v == view) return;
    HapticFeedback.selectionClick();
    setState(() => _view = v);
    context.settings.setRaw(listsViewKey, v.name);
  }

  @override
  Widget build(BuildContext context) {
    final title = ListsTitle(value: view, onChanged: _show);
    // Both stay alive, so a half-typed task or a scrolled list is still there after a look at the other side.
    return IndexedStack(
      index: view.index,
      children: [
        TodoPage(title: title),
        _AboveBottomInset(child: NotesPage(title: title)),
      ],
    );
  }
}

/// "To-do  Notes" as the page title: the open one in ink, the other quieter, either one a tap away.
class ListsTitle extends StatelessWidget {
  const ListsTitle({super.key, required this.value, required this.onChanged});
  final ListsView value;
  final ValueChanged<ListsView> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final base = DefaultTextStyle.of(context).style;
    // Scaled down rather than cut off when the actions leave little room, on a narrow phone or with large text.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (i, (v, label)) in [(ListsView.todo, 'To-do'), (ListsView.notes, 'Notes')].indexed) ...[
            if (i > 0) const SizedBox(width: 14),
            Semantics(
              button: true,
              selected: v == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    // The other half reads as a quieter tab next to the title.
                    style: v == value
                        ? base.copyWith(color: p.ink)
                        : base.copyWith(color: p.muted, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                    child: Text(label),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Notes ends with fixed padding and floating buttons, so the bottom bar's height becomes real padding there.
class _AboveBottomInset extends StatelessWidget {
  const _AboveBottomInset({required this.child});
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
