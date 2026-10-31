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
import '../ai/ask_agent.dart';
import 'accounts_page.dart';
import 'bank_import.dart';
import 'insights.dart';
import 'investing_page.dart';
import 'month_bar.dart' show pickMonth;
import 'pace_card.dart';
import 'savings_page.dart';
import 'year_page.dart';
import 'subscriptions_page.dart';
import 'wallet_logic.dart';
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
    final p = Palette.of(context);
    // Spending has its own round Add button at the top of the page.
    final fab = switch (_tabs.index) {
      0 => null,
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
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 72,
        leading: canPop
            ? Center(
                child: _RoundButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        title: const Text('Wallet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            style: IconButton.styleFrom(backgroundColor: p.surface, fixedSize: const Size(48, 48)),
            icon: Icon(Icons.more_horiz_rounded, color: p.ink),
            onSelected: (v) {
              if (v == 'recurring') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage()));
              }
              if (v == 'import') importBankFile(context);
              if (v == 'banks') showBankHelp(context);
              if (v == 'year') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YearPage()));
              if (v == 'export') exportEntries(context);
              if (v == 'budget') editSpendTarget(context);
              if (v == 'ai') openAgentWith(context, AgentPrompts.explainMonth);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ai', child: Text('Explain my month')),
              PopupMenuItem(value: 'recurring', child: Text('Recurring payments')),
              PopupMenuItem(value: 'budget', child: Text('Monthly budget')),
              PopupMenuItem(value: 'year', child: Text('Year overview and taxes')),
              PopupMenuItem(value: 'import', child: Text('Import bank export')),
              PopupMenuItem(value: 'export', child: Text('Export to CSV')),
              PopupMenuItem(value: 'banks', child: Text('Linking your banks')),
            ],
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(16) + 44),
          child: _PillTabs(controller: _tabs, labels: const ['Spending', 'Savings', 'Investing']),
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

/// Shrinks a little while pressed, then springs back, so taps feel physical.
class _Press extends StatefulWidget {
  const _Press({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A round, flat button on the raised surface: back, menu, previous and next month.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        excludeSemantics: true,
        child: _Press(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: onTap == null ? p.muted.withValues(alpha: 0.5) : p.ink),
          ),
        ),
      ),
    );
  }
}

