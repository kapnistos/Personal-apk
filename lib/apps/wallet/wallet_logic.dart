import '../../core/db/database.dart';
import '../../core/format.dart';
import 'wallet_model.dart';

/// Raw settings key prefix for "remind me to cancel" flags, followed by the subscription id.
const cancelReminderKey = 'wallet.cancel.';

enum BudgetState { onTrack, watch, over }

/// How one category is doing against its monthly budget.
class BudgetStatus {
  const BudgetStatus({required this.spent, required this.budget, required this.state, required this.expected});
  final int spent;
  final int budget;
  final BudgetState state;

  /// What an even pace would have spent by the end of today (the whole budget for past months).
  final int expected;

  int get left => budget - spent;
  double get fraction => budget <= 0 ? 1 : (spent / budget).clamp(0, 1).toDouble();
  double get paceFraction => budget <= 0 ? 1 : (expected / budget).clamp(0, 1).toDouble();

  String get label => switch (state) {
    BudgetState.onTrack => 'On track',
    BudgetState.watch => 'Ahead of pace',
    BudgetState.over => 'Over',
  };
}

/// Compares [spent] with [budget] for [month]. In the running month the budget is spread evenly over
/// the days, so spending well ahead of that pace shows up before the budget is actually gone.
BudgetStatus budgetStatus({required int spent, required int budget, required DateTime month, required DateTime now}) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final today = dateOnly(now);
  int expected;
  if (!today.isBefore(end)) {
    expected = budget;
  } else if (today.isBefore(start)) {
    expected = 0;
  } else {
    final days = daysBetween(start, end);
    expected = (budget * (daysBetween(start, today) + 1) / days).round();
  }
  final state = spent > budget
      ? BudgetState.over
      // A little slack so a single grocery run early in the month doesn't raise a flag.
      : spent > expected * 1.15 && spent - expected > 1000
      ? BudgetState.watch
      : BudgetState.onTrack;
  return BudgetStatus(spent: spent, budget: budget, state: state, expected: expected);
}

/// Whether [e] matches a search: words can hit the note, category, account or type, and a number
/// matches the amount ("12", "12.5" and "12,50" all find €12.50).
bool entryMatches(Entry e, String query) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final text = '${e.note} ${e.category} ${e.account} ${e.kind.label}'.toLowerCase();
  for (final w in words) {
    if (text.contains(w)) continue;
    if (RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(w)) {
      final cents = parseMoney(w);
      final hasDecimals = w.contains('.') || w.contains(',');
      if (cents != null && (hasDecimals ? e.amountCents == cents : e.amountCents ~/ 100 == cents ~/ 100)) continue;
    }
    return false;
  }
  return true;
}

/// Everyday spending (expenses only) per weekday, Monday first.
List<int> weekdayTotals(Iterable<Entry> entries) {
  final out = List.filled(7, 0);
  for (final e in entries) {
    if (e.kind != EntryKind.expense) continue;
    out[e.date.weekday - 1] += e.amountCents;
  }
  return out;
}

/// A shop or payee and what went there.
class MerchantTotal {
  const MerchantTotal(this.name, this.cents, this.count);
  final String name;
  final int cents;
  final int count;
}

/// Where everyday spending went, grouped by note (case and spacing ignored), biggest first.
List<MerchantTotal> topMerchants(Iterable<Entry> entries, {int limit = 3}) {
  final cents = <String, int>{};
  final count = <String, int>{};
  final names = <String, String>{};
  for (final e in entries) {
    if (e.kind != EntryKind.expense) continue;
    final name = e.note.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) continue;
    final k = name.toLowerCase();
    names.putIfAbsent(k, () => name);
    cents[k] = (cents[k] ?? 0) + e.amountCents;
    count[k] = (count[k] ?? 0) + 1;
  }
  final list = [for (final k in cents.keys) MerchantTotal(names[k]!, cents[k]!, count[k]!)]
    ..sort((a, b) => b.cents.compareTo(a.cents));
  return list.take(limit).toList();
}

/// A recurring payment whose amount went up or down.
class PriceChange {
  const PriceChange(this.before, this.after);
  final int before;
  final int after;
  int get diff => after - before;
  bool get up => after > before;
}

/// Looks at what a recurring item charged before. [booked] are its booked entries in any order and
/// [current] is the amount set on it now. Returns the latest change, or null when the price held.
PriceChange? priceChangeOf(int current, Iterable<Entry> booked) {
  final list = booked.toList()..sort((a, b) => a.date.compareTo(b.date));
  final amounts = [for (final e in list) e.amountCents, current];
  for (var i = amounts.length - 1; i > 0; i--) {
    if (amounts[i] != amounts[i - 1]) {
      // Only recent news: the change must be in the last two payments or the upcoming one.
      if (i < amounts.length - 2) return null;
      return PriceChange(amounts[i - 1], amounts[i]);
    }
  }
  return null;
}

/// One payment on the bill calendar.
class BillDay {
  const BillDay(this.date, this.sub);
  final DateTime date;
  final Subscription sub;
}

/// Every active recurring payment or income due from [from] for [days] days, repeats included,
/// sorted by date.
List<BillDay> billCalendar(Iterable<Subscription> subs, DateTime from, {int days = 30}) {
  final start = dateOnly(from);
  final end = addDays(start, days);
  final out = <BillDay>[];
  for (final s in subs) {
    if (!s.active) continue;
    var d = s.nextDate;
    for (var i = 0; i < 400 && d.isBefore(end); i++) {
      if (!d.isBefore(start)) out.add(BillDay(dateOnly(d), s));
      d = addMonths(s.nextDate, s.periodMonths * (i + 1));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Raw settings key for the payday rule, stored as "goalId:cents".
const paydayKey = 'wallet.payday';

/// Raw settings key for the payday the user chose to skip.
const paydaySkipKey = 'wallet.payday.skip';

/// The goal and amount to put aside on payday, or null when the rule is off.
({int goalId, int cents})? parsePaydayRule(String? raw) {
  final parts = (raw ?? '').split(':');
  if (parts.length != 2) return null;
  final goal = int.tryParse(parts[0]);
  final cents = int.tryParse(parts[1]);
  if (goal == null || cents == null || cents <= 0) return null;
  return (goalId: goal, cents: cents);
}

/// The day salary last came in, when that was in the last 10 days and nothing went to [goalId]
/// since. Null when there is nothing to suggest.
DateTime? pendingPayday({
  required Iterable<Entry> entries,
  required Iterable<SavingsMove> moves,
  required int goalId,
  required DateTime now,
  DateTime? skipped,
}) {
  final today = dateOnly(now);
  DateTime? payday;
  for (final e in entries) {
    if (e.kind != EntryKind.income || e.category != 'Salary') continue;
    final d = dateOnly(e.date);
    if (d.isAfter(today) || daysBetween(d, today) > 10) continue;
    if (payday == null || d.isAfter(payday)) payday = d;
  }
  if (payday == null) return null;
  if (skipped != null && !dateOnly(skipped).isBefore(payday)) return null;
  final saved = moves.any((m) => m.goalId == goalId && m.amountCents > 0 && !dateOnly(m.date).isBefore(payday!));
  return saved ? null : payday;
}
