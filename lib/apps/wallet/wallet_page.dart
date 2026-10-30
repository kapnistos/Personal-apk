import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'accounts_page.dart';
import 'bank_import.dart';
import 'insights.dart';
import 'investing_page.dart';
import 'month_bar.dart';
import 'savings_page.dart';
import 'year_page.dart';
import 'subscriptions_page.dart';
import 'wallet_model.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fab = switch (_tabs.index) {
      0 => FloatingActionButton.extended(
        heroTag: 'wallet-add',
        onPressed: () => editEntry(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      1 => FloatingActionButton.extended(
        heroTag: 'wallet-goal',
        onPressed: () => editGoal(context),
        icon: const Icon(Icons.savings_outlined),
        label: const Text('New goal'),
      ),
      _ => FloatingActionButton.extended(
        heroTag: 'wallet-holding',
        onPressed: () => editHolding(context),
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Add holding'),
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(
            tooltip: 'Subscriptions',
            icon: const Icon(Icons.autorenew_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') importBankFile(context);
              if (v == 'banks') showBankHelp(context);
              if (v == 'year') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YearPage()));
              if (v == 'export') exportEntries(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'year', child: Text('Year overview and taxes')),
              PopupMenuItem(value: 'import', child: Text('Import bank export')),
              PopupMenuItem(value: 'export', child: Text('Export to CSV')),
              PopupMenuItem(value: 'banks', child: Text('Linking your banks')),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          controller: _tabs,
          tabs: const [
            Tab(text: 'Spending'),
            Tab(text: 'Savings'),
            Tab(text: 'Investing'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        // Sideways swipes inside Spending change the month, so tabs change by tapping.
        physics: const NeverScrollableScrollPhysics(),
        children: const [_SpendingTab(), SavingsTab(), InvestingTab()],
      ),
    );
  }
}

class _SpendingTab extends StatefulWidget {
  const _SpendingTab();

  @override
  State<_SpendingTab> createState() => _SpendingTabState();
}

class _SpendingTabState extends State<_SpendingTab> with AutomaticKeepAliveClientMixin {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  EntryKind? _filter;

  @override
  bool get wantKeepAlive => true;

  void _go(DateTime m) {
    final latest = DateTime(DateTime.now().year, DateTime.now().month + 12);
    final target = DateTime(m.year, m.month);
    if (target.isAfter(latest)) return;
    setState(() => _month = target);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final db = context.db;
    final currency = context.settings.currency;
    final next = DateTime(_month.year, _month.month + 1);
    final isCurrent = _month == DateTime(DateTime.now().year, DateTime.now().month);
    return StreamBuilder<List<Entry>>(
      stream: db.watchEntries(_month, next),
      builder: (context, snap) {
        // While the new month loads, the old month's rows must not show under the new title.
        final all = (snap.data ?? const <Entry>[])
            .where((e) => !e.date.isBefore(_month) && e.date.isBefore(next))
            .toList();
        final summary = MonthSummary(all);
        final shown = _filter == null ? all : all.where((e) => e.kind == _filter).toList();
        final byDay = <DateTime, List<Entry>>{};
        for (final e in shown) {
          (byDay[dateOnly(e.date)] ??= []).add(e);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
        return GestureDetector(
          // Swipe sideways to change month.
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 300) return;
            _go(DateTime(_month.year, _month.month + (v < 0 ? 1 : -1)));
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: ContentWidth(
                    child: MonthBar(
                      month: _month,
                      onChanged: _go,
                      latest: DateTime(DateTime.now().year, DateTime.now().month + 12),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: ContentWidth(
                    child: _SummaryCard(summary: summary, currency: currency),
                  ),
                ),
              ),
              if (isCurrent)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ContentWidth(child: LeftToSpendCard(monthEntries: all, currency: currency)),
                  ),
                ),
              if (isCurrent)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: ContentWidth(child: AccountsStrip(currency: currency)),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ContentWidth(
                    child: _Trend(month: _month, currency: currency, onPick: _go),
                  ),
                ),
              ),
              if (isCurrent)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ContentWidth(child: _Upcoming(currency: currency)),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ContentWidth(
                    child: _Breakdown(summary: summary, currency: currency),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ContentWidth(
                    child: InsightsCard(month: _month, thisMonth: summary.byCategory, currency: currency),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ContentWidth(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final k in [
                          null,
                          EntryKind.expense,
                          EntryKind.subscription,
                          EntryKind.income,
                          EntryKind.tax,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              label: Text(k == null ? 'All' : k.label),
                              selected: _filter == k,
                              onSelected: (_) => setState(() => _filter = k),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (days.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No entries',
                    message: all.isEmpty
                        ? 'Add an expense, or import a CSV from Revolut, ABN AMRO or Eurobank.'
                        : 'Nothing of this type this month.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: days.length,
                  itemBuilder: (context, i) {
                    final d = days[i];
                    final list = byDay[d]!;
                    final dayTotal = list.fold<int>(0, (s, e) => s + e.kind.sign * e.amountCents);
                    return ContentWidth(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, i == days.length - 1 ? 96 : 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                              child: Row(
                                children: [
                                  Expanded(child: SectionLabel(friendlyDay(d))),
                                  Text(
                                    money(dayTotal, currency, signed: true),
                                    style: TextStyle(fontSize: 13, color: Palette.of(context).muted),
                                  ),
                                ],
                              ),
                            ),
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var j = 0; j < list.length; j++) ...[
                                    if (j > 0) const Divider(indent: 64),
                                    EntryTile(entry: list[j], currency: currency),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Six months of spending, so a month can be judged against the ones before.
class _Trend extends StatelessWidget {
  const _Trend({required this.month, required this.currency, required this.onPick});
  final DateTime month;
  final String currency;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final first = DateTime(month.year, month.month - 5);
    final end = DateTime(month.year, month.month + 1);
    return StreamBuilder<List<Entry>>(
      stream: context.db.watchEntries(first, end),
      builder: (context, snap) {
        final months = [for (var i = 0; i < 6; i++) DateTime(first.year, first.month + i)];
        final out = {for (final m in months) m: 0};
        for (final e in snap.data ?? const <Entry>[]) {
          if (e.kind.sign >= 0) continue;
          final k = DateTime(e.date.year, e.date.month);
          if (out.containsKey(k)) out[k] = out[k]! + e.amountCents;
        }
        final maxV = out.values.fold<int>(1, math.max);
        // Compare with the other months that have spending, not with itself.
        final others = [
          for (final e in out.entries)
            if (e.key != month && e.value > 0) e.value,
        ];
        final avg = others.isEmpty ? 0.0 : others.fold<int>(0, (a, b) => a + b) / others.length;
        return Section(
          title: 'Spending, last 6 months',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 116,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final m in months)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onPick(m),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (m == month && out[m]! > 0)
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      NumberFormat.compactSimpleCurrency(name: currency).format(out[m]! / 100),
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  height: math.max(3, 64 * out[m]! / maxV),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: m == month ? TileColors.finance : TileColors.finance.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat.MMM().format(m),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: m == month ? p.ink : p.muted,
                                    fontWeight: m == month ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (avg > 0 && out[month]! > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    (out[month]! / avg - 1).abs() < 0.03
                        ? 'About the same as your average month'
                        : out[month]! > avg
                        ? '${((out[month]! / avg - 1) * 100).round()}% above your average month'
                        : '${((1 - out[month]! / avg) * 100).round()}% below your average month',
                    style: TextStyle(color: p.muted, fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Recurring payments and income due in the next 30 days.
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.currency});
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final limit = DateTime.now().add(const Duration(days: 30));
    return StreamBuilder<List<Subscription>>(
      stream: context.db.watchSubscriptions(),
      builder: (context, snap) {
        final due = (snap.data ?? const <Subscription>[]).where((s) => s.active && s.nextDate.isBefore(limit)).toList()
          ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
        if (due.isEmpty) return const SizedBox.shrink();
        final total = due.fold<int>(0, (t, s) => t + s.kind.sign * s.amountCents);
        return Section(
          title: 'Next 30 days',
          trailing: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(money(total, currency, signed: true), style: TextStyle(color: p.muted, fontSize: 13.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final s in due.take(6))
                  ListTile(
                    dense: true,
                    leading: Icon(categoryInfo(s.category).icon, color: categoryInfo(s.category).color, size: 20),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(friendlyDay(s.nextDate)),
                    trailing: Text(
                      money(s.kind.sign * s.amountCents, currency, signed: true),
                      style: TextStyle(fontWeight: FontWeight.w600, color: s.kind.sign > 0 ? p.positive : p.ink),
                    ),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.currency});
  final MonthSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        Text('Net this month', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        BigAmount(money(summary.net, currency, signed: true), size: 44),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _action(context, Icons.add_rounded, 'Add', () => editEntry(context)),
            _action(
              context,
              Icons.autorenew_rounded,
              'Recurring',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
            ),
            _action(
              context,
              Icons.bar_chart_rounded,
              'Year',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YearPage())),
            ),
            _action(context, Icons.file_download_outlined, 'Import', () => importBankFile(context)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _stat(p, Icons.south_west_rounded, 'In', money(summary.income, currency), p.positive)),
            const SizedBox(width: 10),
            Expanded(child: _stat(p, Icons.north_east_rounded, 'Out', money(summary.out, currency), p.ink)),
          ],
        ),
      ],
    );
  }

  /// A round action button with its name underneath.
  Widget _action(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Material(
            color: p.raised,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 52, height: 52, child: Icon(icon, color: p.ink)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _stat(Palette p, IconData icon, String label, String value, Color color) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
    child: Row(
      children: [
        Icon(icon, size: 18, color: p.muted),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary, required this.currency});
  final MonthSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (summary.out == 0) return const SizedBox.shrink();
    final cats = summary.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return StreamBuilder<List<Budget>>(
      stream: context.db.watchBudgets(),
      builder: (context, snap) {
        final budgets = {for (final b in snap.data ?? const <Budget>[]) b.category: b.monthlyCents};
        return Section(
          title: 'Where it went',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              children: [
                // Stacked bar of the month's outgoings.
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final c in cats)
                          Expanded(
                            flex: math.max(1, (c.value * 1000 / summary.out).round()),
                            child: Container(
                              color: categoryInfo(c.key).color,
                              margin: const EdgeInsets.only(right: 1.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final c in cats.take(8))
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editBudget(context, c.key, budgets[c.key]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(categoryInfo(c.key).icon, size: 18, color: categoryInfo(c.key).color),
                              const SizedBox(width: 10),
                              Expanded(child: Text(c.key)),
                              if (budgets[c.key] != null)
                                Text(
                                  '${money(c.value, currency)} of ${money(budgets[c.key]!, currency)}',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: c.value > budgets[c.key]! ? p.danger : p.muted,
                                  ),
                                )
                              else
                                Text(money(c.value, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          if (budgets[c.key] != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 28, top: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  minHeight: 5,
                                  value: (c.value / budgets[c.key]!).clamp(0, 1).toDouble(),
                                  backgroundColor: p.raised,
                                  color: c.value > budgets[c.key]! ? p.danger : categoryInfo(c.key).color,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tap a category to set a monthly budget',
                    style: TextStyle(fontSize: 12.5, color: p.muted),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editBudget(BuildContext context, String category, int? current) async {
    final c = TextEditingController(text: current == null ? '' : (current / 100).toStringAsFixed(0));
    final db = context.db;
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Budget for $category'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: 'Per month, empty for none', suffixText: currency),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await db.setBudget(category, parseMoney(v));
  }
}

class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.currency});
  final Entry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final info = categoryInfo(entry.category);
    final sign = entry.kind.sign;
    return ListTile(
      onTap: () => editEntry(context, entry: entry),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: info.color.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Icon(info.icon, size: 20, color: info.color),
      ),
      title: Text(entry.note.isEmpty ? entry.category : entry.note, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (entry.note.isNotEmpty) entry.category,
          if (entry.kind != EntryKind.expense) entry.kind.label,
          if (entry.account.isNotEmpty) entry.account,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.muted, fontSize: 13.5),
      ),
      trailing: Text(
        money(sign * entry.amountCents, currency, signed: sign != 0),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: sign > 0 ? p.positive : p.ink,
        ),
      ),
    );
  }
}

Future<void> editEntry(BuildContext context, {Entry? entry, String? account}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EntryEditor(entry: entry, account: account),
  );
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({this.entry, this.account});
  final Entry? entry;
  final String? account;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late EntryKind _kind = widget.entry?.kind ?? EntryKind.expense;
  late String _category = widget.entry?.category ?? categoriesByKind[_kind]!.first.name;
  late final _amount = TextEditingController(
    text: widget.entry == null ? '' : (widget.entry!.amountCents / 100).toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late final _account = TextEditingController(text: widget.entry?.account ?? widget.account ?? '');
  late DateTime _date = widget.entry?.date ?? DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_amount.text);
    if (cents == null || cents == 0) return;
    final db = context.db;
    final roundUp = context.settings.raw(roundUpKey);
    final companion = EntriesCompanion(
      amountCents: Value(cents.abs()),
      kind: Value(_kind),
      category: Value(_category),
      note: Value(_note.text.trim()),
      account: Value(_account.text.trim()),
      date: Value(_date),
    );
    if (widget.entry == null) {
      await db.addEntry(companion);
      if (_kind == EntryKind.expense) {
        final label = _note.text.trim().isEmpty ? _category : _note.text.trim();
        await applyRoundUp(db, roundUp, cents, label);
      }
    } else {
      await db.updateEntry(
        widget.entry!.copyWith(
          amountCents: cents.abs(),
          kind: _kind,
          category: _category,
          note: _note.text.trim(),
          account: _account.text.trim(),
          date: _date,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cats = categoriesByKind[_kind]!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<EntryKind>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: [
                for (final k in [EntryKind.expense, EntryKind.subscription, EntryKind.income, EntryKind.tax])
                  ButtonSegment(value: k, label: Text(k == EntryKind.subscription ? 'Sub' : k.label)),
              ],
              selected: {_kind == EntryKind.transfer ? EntryKind.expense : _kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _category = categoriesByKind[_kind]!.first.name;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: widget.entry == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${NumberFormat.simpleCurrency(name: context.settings.currency).currencySymbol} ',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(c.icon, size: 17, color: _category == c.name ? p.onAccent : c.color),
                    label: Text(c.name),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Note (shop, who, what)'),
            ),
            AccountChips(controller: _account),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _account,
                    decoration: const InputDecoration(hintText: 'Account (e.g. Revolut)'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(friendlyDay(_date)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.entry != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: () {
                      final db = context.db;
                      final e = widget.entry!;
                      db.deleteEntry(e.id);
                      Navigator.pop(context);
                      showUndo(context, 'Entry deleted', () => db.restoreEntry(e));
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(widget.entry == null ? 'Add' : 'Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> importBankFile(BuildContext context) async {
  final db = context.db;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tab']);
  final file = picked.firstOrNull;
  if (file == null) return;

  ImportResult result;
  try {
    final text = _decode(await file.xFile.readAsBytes());
    result = parseBankExport(text, fileName: file.name);
  } on ImportException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  if (result.rows.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('No completed transactions in that file.')));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Import from ${result.format}?'),
      content: Text(
        '${result.rows.length} transactions from '
        '${DateFormat('d MMM y').format(result.rows.map((r) => r.date).reduce((a, b) => a.isBefore(b) ? a : b))} to '
        '${DateFormat('d MMM y').format(result.rows.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b))}. '
        'Ones already imported are skipped. Categories are guessed; tap an entry to fix it.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Import')),
      ],
    ),
  );
  if (ok != true) return;
  await db.insertEntries([
    for (final r in result.rows)
      EntriesCompanion.insert(
        amountCents: r.amountCents.abs(),
        kind: r.kind,
        category: r.category,
        note: Value(r.description),
        account: Value(r.account),
        date: r.date,
        importKey: Value(r.key),
      ),
  ]);
  messenger.showSnackBar(SnackBar(content: Text('Imported from ${result.format}')));
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Older bank exports are often Windows-1252 / Latin-1.
    return latin1.decode(bytes);
  }
}

void showBankHelp(BuildContext context) {
  final p = Palette.of(context);
  Widget bank(String name, String how) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(how, style: TextStyle(color: p.muted, height: 1.4)),
      ],
    ),
  );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Linking your banks', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            bank(
              'Revolut',
              'In the Revolut app: Account → Statement → Excel/CSV, pick the months, share the file to this phone or PC, then Import here.',
            ),
            bank('ABN AMRO', 'In Internet Banking: Download transactions → format TXT. Import the .TXT file here.'),
            bank(
              'Eurobank',
              'In e-Banking: open the account, Transactions → Export (Excel/CSV). Save as CSV and import it here.',
            ),
            const SizedBox(height: 4),
            Text(
              'Automatic sync is planned through Enable Banking, an EU open-banking service with a free mode for your own accounts. '
              'It needs a small always-on server for the bank login redirect, which your laptop server will provide.',
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
            ),
          ],
        ),
      ),
    ),
  );
}
