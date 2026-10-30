import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import 'insights.dart';
import 'wallet_model.dart';

/// "Day by day": a strip of every day of the month (what went out, the no-spend days, the even daily
/// allowance) over plain rows that say whether the month is on track: safe to spend today, where the
/// month is heading, bills still to come and the no-spend days.
class PaceCard extends StatelessWidget {
  const PaceCard({super.key, required this.month, required this.monthEntries, required this.currency});
  final DateTime month;
  final List<Entry> monthEntries;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    if (month.isAfter(current)) return const SizedBox.shrink();
    final target = int.tryParse(context.settings.raw(spendTargetKey) ?? '');
    final hasTarget = target != null && target > 0;
    final days = MonthDays.of(monthEntries, month, now);
    if (month != current) {
      if (monthEntries.isEmpty) return const SizedBox.shrink();
      return _past(context, days, hasTarget ? target : null);
    }
    // A brand-new month with nothing in it and no budget: the hero already offers to set one.
    if (!hasTarget && monthEntries.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<Subscription>>(
      stream: context.db.watchSubscriptions(),
      builder: (context, snap) {
        final bills = billsLeftThisMonth(snap.data ?? const <Subscription>[], now);
        final spent = MonthSummary(monthEntries.where((e) => !e.date.isAfter(now)).toList()).out;
        final plan = SpendPlan(
          target: hasTarget ? target : 0,
          spent: spent,
          billsAhead: bills.cents,
          billsPaid: fixedCostsBooked(monthEntries, now),
          now: now,
        );
        return _current(context, days, plan, bills, hasTarget);
      },
    );
  }

  Widget _current(
    BuildContext context,
    MonthDays days,
    SpendPlan plan,
    ({int cents, int count}) bills,
    bool hasTarget,
  ) {
    final p = Palette.of(context);
    final amber = paceAmber(context);
    final end = DateFormat('d MMM').format(days.lastDay);
    final rows = <Widget>[];
    if (hasTarget) {
      final todaySpent = days.everyday[days.daysSoFar - 1];
      final safe = safeToSpend(plan, todaySpent);
      final lastDay = plan.daysLeft <= 1;
      rows.add(
        plan.over
            ? _PaceRow(
                icon: Icons.today_rounded,
                title: 'Safe to spend today',
                subtitle: 'Budget used up, ${money(-plan.left, currency)} over',
                subtitleColor: p.danger,
                value: money(0, currency),
              )
            : safe.today < 0
            ? _PaceRow(
                icon: Icons.today_rounded,
                title: 'Safe to spend today',
                subtitle: lastDay
                    ? '${money(-safe.today, currency)} past today\'s share'
                    : '${money(-safe.today, currency)} past today\'s share · then ${money(safe.after, currency)} a day',
                subtitleColor: amber,
                value: money(0, currency),
              )
            : _PaceRow(
                icon: Icons.today_rounded,
                title: 'Safe to spend today',
                subtitle: lastDay
                    ? 'Last day of the month'
                    : plan.daysLeft == 2
                    ? '${money(safe.after, currency)} for tomorrow, the last day'
                    : 'Then ${money(safe.after, currency)} a day for ${_days(plan.daysLeft - 1)}',
                value: money(safe.today, currency),
              ),
      );
      final diff = plan.projectedLeft;
      rows.add(
        _PaceRow(
          icon: Icons.trending_up_rounded,
          title: 'Projected by $end',
          subtitle: diff.abs() < paceTolerance(plan.target)
              ? 'Right on your budget'
              : diff > 0
              ? '${money(diff, currency)} under budget'
              : '${money(-diff, currency)} over budget',
          subtitleColor: diff >= 0 || diff.abs() < paceTolerance(plan.target)
              ? p.positive
              : plan.over
              ? p.danger
              : amber,
          value: money(plan.projected, currency),
        ),
      );
    } else {
      rows.add(
        _PaceRow(
          icon: Icons.trending_up_rounded,
          title: 'Projected by $end',
          subtitle: 'At this month\'s pace, bills included',
          value: money(plan.projected, currency),
        ),
      );
    }
    if (bills.count > 0) {
      rows.add(
        _PaceRow(
          icon: Icons.autorenew_rounded,
          title: 'Bills still to come',
          subtitle: '${bills.count} ${bills.count == 1 ? 'payment' : 'payments'} by $end, already set aside',
          value: money(bills.cents, currency),
        ),
      );
    }
    rows.add(_noSpendRow(context, days));
    if (!hasTarget) {
      rows.add(
        _PaceRow(
          icon: Icons.flag_outlined,
          title: 'Set a monthly budget',
          subtitle: 'See each day whether you\'re on track',
          trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
          onTap: () => editSpendTarget(context),
        ),
      );
    }
    return _shell(context, days, hasTarget ? plan.dailyAllowance : null, rows);
  }

