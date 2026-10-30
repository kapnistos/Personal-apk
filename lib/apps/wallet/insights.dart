import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'accounts_page.dart' show AccountState;
import 'wallet_logic.dart';
import 'wallet_model.dart';

/// Raw settings keys for the wallet's targets.
const spendTargetKey = 'wallet.target';
const roundUpKey = 'wallet.roundup';

/// How this month is going against a monthly spending target.
class SpendPlan {
  SpendPlan({required this.target, required this.spent, required this.billsAhead, required DateTime now}) {
    final today = dateOnly(now);
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1);
    daysInMonth = daysBetween(monthStart, monthEnd);
    daysLeft = daysBetween(today, monthEnd); // Today counts as a day still to spend.
    left = target - spent - billsAhead;
    perDay = daysLeft == 0 ? 0 : (left / daysLeft).floor();
    final dayOfMonth = daysInMonth - daysLeft + 1;
    // Where spending "should" be by the end of today if spread evenly.
    expectedByNow = (target * dayOfMonth / daysInMonth).round();
  }

  final int target;
  final int spent;

  /// Recurring payments still to leave this month.
  final int billsAhead;
  late final int daysInMonth;
  late final int daysLeft;
  late final int left;
  late final int perDay;
  late final int expectedByNow;

  /// Positive when spending (bills to come included) is under the even pace, negative when over it.
  int get paceDiff => expectedByNow - spent - billsAhead;
  bool get over => left < 0;
  double get usedFraction => target <= 0 ? 0 : ((spent + billsAhead) / target).clamp(0, 1).toDouble();
  double get paceFraction => target <= 0 ? 0 : (expectedByNow / target).clamp(0, 1).toDouble();
}

/// One category that is noticeably different from the last three months.
class CategoryInsight {
  const CategoryInsight(this.category, this.now, this.usual);
  final String category;
  final int now;

  /// Average of the previous three months.
  final int usual;
  double get change => usual == 0 ? 1 : (now - usual) / usual;
}

/// Categories this month that differ from the usual by at least a fifth (and €10), biggest first.
List<CategoryInsight> categoryInsights(Map<String, int> thisMonth, List<Map<String, int>> previous) {
  final usual = <String, int>{};
  for (final m in previous) {
    m.forEach((k, v) => usual[k] = (usual[k] ?? 0) + v);
  }
  final months = previous.isEmpty ? 1 : previous.length;
  final out = <CategoryInsight>[];
  for (final k in {...thisMonth.keys, ...usual.keys}) {
    final now = thisMonth[k] ?? 0;
    final avg = ((usual[k] ?? 0) / months).round();
    if ((now - avg).abs() < 1000) continue;
    if (avg > 0 && ((now - avg) / avg).abs() < 0.2) continue;
    out.add(CategoryInsight(k, now, avg));
  }
  out.sort((a, b) => (b.now - b.usual).abs().compareTo((a.now - a.usual).abs()));
  return out;
}

/// Days so far this month without a single everyday expense.
int noSpendDays(List<Entry> monthEntries, DateTime now) {
  final today = dateOnly(now);
  final spentOn = {
    for (final e in monthEntries)
      if (e.kind == EntryKind.expense) dateOnly(e.date),
  };
  var n = 0;
  for (var d = DateTime(today.year, today.month); !d.isAfter(today); d = addDays(d, 1)) {
    if (!spentOn.contains(d)) n++;
  }
  return n;
}

/// Cents to the next whole euro: €3.40 rounds up by €0.60, €5.00 by nothing.
int roundUpCents(int cents) => (100 - cents.abs() % 100) % 100;

/// After a new expense, puts its round-up into the chosen savings goal, if any. Returns the cents moved.
Future<int> applyRoundUp(AppDatabase db, String? goalSetting, int cents, String label) async {
  final goalId = int.tryParse(goalSetting ?? '');
  if (goalId == null) return 0;
  final goals = await db.watchGoals().first;
  if (!goals.any((g) => g.id == goalId && !g.archived)) return 0;
  final r = roundUpCents(cents);
  if (r == 0) return 0;
  await db.addMove(goalId, r, note: 'Round-up · $label');
  return r;
}