/// Spending / Savings / Investing as large pills; the chosen one is solid ink.
class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.controller, required this.labels});
  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: controller.index == i,
                button: true,
                child: _Press(
                  onTap: () => controller.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: controller.index == i ? p.ink : p.surface,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: controller.index == i ? p.background : p.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
  bool _searching = false;
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  Widget _searchField(Palette p) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: TextField(
      controller: _search,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search notes, categories or amounts',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(tooltip: 'Close search', icon: const Icon(Icons.close_rounded), onPressed: _closeSearch),
      ),
    ),
  );

  DateTime get _latest => DateTime(DateTime.now().year, DateTime.now().month + 12);

  void _go(DateTime m) {
    final target = DateTime(m.year, m.month);
    if (target.isAfter(_latest)) return;
    setState(() => _month = target);
  }

  /// Big month name with round previous / next buttons; tapping the name opens the month picker.
  Widget _monthRow(Palette p, bool isCurrent) {
    final next = DateTime(_month.year, _month.month + 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _Press(
              onTap: () async {
                final picked = await pickMonth(context, _month, latest: _latest);
                if (picked != null) _go(picked);
              },
              child: Semantics(
                button: true,
                hint: 'Pick a month',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        DateFormat('MMMM y').format(_month),
                        maxLines: 1,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isCurrent)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: p.accent),
              onPressed: () => _go(DateTime(DateTime.now().year, DateTime.now().month)),
              child: const Text('Now'),
            ),
          const SizedBox(width: 4),
          _RoundButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous month',
            onTap: () => _go(DateTime(_month.year, _month.month - 1)),
          ),
          const SizedBox(width: 10),
          _RoundButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next month',
            onTap: next.isAfter(_latest) ? null : () => _go(next),
          ),
        ],
      ),
    );
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
        final query = _search.text;
        final shown = all.where((e) => (_filter == null || e.kind == _filter) && entryMatches(e, query)).toList();
        final p = Palette.of(context);
        final byDay = <DateTime, List<Entry>>{};
        for (final e in shown) {
          (byDay[dateOnly(e.date)] ??= []).add(e);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
        Widget block(Widget child, {double bottom = 16}) => SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
            child: ContentWidth(child: child),
          ),
        );
        return GestureDetector(
          // Swipe sideways to change month.
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 300) return;
            _go(DateTime(_month.year, _month.month + (v < 0 ? 1 : -1)));
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: ContentWidth(child: _monthRow(p, isCurrent))),
              block(
                _Press(
                  onTap: () => editSpendTarget(context),
                  child: SpendingHero(month: _month, monthEntries: all, currency: currency),
                ),
                bottom: 20,
              ),
              block(const _Actions(), bottom: 20),
              if (isCurrent) block(_AccountsList(currency: currency), bottom: 20),
              block(PaceCard(month: _month, monthEntries: all, currency: currency), bottom: 20),
              block(_InOut(summary: summary, currency: currency)),
              block(_Trend(month: _month, currency: currency, onPick: _go)),
              if (isCurrent) block(_Upcoming(currency: currency)),
              block(_Breakdown(summary: summary, month: _month, currency: currency)),
              block(InsightsCard(month: _month, thisMonth: summary.byCategory, currency: currency)),
              block(PatternsCard(entries: all, currency: currency)),
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
                    child: Text(
                      'Entries',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: p.ink),
                    ),
                  ),
                ),
              ),
              if (_searching) SliverToBoxAdapter(child: ContentWidth(child: _searchField(p))),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ContentWidth(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (!_searching)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(Icons.search_rounded, size: 18),
                              label: const Text('Search'),
                              onPressed: () => setState(() => _searching = true),
                            ),
                          ),
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
                    title: query.trim().isNotEmpty ? 'No matches' : 'No entries',
                    message: all.isEmpty
                        ? 'Add an expense, or import a CSV from Revolut, ABN AMRO or Eurobank.'
                        : query.trim().isNotEmpty
                        ? 'Nothing this month matches "${query.trim()}". Try another month or a shorter word.'
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
                        padding: EdgeInsets.fromLTRB(16, 6, 16, i == days.length - 1 ? 40 : 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      friendlyDay(d),
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                                    ),
                                  ),
                                  Text(
                                    money(dayTotal, currency, signed: true),
                                    style: TextStyle(fontSize: 14, color: p.muted),
                                  ),
                                ],
                              ),
                            ),
                            Material(
                              color: p.surface,
                              borderRadius: BorderRadius.circular(24),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var j = 0; j < list.length; j++) ...[
                                    if (j > 0) const Divider(indent: 68),
                                    _SwipeToDelete(
                                      entry: list[j],
                                      child: EntryTile(entry: list[j], currency: currency),
                                    ),
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

/// Add (solid), Recurring, Year and Import as round buttons with their names underneath.
class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget action(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: _Press(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: primary ? p.ink : p.surface, shape: BoxShape.circle),
                child: Icon(icon, size: 26, color: primary ? p.background : p.ink),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            action(Icons.add_rounded, 'Add', () => editEntry(context), primary: true),
            action(
              Icons.autorenew_rounded,
              'Recurring',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
            ),
            action(
              Icons.bar_chart_rounded,
              'Year',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YearPage())),
            ),
            action(Icons.file_download_outlined, 'Import', () => importBankFile(context)),
          ],
        ),
      ),
    );
  }
}