  Widget _past(BuildContext context, MonthDays days, int? target) {
    final p = Palette.of(context);
    final s = MonthSummary(monthEntries);
    final rows = <Widget>[
      if (target != null)
        _PaceRow(
          icon: Icons.flag_outlined,
          title: 'Spent in ${DateFormat.MMMM().format(month)}',
          subtitle: s.out <= target
              ? '${money(target - s.out, currency)} under budget'
              : '${money(s.out - target, currency)} over budget',
          subtitleColor: s.out <= target ? p.positive : p.danger,
          value: money(s.out, currency),
        ),
      _PaceRow(
        icon: Icons.calendar_view_day_rounded,
        title: 'Average day',
        subtitle: 'Everyday spending, bills left out',
        value: money((days.spent / days.daysInMonth).round(), currency),
      ),
      _noSpendRow(context, days),
    ];
    final fixed = fixedCostsBooked(monthEntries, addDays(days.lastDay, 1));
    final allowance = target == null ? null : (math.max(0, target - fixed) / days.daysInMonth).floor();
    return _shell(context, days, allowance, rows);
  }

  Widget _noSpendRow(BuildContext context, MonthDays days) {
    final n = days.noSpend;
    final run = days.currentRun >= 2 ? days.currentRun : 0;
    return _PaceRow(
      icon: Icons.eco_outlined,
      title: 'No-spend days',
      subtitle: n == 0
          ? 'Every day so far had spending'
          : run > 0 && days.daysSoFar < days.daysInMonth
          ? '$run in a row now · best run ${_days(days.longestRun)}'
          : 'Best run ${_days(days.longestRun)}',
      value: '$n',
      valueColor: n > 0 ? Palette.of(context).positive : null,
    );
  }

  Widget _shell(BuildContext context, MonthDays days, int? allowance, List<Widget> rows) {
    return WalletSection(
      title: 'Day by day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: DayStrip(days: days, allowance: allowance, currency: currency),
          ),
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(indent: 70), rows[i]],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// One line of the card: a grey circle with an icon, a title over a short verdict, and a figure.
class _PaceRow extends StatelessWidget {
  const _PaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final valueText = value == null
        ? null
        : Text(
            value!,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? p.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
      child: LayoutBuilder(
        builder: (context, box) {
          // With large text on a narrow phone the figure moves under the title instead of squeezing it.
          final stacked = box.maxWidth - 54 < MediaQuery.textScalerOf(context).scale(16) * 14;
          final titleText = Text(
            title,
            maxLines: stacked ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
          );
          final subtitleText = Text(
            subtitle,
            maxLines: stacked ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: subtitleColor ?? p.muted,
              fontWeight: subtitleColor == null ? FontWeight.w400 : FontWeight.w500,
            ),
          );
          return Row(
            crossAxisAlignment: stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: p.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleText,
                    if (stacked && valueText != null)
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: valueText),
                    const SizedBox(height: 1),
                    subtitleText,
                  ],
                ),
              ),
              if (!stacked && valueText != null) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: valueText),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          );
        },
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// Every day of the month as a thin bar of what went out, a green dot for a day with no spending, and
/// a faint dot for days still to come. Today is drawn in ink. A dashed line marks the even everyday
/// allowance when there is a budget.
class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.days, required this.allowance, required this.currency});
  final MonthDays days;
  final int? allowance;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final small = TextStyle(color: p.muted, fontSize: 13.5);
    final limit = allowance != null && allowance! > 0 ? allowance : null;
    final over = limit == null ? 0 : days.everyday.take(days.daysSoFar).where((c) => c > limit).length;
    final isRunning = days.daysSoFar > 0 && days.daysSoFar < days.daysInMonth;
    return Semantics(
      label:
          '${days.noSpend} no-spend days so far'
          '${limit == null ? '' : ', $over days above ${money(limit, currency)}, the even daily share'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 76,
            child: CustomPaint(
              painter: DayStripPainter(
                values: days.everyday,
                daysSoFar: days.daysSoFar,
                today: isRunning ? days.daysSoFar - 1 : null,
                allowance: limit,
                bar: p.accent,
                todayColor: p.ink,
                free: p.positive,
                future: p.muted.withValues(alpha: 0.4),
                guide: p.muted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(DateFormat('d MMM').format(days.month), style: small),
              const Spacer(),
              Text(DateFormat('d MMM').format(days.lastDay), style: small),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Key(color: p.positive, label: 'No spend', shape: _KeyShape.dot),
              _Key(color: p.accent, label: 'Spent', shape: _KeyShape.bar),
              if (limit != null)
                _Key(color: p.muted, label: '${moneyWhole(limit, currency)} a day', shape: _KeyShape.dash),
            ],
          ),
        ],
      ),
    );
  }
}