/// Everything owned: card balances, savings goals and investments.
class NetWorth {
  const NetWorth(this.cards, this.savings, this.investments);
  final int cards;
  final int savings;
  final int investments;
  int get total => cards + savings + investments;
}

/// Net worth from the rows themselves, so the card can follow plain table streams.
NetWorth netWorthOf({
  required List<Account> accounts,
  required List<Entry> entries,
  required List<Subscription> subs,
  required List<SavingsMove> moves,
  required List<Holding> holdings,
  DateTime? now,
}) {
  final byAccount = <String, List<Entry>>{};
  for (final e in entries) {
    (byAccount[e.account.trim().toLowerCase()] ??= []).add(e);
  }
  var cards = 0;
  for (final a in accounts) {
    if (a.balanceAt == null) continue;
    cards += AccountState(a, byAccount[a.name.trim().toLowerCase()] ?? const [], subs, now: now).balance;
  }
  final savings = moves.fold<int>(0, (t, m) => t + m.amountCents);
  final investments = holdings.fold<int>(0, (t, h) => t + (h.units * h.price * 100).round());
  return NetWorth(cards, savings, investments);
}

Future<NetWorth> computeNetWorth(AppDatabase db, {DateTime? now}) async => netWorthOf(
  accounts: await db.select(db.accounts).get(),
  entries: await db.select(db.entries).get(),
  subs: await db.select(db.subscriptions).get(),
  moves: await db.select(db.savingsMoves).get(),
  holdings: await db.select(db.holdings).get(),
  now: now,
);

/// Money in whole units, for chart labels: "€1,800".
String moneyWhole(int cents, String currency) =>
    NumberFormat.simpleCurrency(name: currency, decimalDigits: 0).format(cents / 100);

/// Running total of spending through each day of [month], up to [lastDay].
List<int> cumulativeSpend(List<Entry> entries, DateTime month, int lastDay) {
  final perDay = List<int>.filled(lastDay, 0);
  for (final e in entries) {
    if (e.kind.sign >= 0 || e.date.year != month.year || e.date.month != month.month) continue;
    if (e.date.day > lastDay) continue;
    perDay[e.date.day - 1] += e.amountCents;
  }
  for (var i = 1; i < perDay.length; i++) {
    perDay[i] += perDay[i - 1];
  }
  return perDay;
}