/// Every account in one card: bank circle, name, what is next on it, and the balance.
class _AccountsList extends StatelessWidget {
  const _AccountsList({required this.currency});
  final String currency;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    return StreamBuilder<List<Account>>(
      stream: db.watchAccounts(),
      builder: (context, snap) {
        final accounts = snap.data ?? const <Account>[];
        return StreamBuilder<List<Subscription>>(
          stream: db.watchSubscriptions(),
          builder: (context, subSnap) {
            final subs = subSnap.data ?? const <Subscription>[];
            return WalletSection(
              title: 'Accounts',
              trailing: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: p.accent,
                  minimumSize: const Size(44, 44),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onPressed: () => editAccount(context),
                child: const Text('Add account'),
              ),
              child: accounts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text('Add your bank cards to see each balance here.', style: TextStyle(color: p.muted)),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < accounts.length; i++) ...[
                          if (i > 0) const Divider(indent: 76),
                          StreamBuilder<List<Entry>>(
                            stream: db.watchAccountEntries(accounts[i].name),
                            builder: (context, e) => _AccountRow(
                              state: AccountState(accounts[i], e.data ?? const <Entry>[], subs),
                              first: i == 0,
                              currency: currency,
                            ),
                          ),
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.state, required this.first, required this.currency});
  final AccountState state;
  final bool first;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = state.account;
    final next = state.recurring.where((s) => s.kind.sign < 0).firstOrNull;
    final sub = next != null
        ? '${next.name} ${money(next.amountCents, currency)} on ${DateFormat('d MMM').format(next.nextDate)}'
        : a.number.isNotEmpty
        ? 'Card •••• ${a.number}'
        : first
        ? 'Main account'
        : 'Account';
    final initial = a.name.trim().isEmpty ? '?' : a.name.trim().characters.first.toUpperCase();
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountPage(accountId: a.id))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Color(a.color), shape: BoxShape.circle),
              child: Text(
                initial,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: state.hasBalance
                    ? Text(
                        money(state.balance, currency),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : Text(
                        'Set balance',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.accent),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Money in and out this month, side by side.
class _InOut extends StatelessWidget {
  const _InOut({required this.summary, required this.currency});
  final MonthSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 14),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        Expanded(child: stat('Money in', money(summary.income, currency), p.positive)),
        const SizedBox(width: 12),
        Expanded(child: stat('Money out', money(summary.out, currency), p.ink)),
      ],
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
        return WalletSection(
          title: 'Spending, last 6 months',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  // Bars plus two labels that grow with the text size.
                  height: 76 + MediaQuery.textScalerOf(context).scale(38),
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
                                    color: m == month ? p.accent : p.accent.withValues(alpha: 0.28),
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
    return StreamBuilder<List<Subscription>>(
      stream: context.db.watchSubscriptions(),
      builder: (context, snap) {
        final due = billCalendar(snap.data ?? const <Subscription>[], DateTime.now());
        if (due.isEmpty) return const SizedBox.shrink();
        final total = due.fold<int>(0, (t, b) => t + b.sub.kind.sign * b.sub.amountCents);
        return WalletSection(
          title: 'Next 30 days',
          trailing: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(money(total, currency, signed: true), style: TextStyle(color: p.muted, fontSize: 13.5)),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final b in due.take(6))
                  ListTile(
                    dense: true,
                    leading: Icon(
                      categoryInfo(b.sub.category).icon,
                      color: categoryInfo(b.sub.category).color,
                      size: 20,
                    ),
                    title: Text(
                      b.sub.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(friendlyDay(b.date)),
                    trailing: Text(
                      money(b.sub.kind.sign * b.sub.amountCents, currency, signed: true),
                      style: TextStyle(fontWeight: FontWeight.w600, color: b.sub.kind.sign > 0 ? p.positive : p.ink),
                    ),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                  ),
                if (due.length > 6)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                    child: Text('See all ${due.length}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary, required this.month, required this.currency});
  final MonthSummary summary;
  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<Budget>>(
      stream: context.db.watchBudgets(),
      builder: (context, snap) {
        final budgets = {for (final b in snap.data ?? const <Budget>[]) b.category: b.monthlyCents};
        if (summary.out == 0 && budgets.isEmpty) return const SizedBox.shrink();
        final spent = {...summary.byCategory, for (final k in budgets.keys) k: summary.byCategory[k] ?? 0};
        final cats = spent.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final now = DateTime.now();
        final status = {
          for (final k in budgets.keys) k: budgetStatus(spent: spent[k]!, budget: budgets[k]!, month: month, now: now),
        };
        final overCount = status.values.where((s) => s.state == BudgetState.over).length;
        final watchCount = status.values.where((s) => s.state == BudgetState.watch).length;
        // Budgeted categories first so their progress is easy to find, then the rest by size.
        final ordered = [
          ...cats.where((c) => budgets.containsKey(c.key)),
          ...cats.where((c) => !budgets.containsKey(c.key) && c.value > 0).take(8),
        ];
        return WalletSection(
          title: 'Where it went',
          trailing: budgets.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _StatusPill(
                    text: overCount > 0
                        ? '$overCount over'
                        : watchCount > 0
                        ? '$watchCount ahead of pace'
                        : 'Budgets on track',
                    color: overCount > 0
                        ? p.danger
                        : watchCount > 0
                        ? _amber
                        : p.positive,
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                if (summary.out > 0) ...[
                  // Stacked bar of the month's outgoings.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final c in cats.where((c) => c.value > 0))
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
                ],
                for (final c in ordered)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editBudget(context, c.key, budgets[c.key]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: status[c.key] == null
                          ? Row(
                              children: [
                                Icon(categoryInfo(c.key).icon, size: 18, color: categoryInfo(c.key).color),
                                const SizedBox(width: 10),
                                Expanded(child: Text(c.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(money(c.value, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            )
                          : _BudgetRow(category: c.key, status: status[c.key]!, currency: currency),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    budgets.isEmpty ? 'Tap a category to set a monthly budget' : 'Tap a category to change its budget',
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
    final c = TextEditingController(text: current == null ? '' : moneyInput(current));
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
    c.dispose();
    if (v == null) return;
    final cents = parseMoney(v);
    // Typos like "abc" or "-50" must not wipe a budget; only an empty field removes it.
    if (v.trim().isNotEmpty && (cents == null || cents <= 0)) return;
    await db.setBudget(category, cents);
  }
}

/// Amber for "ahead of pace": a heads-up, not yet a problem.
const _amber = Color(0xFFE08A1E);

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 160),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// A budgeted category: spent against budget, where an even pace would be today, and a plain verdict.
class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.category, required this.status, required this.currency});
  final String category;
  final BudgetStatus status;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final info = categoryInfo(category);
    final color = switch (status.state) {
      BudgetState.over => p.danger,
      BudgetState.watch => _amber,
      BudgetState.onTrack => p.positive,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(info.icon, size: 18, color: info.color),
            const SizedBox(width: 10),
            Expanded(child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            _StatusPill(text: status.label, color: color),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 8),
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: status.fraction,
                    backgroundColor: p.raised,
                    color: status.state == BudgetState.over ? p.danger : info.color,
                  ),
                ),
                // Where spending would be today at an even pace.
                if (status.paceFraction < 1)
                  Positioned(
                    left: (box.maxWidth * status.paceFraction - 1).clamp(0, box.maxWidth - 2).toDouble(),
                    top: -2,
                    child: Container(width: 2, height: 11, color: p.ink.withValues(alpha: 0.6)),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 6),
          child: Text(
            status.left >= 0
                ? '${money(status.spent, currency)} of ${money(status.budget, currency)} · ${money(status.left, currency)} left'
                : '${money(status.spent, currency)} of ${money(status.budget, currency)} · ${money(-status.left, currency)} over',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ),
      ],
    );
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: info.color, shape: BoxShape.circle),
        child: Icon(info.icon, size: 20, color: Colors.white),
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

/// Swipe an entry left to delete it, with a moment to undo.
class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({required this.entry, required this.child});
  final Entry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: p.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        final db = context.db;
        db.deleteEntry(entry.id);
        final label = entry.note.isEmpty ? entry.category : entry.note;
        showUndo(context, '$label deleted', () => db.restoreEntry(entry));
      },
      child: child,
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
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_amount.text)?.abs();
    if (cents == null || cents == 0 || _saving) return;
    // A second tap while saving would book the entry (and its round-up) twice.
    _saving = true;
    final db = context.db;
    final roundUp = context.settings.raw(roundUpKey);
    final companion = EntriesCompanion(
      amountCents: Value(cents),
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
          amountCents: cents,
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
            PillToggle<EntryKind>(
              dense: true,
              options: [
                for (final k in [EntryKind.expense, EntryKind.subscription, EntryKind.income, EntryKind.tax])
                  (k, k == EntryKind.subscription ? 'Sub' : k.label),
              ],
              value: _kind == EntryKind.transfer ? EntryKind.expense : _kind,
              onChanged: (k) => setState(() {
                _kind = k;
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
                    final first = DateTime(2000);
                    final last = addDays(DateTime.now(), 365);
                    // An imported entry can sit outside the range, which the picker does not allow.
                    final initial = _date.isBefore(first) ? first : (_date.isAfter(last) ? last : _date);
                    final d = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: _date.isBefore(first) ? DateTime(_date.year) : first,
                      lastDate: last,
                    );
                    if (!mounted) return;
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
