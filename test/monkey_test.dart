// Taps every button, row and chip on each mini-app with demo data, one at a time. Whatever opens (a sheet,
// a dialog, an editor) gets long text typed in, the keyboard raised over it, a scroll from top to bottom and
// then is backed out of. Any crash or overflow on the way fails.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hub/apps/calendar/calendar_page.dart';
import 'package:hub/apps/habits/habits_page.dart';
import 'package:hub/apps/internships/internships_page.dart';
import 'package:hub/apps/notes/notes_page.dart';
import 'package:hub/apps/shopping/shopping_page.dart';
import 'package:hub/apps/spaces/my_spaces.dart';
import 'package:hub/apps/spaces/space_page.dart';
import 'package:hub/apps/todo/todo_page.dart';
import 'package:hub/apps/wallet/subscriptions_page.dart';
import 'package:hub/apps/wallet/wallet_page.dart';
import 'package:hub/apps/wallet/year_page.dart';
import 'package:hub/core/edition.dart';

import '../screenshots/screenshots_test.dart' show loadFonts;
import 'flows_test.dart' show configName, done, pumpPage, scrollThrough, settle;

const _long = 'A very long name that keeps going past the edge of the phone screen, to see what wraps and what breaks';

/// Everything on screen that reacts to a tap, in a stable order.
List<Element> tappables(WidgetTester t) {
  final f = find
      .byWidgetPredicate(
        (w) =>
            (w is InkWell && w.onTap != null) ||
            (w is GestureDetector && w.onTap != null) ||
            (w is IconButton && w.onPressed != null) ||
            (w is ButtonStyleButton && w.onPressed != null) ||
            (w is FloatingActionButton && w.onPressed != null),
      )
      .hitTestable();
  return f.evaluate().toList();
}

bool _isRoot(WidgetTester t, int depth) => routeDepth(t) <= depth;

/// How many routes are on the root navigator.
int routeDepth(WidgetTester t) {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  var n = 0;
  nav.popUntil((r) {
    n++;
    return true;
  });
  return n;
}

/// Backs out of whatever opened, saying "Discard" or "Cancel" to any question on the way.
Future<void> backOut(WidgetTester t, int depth) async {
  for (var i = 0; i < 8 && !_isRoot(t, depth); i++) {
    final navs = find.byType(Navigator).evaluate().toList();
    for (final n in navs.reversed) {
      final state = (n as StatefulElement).state as NavigatorState;
      if (state.canPop()) {
        await state.maybePop();
        break;
      }
    }
    await settle(t, 2);
    for (final word in ['Discard', 'Cancel', 'Leave', 'Close', 'Keep editing']) {
      final b = find.widgetWithText(TextButton, word).hitTestable();
      if (b.evaluate().isNotEmpty && word != 'Keep editing') {
        await t.tap(b.first, warnIfMissed: false);
        await settle(t, 2);
        break;
      }
    }
  }
}

/// Types long text into each field, raises a keyboard over the sheet and scrolls it.
Future<void> poke(WidgetTester t) async {
  final fields = find.byType(EditableText).hitTestable();
  final n = fields.evaluate().length;
  for (var i = 0; i < n && i < 3; i++) {
    final f = find.byType(EditableText).hitTestable();
    if (f.evaluate().length <= i) break;
    final e = f.evaluate().elementAt(i).widget as EditableText;
    if (e.readOnly) continue;
    // Numbers stay numbers so money and hours fields keep working.
    final numeric =
        e.keyboardType.index == TextInputType.number.index ||
        e.keyboardType == const TextInputType.numberWithOptions(decimal: true) ||
        e.keyboardType == const TextInputType.numberWithOptions(decimal: true, signed: true);
    await t.enterText(f.at(i), numeric ? '12.5' : _long);
    await t.pump(const Duration(milliseconds: 100));
  }
  t.view.viewInsets = const FakeViewPadding(bottom: 330);
  await t.pump(const Duration(milliseconds: 300));
  await scrollThrough(t);
  t.view.resetViewInsets();
  await t.pump(const Duration(milliseconds: 300));
}

void monkey(String name, Widget Function()? page, {int limit = 60}) {
  for (final c in const [(Size(412, 915), true, 1.3), (Size(360, 740), false, 1.3)]) {
    testWidgets('monkey $name ${configName(c)}', (t) async {
      final db = await pumpPage(t, c, page);
      final depth = routeDepth(t);
      final seen = <String>{};
      // Fields on the page itself (quick add, search) with the keyboard up.
      if (find.byType(EditableText).hitTestable().evaluate().isNotEmpty) {
        await poke(t);
        await backOut(t, depth);
      }
      // Top of the page, then a screen further down, then further still.
      for (var screen = 0; screen < 3; screen++) {
        var i = 0;
        while (i < limit) {
          final all = tappables(t);
          if (i >= all.length) break;
          final el = all[i];
          i++;
          final box = el.renderObject as RenderBox?;
          if (box == null || !box.attached || !box.hasSize) continue;
          final at = box.localToGlobal(box.size.center(Offset.zero));
          final key = '${el.widget.runtimeType}@${at.dx.round()},${at.dy.round()}';
          if (!seen.add(key)) continue;
          final label = el.widget is IconButton ? (el.widget as IconButton).tooltip : null;
          if (label == 'Back') continue;
          debugPrint('  tap $key ${label ?? ''}');
          await t.tapAt(at, kind: PointerDeviceKind.touch);
          await settle(t, 2);
          if (!_isRoot(t, depth)) {
            await scrollThrough(t);
            await poke(t);
            await backOut(t, depth);
          }
          // A tap may have scrolled or changed tabs; carry on from there.
        }
        final s = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
        if (s.evaluate().isEmpty) break;
        final state = t.state<ScrollableState>(s.first);
        final pos = state.position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        pos.jumpTo((pos.pixels + pos.viewportDimension * 0.9).clamp(0, pos.maxScrollExtent));
        await settle(t, 2);
      }
      await done(t, db);
    });
  }
}

void main() {
  personalEdition = false;
  setUpAll(loadFonts);
  setUp(() {
    // Links and file pickers have no platform side in tests: they answer "nothing opened".
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'plugins.flutter.io/url_launcher',
      'plugins.flutter.io/url_launcher_android',
      'miguelruivo.flutter.plugins.filepicker',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });
  monkey('todo', () => const TodoPage());
  monkey('notes', () => const NotesPage());
  monkey('calendar', () => const CalendarPage());
  monkey('wallet', () => const WalletPage());
  monkey('savings', () => const WalletPage(initialTab: 1));
  monkey('investing', () => const WalletPage(initialTab: 2));
  monkey('subscriptions', () => const SubscriptionsPage());
  monkey('year', () => const YearPage());
  monkey('shopping', () => const ShoppingPage());
  monkey('habits', () => const HabitsPage());
  monkey('internships', () => const InternshipsPage());
  monkey('spaces', () => const SpacesPage());
  monkey('university', () => const SpaceLauncher(gid: 'seed-uni', fallbackName: 'University'));
  monkey('job', () => const SpaceLauncher(gid: 'seed-job', fallbackName: 'Job'));
}