/// The month at a glance: what is left of the budget (or the net when there is none) over a chart of
/// spending day by day against an even pace.
class SpendingHero extends StatelessWidget {
  const SpendingHero({super.key, required this.month, required this.monthEntries, required this.currency});
  final DateTime month;
  final List<Entry> monthEntries;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final settings = context.settings;
    final target = int.tryParse(settings.raw(spendTargetKey) ?? '');
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final isCurrent = month == current;
    final isPast = month.isBefore(current);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final lastDay = isCurrent ? now.day : (isPast ? daysInMonth : 0);
    final spentSoFar = MonthSummary(monthEntries.where((e) => !e.date.isAfter(now)).toList()).out;
    final cumulative = cumulativeSpend(monthEntries.where((e) => !e.date.isAfter(now)).toList(), month, lastDay);
    final free = lastDay == 0
        ? 0
        : noSpendDays(monthEntries, isCurrent ? now : DateTime(month.year, month.month, daysInMonth));
    final hasTarget = target != null && target > 0;
    if (!hasTarget || lastDay == 0) {
      return _HeroShell(
        children: [
          _NetHeader(entries: monthEntries, currency: currency, canSetBudget: !hasTarget),
          if (spentSoFar > 0) ...[
            const SizedBox(height: 20),
            _ChartBlock(
              month: month,
              cumulative: cumulative,
              daysInMonth: daysInMonth,
              budget: null,
              currency: currency,
              noSpendDays: free,
            ),
          ],
        ],
      );
    }
    if (!isCurrent) {
      final diff = target - spentSoFar;
      return _HeroShell(
        children: [
          _HeroTop(left: 'Spent', right: 'of ${money(target, currency)}'),
          const SizedBox(height: 4),
          _Amount(money(spentSoFar, currency)),
          const SizedBox(height: 12),
          _StatusLine(
            good: diff >= 0,
            strong: diff >= 0 ? '${money(diff, currency)} under budget' : '${money(-diff, currency)} over budget',
          ),
          const SizedBox(height: 20),
          _ChartBlock(
            month: month,
            cumulative: cumulative,
            daysInMonth: daysInMonth,
            budget: target,
            currency: currency,
            noSpendDays: free,
          ),
        ],
      );
    }
    return StreamBuilder<List<Subscription>>(
      stream: context.db.watchSubscriptions(),
      builder: (context, snap) {
        final end = DateTime(now.year, now.month + 1);
        final today = dateOnly(now);
        final billsAhead = (snap.data ?? const <Subscription>[])
            .where((s) => s.active && s.kind.sign < 0 && !s.nextDate.isBefore(today) && s.nextDate.isBefore(end))
            .fold<int>(0, (t, s) => t + s.amountCents);
        // Booked recurring payments are already entries; count only what hasn't been booked.
        final plan = SpendPlan(target: target, spent: spentSoFar, billsAhead: billsAhead, now: now);
        final pace = plan.paceDiff;
        final p = Palette.of(context);
        return _HeroShell(
          children: [
            _HeroTop(left: plan.over ? 'Over budget by' : 'Left to spend', right: 'of ${money(target, currency)}'),
            const SizedBox(height: 4),
            _Amount(money(plan.left.abs(), currency), color: plan.over ? p.danger : null),
            const SizedBox(height: 12),
            _StatusLine(
              good: pace >= 0,
              strong: pace >= 0 ? '${money(pace, currency)} under pace' : '${money(-pace, currency)} over pace',
              rest: [
                if (!plan.over && plan.daysLeft > 0) '${money(plan.perDay, currency)} a day left',
                if (billsAhead > 0) '${money(billsAhead, currency)} in bills to come',
              ].join(' · '),
            ),
            const SizedBox(height: 20),
            _ChartBlock(
              month: month,
              cumulative: cumulative,
              daysInMonth: daysInMonth,
              budget: target,
              currency: currency,
              noSpendDays: free,
            ),
          ],
        );
      },
    );
  }
}

class _HeroShell extends StatelessWidget {
  const _HeroShell({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Palette.of(context).surface, borderRadius: BorderRadius.circular(28)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _HeroTop extends StatelessWidget {
  const _HeroTop({required this.left, required this.right});
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 15),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(color: p.muted, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

/// The huge figure, with muted cents.
class _Amount extends StatelessWidget {
  const _Amount(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = RegExp(r'^(.*?)([.,]\d{2})(\D*)$').firstMatch(text);
    final style = TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
      height: 1.1,
      color: color ?? p.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: m == null
          ? Text(text, maxLines: 1, style: style)
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: m[1]),
                  TextSpan(
                    text: '${m[2]}${m[3]}',
                    style: style.copyWith(
                      fontSize: 30,
                      letterSpacing: 0,
                      color: (color ?? p.muted).withValues(alpha: color == null ? 1 : 0.7),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              style: style,
            ),
    );
  }
}

/// "✓ €203.11 under pace · €130.58 a day left".
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.good, required this.strong, this.rest = ''});
  final bool good;
  final String strong;
  final String rest;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = good ? p.positive : p.danger;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(good ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 20, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: strong,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                if (rest.isNotEmpty)
                  TextSpan(
                    text: ' · $rest',
                    style: TextStyle(color: p.muted),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
        ),
      ],
    );
  }
}

/// "Net this month" with money in and out, for months without a budget.
class _NetHeader extends StatelessWidget {
  const _NetHeader({required this.entries, required this.currency, required this.canSetBudget});
  final List<Entry> entries;
  final String currency;
  final bool canSetBudget;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = MonthSummary(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Net this month', style: TextStyle(color: p.muted, fontSize: 15)),
        const SizedBox(height: 4),
        _Amount(money(s.net, currency, signed: true)),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${money(s.income, currency)} in',
                style: TextStyle(color: p.positive, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' · ${money(s.out, currency)} out',
                style: TextStyle(color: p.muted),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 15),
        ),
        if (canSetBudget) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: p.ink,
                backgroundColor: p.raised,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: () => editSpendTarget(context),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Set a budget'),
            ),
          ),
        ],
      ],
    );
  }
}