enum _KeyShape { dot, bar, dash }

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, required this.shape});
  final Color color;
  final String label;
  final _KeyShape shape;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      switch (shape) {
        _KeyShape.dot => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        _KeyShape.bar => Container(
          width: 5,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        _KeyShape.dash => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(width: 4, height: 1.5, margin: const EdgeInsets.only(right: 2), color: color),
          ],
        ),
      },
      const SizedBox(width: 7),
      Text(label, style: TextStyle(color: Palette.of(context).muted, fontSize: 13.5)),
    ],
  );
}

class DayStripPainter extends CustomPainter {
  DayStripPainter({
    required this.values,
    required this.daysSoFar,
    required this.today,
    required this.allowance,
    required this.bar,
    required this.todayColor,
    required this.free,
    required this.future,
    required this.guide,
  });
  final List<int> values;
  final int daysSoFar;
  final int? today;
  final int? allowance;
  final Color bar;
  final Color todayColor;
  final Color free;
  final Color future;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final col = size.width / n;
    final barW = math.min(col * 0.58, 9.0);
    const dotR = 3.0;
    final base = size.height;
    const top = 4.0;
    final biggest = values.fold<int>(0, math.max);
    final yMax = math.max(math.max(biggest, (allowance ?? 0) * 1.6), 1).toDouble();
    double h(int v) => math.max(barW, (base - top) * v / yMax);

    for (var i = 0; i < n; i++) {
      final cx = col * (i + 0.5);
      final dot = Offset(cx, base - dotR - 2);
      if (i >= daysSoFar) {
        canvas.drawCircle(dot, 1.6, Paint()..color = future);
        continue;
      }
      final v = values[i];
      if (v == 0) {
        canvas.drawCircle(dot, dotR, Paint()..color = free);
        // Today, still clean: a ring in ink around the green dot.
        if (i == today) {
          canvas.drawCircle(
            dot,
            dotR + 2.2,
            Paint()
              ..color = todayColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
        continue;
      }
      final r = Rect.fromLTRB(cx - barW / 2, base - h(v), cx + barW / 2, base);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(barW / 2)),
        Paint()..color = i == today ? todayColor : bar,
      );
    }

    if (allowance != null) {
      final y = base - (base - top) * allowance! / yMax;
      final paint = Paint()
        ..color = guide.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DayStripPainter old) =>
      old.values != values ||
      old.daysSoFar != daysSoFar ||
      old.today != today ||
      old.allowance != allowance ||
      old.bar != bar ||
      old.todayColor != todayColor ||
      old.free != free ||
      old.future != future ||
      old.guide != guide;
}
