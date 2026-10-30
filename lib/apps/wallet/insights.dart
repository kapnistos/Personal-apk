import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'accounts_page.dart' show AccountState;
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

/// "€412 left to spend": the month against a target, with a daily allowance and pace.
class LeftToSpendCard extends StatelessWidget {
  const LeftToSpendCard({super.key, required this.monthEntries, required this.currency});
  final List<Entry> monthEntries;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final target = int.tryParse(settings.raw(spendTargetKey) ?? '');
    if (target == null || target <= 0) {
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          leading: CircleAvatar(
            backgroundColor: p.accent.withValues(alpha: 0.16),
            child: Icon(Icons.flag_outlined, color: p.accent),
          ),
          title: const Text('Set a monthly spending target'),
          subtitle: const Text('See what is left, a daily allowance and whether you are on pace'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => editSpendTarget(context),
        ),
      );
    }
    final now = DateTime.now();
    return StreamBuilder<List<Subscription>>(
      stream: context.db.watchSubscriptions(),
      builder: (context, snap) {
        final end = DateTime(now.year, now.month + 1);
        final today = dateOnly(now);
        final billsAhead = (snap.data ?? const <Subscription>[])
            .where((s) => s.active && s.kind.sign < 0 && !s.nextDate.isBefore(today) && s.nextDate.isBefore(end))
            .fold<int>(0, (t, s) => t + s.amountCents);
        // Booked recurring payments are already entries; count only what hasn't been booked.
        final spent = MonthSummary(monthEntries.where((e) => !e.date.isAfter(now)).toList()).out;
        final plan = SpendPlan(target: target, spent: spent, billsAhead: billsAhead, now: now);
        final free = noSpendDays(monthEntries, now);
        final pace = plan.paceDiff;
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => editSpendTarget(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(plan.over ? 'Over target by' : 'Left to spend', style: TextStyle(color: p.muted)),
                      const Spacer(),
                      Text('of ${money(target, currency)}', style: TextStyle(color: p.muted, fontSize: 13.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  BigAmount(money(plan.left.abs(), currency), size: 34, color: plan.over ? p.danger : null),
                  const SizedBox(height: 12),
                  _PaceBar(used: plan.usedFraction, pace: plan.paceFraction, over: plan.over),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!plan.over && plan.daysLeft > 0)
                        _Pill('${money(plan.perDay, currency)} a day for ${plan.daysLeft} days'),
                      _Pill(
                        pace >= 0 ? '${money(pace, currency)} under pace' : '${money(-pace, currency)} over pace',
                        color: pace >= 0 ? p.positive : p.danger,
                      ),
                      if (billsAhead > 0) _Pill('${money(billsAhead, currency)} in bills to come'),
                      if (free > 0) _Pill('$free no-spend ${free == 1 ? 'day' : 'days'}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PaceBar extends StatelessWidget {
  const _PaceBar({required this.used, required this.pace, required this.over});
  final double used;
  final double pace;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: 14,
        child: Stack(
          children: [
            Positioned.fill(
              top: 3,
              bottom: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Positioned(
              left: 0,
              top: 3,
              bottom: 3,
              width: c.maxWidth * used,
              child: DecoratedBox(
                decoration: BoxDecoration(color: over ? p.danger : p.accent, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            // Today's even-pace mark.
            Positioned(
              left: (c.maxWidth * pace - 1).clamp(0, c.maxWidth - 2),
              top: 0,
              bottom: 0,
              width: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: p.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? p.ink),
      ),
    );
  }
}

Future<void> editSpendTarget(BuildContext context) async {
  final settings = context.settings;
  final current = int.tryParse(settings.raw(spendTargetKey) ?? '');
  final ctrl = TextEditingController(text: current == null ? '' : (current / 100).toStringAsFixed(0));
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
        return Section(
          title: 'Compared with your usual month',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final i in list)
                  ListTile(
                    dense: true,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: categoryInfo(i.category).color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(categoryInfo(i.category).icon, size: 18, color: categoryInfo(i.category).color),
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
                        Text(x.$1, style: TextStyle(color: p.muted)),
                        const Spacer(),
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
          backgroundColor: p.positive.withValues(alpha: 0.16),
          child: Icon(Icons.savings_outlined, color: p.positive),
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