/// The step chart with its day labels and legend.
class _ChartBlock extends StatelessWidget {
  const _ChartBlock({
    required this.month,
    required this.cumulative,
    required this.daysInMonth,
    required this.budget,
    required this.currency,
    required this.noSpendDays,
  });
  final DateTime month;
  final List<int> cumulative;
  final int daysInMonth;
  final int? budget;
  final String currency;
  final int noSpendDays;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final small = DefaultTextStyle.of(context).style.merge(TextStyle(color: p.muted, fontSize: 13.5));
    final last = DateTime(month.year, month.month, daysInMonth);
    final total = cumulative.isEmpty ? 0 : cumulative.last;
    return Semantics(
      label: budget == null
          ? 'Spent ${money(total, currency)} so far this month'
          : 'Spent ${money(total, currency)} of a ${money(budget!, currency)} budget',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: SpendChartPainter(
                cumulative: cumulative,
                daysInMonth: daysInMonth,
                budget: budget,
                budgetLabel: budget == null ? null : '${moneyWhole(budget!, currency)} budget',
                labelStyle: small.copyWith(fontSize: scaler.scale(13)),
                line: p.accent,
                pace: p.muted,
                grid: p.line,
                dot: p.ink,
                dotRing: p.surface,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(DateFormat('d MMM').format(month), style: small),
              const Spacer(),
              Text(DateFormat('d MMM').format(last), style: small),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _LegendItem(label: 'Spent', color: p.accent, dashed: false),
                  if (budget != null) _LegendItem(label: 'Pace', color: p.muted, dashed: true),
                ],
              ),
              if (noSpendDays > 0) Text('$noSpendDays no-spend ${noSpendDays == 1 ? 'day' : 'days'}', style: small),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color, required this.dashed});
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 18, height: 10, child: CustomPaint(painter: _LegendMark(color, dashed))),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
      ],
    );
  }
}

class _LegendMark extends CustomPainter {
  _LegendMark(this.color, this.dashed);
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.5 : 3
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(Offset(1.5, y), Offset(size.width - 1.5, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_LegendMark old) => old.color != color || old.dashed != dashed;
}

/// Cumulative spending as a stepped line with a soft fill, an even-pace line to the budget and the budget itself.
class SpendChartPainter extends CustomPainter {
  SpendChartPainter({
    required this.cumulative,
    required this.daysInMonth,
    required this.budget,
    required this.budgetLabel,
    required this.labelStyle,
    required this.line,
    required this.pace,
    required this.grid,
    required this.dot,
    required this.dotRing,
  });
  final List<int> cumulative;
  final int daysInMonth;
  final int? budget;
  final String? budgetLabel;
  final TextStyle labelStyle;
  final Color line;
  final Color pace;
  final Color grid;
  final Color dot;
  final Color dotRing;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final spent = cumulative.isEmpty ? 0 : cumulative.last;
    TextPainter? label;
    if (budgetLabel != null) {
      label = TextPainter(
        text: TextSpan(text: budgetLabel, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: w);
    }
    final top = (label?.height ?? 0) + 8;
    final bottom = size.height - 2;
    final peak = math.max(math.max(budget ?? 0, spent), 1);
    // Leave a little headroom when spending has gone past the budget.
    final yMax = budget != null && spent > budget! ? peak * 1.04 : peak.toDouble();
    double y(num v) => bottom - (bottom - top) * (v / yMax);
    double x(num day) => w * day / daysInMonth;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, bottom), Offset(w, bottom), gridPaint);

    if (budget != null) {
      final by = y(budget!);
      canvas.drawLine(Offset(0, by), Offset(w, by), gridPaint);
      label!.paint(canvas, Offset(w - label.width, by - label.height - 4));
      // Even pace: nothing on day 0, the whole budget by the last day.
      final pacePaint = Paint()
        ..color = pace.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final start = Offset(0, bottom);
      final end = Offset(w, by);
      final length = (end - start).distance;
      const dash = 5.0, gap = 4.0;
      for (var d = 0.0; d < length; d += dash + gap) {
        final a = start + (end - start) * (d / length);
        final b = start + (end - start) * (math.min(d + dash, length) / length);
        canvas.drawLine(a, b, pacePaint);
      }
    }

    if (cumulative.isEmpty) return;
    final path = Path()..moveTo(0, y(0));
    for (var i = 0; i < cumulative.length; i++) {
      path
        ..lineTo(x(i), y(cumulative[i]))
        ..lineTo(x(i + 1), y(cumulative[i]));
    }
    final lastX = x(cumulative.length);
    final fill = Path.from(path)
      ..lineTo(lastX, bottom)
      ..lineTo(0, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.32), line.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTRB(0, top, w, bottom)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final today = Offset(lastX, y(spent));
    canvas.drawCircle(today, 6, Paint()..color = dotRing);
    canvas.drawCircle(today, 4.5, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(SpendChartPainter old) =>
      old.cumulative != cumulative ||
      old.budget != budget ||
      old.daysInMonth != daysInMonth ||
      old.line != line ||
      old.dot != dot ||
      old.grid != grid ||
      old.labelStyle != labelStyle ||
      old.budgetLabel != budgetLabel;
}

/// A titled group on the wallet pages: a bold heading above one flat rounded card.
class WalletSection extends StatelessWidget {
  const WalletSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: p.ink),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Material(color: p.surface, borderRadius: BorderRadius.circular(24), clipBehavior: Clip.antiAlias, child: child),
      ],
    );
  }
}

Future<void> editSpendTarget(BuildContext context) async {
  final settings = context.settings;
  final current = int.tryParse(settings.raw(spendTargetKey) ?? '');
  final ctrl = TextEditingController(text: current == null ? '' : moneyInput(current));
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Monthly spending target'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Everything going out in a month, bills included.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: '${currencySymbol(settings.currency)} ', hintText: '1500'),
            onSubmitted: (t) => Navigator.pop(ctx, t),
          ),
        ],
      ),
      actions: [
        if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
  if (v == null) return;
  final cents = parseMoney(v);
  // Only an empty field (or Remove) clears the target; a typo keeps the old one.
  if (v.trim().isNotEmpty && (cents == null || cents <= 0)) return;
  await settings.setRaw(spendTargetKey, cents == null || cents <= 0 ? '' : '$cents');
}

/// Categories that are up or down on the usual, with a plain sentence each.
class InsightsCard extends StatelessWidget {
  const InsightsCard({super.key, required this.month, required this.thisMonth, required this.currency});
  final DateTime month;
  final Map<String, int> thisMonth;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final from = DateTime(month.year, month.month - 3);
    return StreamBuilder<List<Entry>>(
      stream: context.db.watchEntries(from, month),
      builder: (context, snap) {
        final prev = snap.data;
        if (prev == null) return const SizedBox.shrink();
        final byMonth = <int, List<Entry>>{};
        for (final e in prev) {
          (byMonth[e.date.year * 12 + e.date.month] ??= []).add(e);
        }
        // Without history there is nothing to compare to.
        if (byMonth.isEmpty) return const SizedBox.shrink();
        final previous = [for (final l in byMonth.values) MonthSummary(l).byCategory];
        final list = categoryInsights(thisMonth, previous).take(4).toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return WalletSection(
          title: 'Compared with your usual month',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final i in list)
                  ListTile(
                    dense: true,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: categoryInfo(i.category).color, shape: BoxShape.circle),
                      child: Icon(categoryInfo(i.category).icon, size: 18, color: Colors.white),
                    ),
                    title: Text(i.category, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text(i.usual == 0 ? 'New this month' : 'Usually ${money(i.usual, currency)} a month'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(i.now, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (i.usual > 0)
                          Text(
                            '${i.change > 0 ? '+' : ''}${(i.change * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: i.change > 0 ? p.danger : p.positive,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Total of everything owned, split into cards, savings and investments.
class NetWorthCard extends StatefulWidget {
  const NetWorthCard({super.key, required this.currency});
  final String currency;

  @override
  State<NetWorthCard> createState() => _NetWorthCardState();
}

class _NetWorthCardState extends State<NetWorthCard> {
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = widget.currency;
    final db = context.db;
    // Nested plain streams: each table change rebuilds just this card.
    return StreamBuilder<List<Account>>(
      stream: db.select(db.accounts).watch(),
      builder: (context, a) => StreamBuilder<List<Entry>>(
        stream: db.select(db.entries).watch(),
        builder: (context, e) => StreamBuilder<List<Subscription>>(
          stream: db.select(db.subscriptions).watch(),
          builder: (context, s) => StreamBuilder<List<SavingsMove>>(
            stream: db.select(db.savingsMoves).watch(),
            builder: (context, m) => StreamBuilder<List<Holding>>(
              stream: db.select(db.holdings).watch(),
              builder: (context, h) => _card(
                p,
                currency,
                [a.data, e.data, s.data, m.data, h.data].contains(null)
                    ? null
                    : netWorthOf(accounts: a.data!, entries: e.data!, subs: s.data!, moves: m.data!, holdings: h.data!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Palette p, String currency, NetWorth? w) {
    return Builder(
      builder: (context) {
        if (w == null) return const SizedBox(height: 120);
        final parts = [
          ('Cards', w.cards, const Color(0xFF4F86FF)),
          ('Savings', w.savings, const Color(0xFF1F9D6B)),
          ('Investments', w.investments, const Color(0xFFD9822B)),
        ];
        final positive = parts.fold<int>(0, (t, x) => t + (x.$2 > 0 ? x.$2 : 0));
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net worth', style: TextStyle(color: p.muted)),
                const SizedBox(height: 2),
                BigAmount(money(w.total, currency), size: 34),
                if (positive > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          for (final x in parts)
                            if (x.$2 > 0)
                              Expanded(
                                flex: (x.$2 * 1000 / positive).round().clamp(1, 1000),
                                child: Container(color: x.$3, margin: const EdgeInsets.only(right: 2)),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final x in parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: x.$3, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            x.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted),
                          ),
                        ),
                        Text(money(x.$2, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Switch for rounding every expense up to the euro and saving the change.
class RoundUpTile extends StatelessWidget {
  const RoundUpTile({super.key, required this.goals});
  final List<SavingsGoal> goals;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final id = int.tryParse(settings.raw(roundUpKey) ?? '');
    final goal = goals.where((g) => g.id == id && !g.archived).firstOrNull;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: CircleAvatar(
          backgroundColor: p.positive,
          child: Icon(Icons.savings_outlined, color: Colors.white),
        ),
        title: const Text('Round-ups'),
        subtitle: Text(
          goal == null ? 'Round each expense up to the euro and save the change' : 'Spare change goes to ${goal.name}',
        ),
        trailing: Switch(
          value: goal != null,
          onChanged: (on) async {
            if (!on) return settings.setRaw(roundUpKey, '');
            final active = goals.where((g) => !g.archived).toList();
            if (active.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Make a savings goal first')));
              return;
            }
            final pick = active.length == 1
                ? active.first
                : await showModalBottomSheet<SavingsGoal>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text('Save the change into', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          for (final g in active) ListTile(title: Text(g.name), onTap: () => Navigator.pop(ctx, g)),
                        ],
                      ),
                    ),
                  );
            if (pick != null) await settings.setRaw(roundUpKey, '${pick.id}');
          },
        ),
      ),
    );
  }
}

/// Which days of the week money goes out, and the places it goes most.
class PatternsCard extends StatelessWidget {
  const PatternsCard({super.key, required this.entries, required this.currency});
  final List<Entry> entries;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final expenses = entries.where((e) => e.kind == EntryKind.expense).toList();
    if (expenses.length < 5) return const SizedBox.shrink();
    final p = Palette.of(context);
    final days = weekdayTotals(expenses);
    final places = topMerchants(expenses);
    final maxDay = days.fold<int>(1, math.max);
    final busiest = days.indexOf(days.reduce(math.max));
    // 5 Jan 2026 is a Monday, so +i gives each weekday's short name in the user's locale.
    String dayName(int i, {bool long = false}) =>
        (long ? DateFormat.EEEE() : DateFormat.E()).format(DateTime(2026, 1, 5 + i));
    return WalletSection(
      title: 'Your patterns',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dayName(busiest, long: true)} is your biggest spending day this month',
              style: TextStyle(color: p.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Tooltip(
                        message: money(days[i], currency),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: math.max(3, 44 * days[i] / maxDay),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: i == busiest ? p.accent : p.accent.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dayName(i),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(fontSize: 12, color: i == busiest ? p.ink : p.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (places.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Where you spend most', style: TextStyle(color: p.muted, fontSize: 13.5)),
              const SizedBox(height: 4),
              for (final m in places)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: p.raised,
                        child: Text(
                          m.name.characters.first.toUpperCase(),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(m.count == 1 ? 'once' : '${m.count} times', style: TextStyle(color: p.muted, fontSize: 13)),
                      const SizedBox(width: 10),
                      Text(money(m.cents, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Pay yourself first": a set amount for a goal each time salary comes in, offered as a one-tap move.
class PaydayTile extends StatelessWidget {
  const PaydayTile({super.key, required this.goals, required this.moves});
  final List<SavingsGoal> goals;
  final List<SavingsMove> moves;

  @override
  Widget build(BuildContext context) {
    final settings = context.settings;
    final db = context.db;
    final now = DateTime.now();
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final p = Palette.of(context);
        final currency = settings.currency;
        final rule = parsePaydayRule(settings.raw(paydayKey));
        final goal = goals.where((g) => g.id == rule?.goalId && !g.archived).firstOrNull;
        return StreamBuilder<List<Entry>>(
          stream: db.watchEntries(addDays(dateOnly(now), -11), addDays(dateOnly(now), 1)),
          builder: (context, snap) {
            final payday = goal == null
                ? null
                : pendingPayday(
                    entries: snap.data ?? const <Entry>[],
                    moves: moves,
                    goalId: goal.id,
                    now: now,
                    skipped: DateTime.tryParse(settings.raw(paydaySkipKey) ?? ''),
                  );
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                    leading: CircleAvatar(
                      backgroundColor: p.positive,
                      child: Icon(Icons.event_repeat_rounded, color: Colors.white),
                    ),
                    title: const Text('Save on payday'),
                    subtitle: Text(
                      goal == null
                          ? 'Put a set amount aside when your salary lands'
                          : '${money(rule!.cents, currency)} into ${goal.name} each payday',
                    ),
                    onTap: goal == null ? null : () => _setUp(context),
                    trailing: Switch(
                      value: goal != null,
                      onChanged: (on) => on ? _setUp(context) : settings.setRaw(paydayKey, ''),
                    ),
                  ),
                  if (payday != null && goal != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Salary came in ${friendlyDay(payday).toLowerCase()}.',
                            style: TextStyle(color: p.muted, fontSize: 13.5),
                          ),
                          FilledButton(
                            onPressed: () async {
                              await db.addMove(goal.id, rule.cents, note: 'Payday');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${money(rule.cents, currency)} put into ${goal.name}')),
                                );
                              }
                            },
                            child: Text('Put ${money(rule!.cents, currency)} aside'),
                          ),
                          TextButton(
                            onPressed: () => settings.setRaw(paydaySkipKey, payday.toIso8601String()),
                            child: const Text('Not this time'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _setUp(BuildContext context) async {
    final settings = context.settings;
    final active = goals.where((g) => !g.archived).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Make a savings goal first')));
      return;
    }
    final rule = parsePaydayRule(settings.raw(paydayKey));
    var goalId = active.any((g) => g.id == rule?.goalId) ? rule!.goalId : active.first.id;
    final amount = TextEditingController(text: rule == null ? '' : moneyInput(rule.cents));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Save on payday'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(hintText: 'Amount', prefixText: '${currencySymbol(settings.currency)} '),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in active)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(g.name),
                      selected: goalId == g.id,
                      onSelected: (_) => setState(() => goalId = g.id),
                    ),
                ],
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
    final cents = parseMoney(amount.text);
    amount.dispose();
    if (ok == true && cents != null && cents > 0) await settings.setRaw(paydayKey, '$goalId:${cents.abs()}');
  }
}
