import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'savings_page.dart' show confirmDelete;
import 'wallet_model.dart';
import 'wallet_page.dart' show EntryTile, editEntry;

const accountColors = [
  0xFF00716B, 0xFF2F55D4, 0xFFB3122E, 0xFF1F1F24, 0xFF7A5BC0, 0xFFCF7A18, 0xFF2F8F5B, 0xFF8A5A44, //
];

bool _onAccount(String entryAccount, Account a) => entryAccount.trim().toLowerCase() == a.name.trim().toLowerCase();

/// What an account holds now, and what moved through it this month.
class AccountState {
  AccountState(this.account, List<Entry> entries, List<Subscription> subs, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final month = DateTime(n.year, n.month);
    balance = account.balanceCents;
    for (final e in entries) {
      final signed = e.kind.sign * e.amountCents;
      if (account.balanceAt != null && e.date.isAfter(account.balanceAt!) && !e.date.isAfter(n)) balance += signed;
      if (!e.date.isBefore(month) && !e.date.isAfter(n)) {
        if (signed > 0) monthIn += signed;
        if (signed < 0) monthOut -= signed;
      }
    }
    recurring = subs.where((s) => s.active && _onAccount(s.account, account)).toList()
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final end = DateTime(n.year, n.month + 1);
    for (final s in recurring) {
      if (s.nextDate.isBefore(end)) dueThisMonth += s.kind.sign * s.amountCents;
      monthly += (s.kind.sign * s.amountCents / s.periodMonths).round();
    }
  }

  final Account account;
  int balance = 0;
  int monthIn = 0;
  int monthOut = 0;
  late final List<Subscription> recurring;

  /// Recurring money still to come in or go out before the month ends.
  int dueThisMonth = 0;

  /// Recurring money per month on this account, in minus out.
  int monthly = 0;

  bool get hasBalance => account.balanceAt != null;
  int get afterBills => balance + dueThisMonth;
}

/// The cards in a row: balance, this month and what is due next on each.
class AccountsStrip extends StatelessWidget {
  const AccountsStrip({super.key, required this.currency});
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
                  child: Row(
                    children: [
                      const Expanded(child: SectionLabel('Accounts')),
                      TextButton.icon(
                        onPressed: () => editAccount(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    // Three side by side when there is room, otherwise swipe through them.
                    final wide = c.maxWidth >= 720;
                    final cardWidth = wide ? (c.maxWidth - 24) / 3 : (c.maxWidth * 0.82).clamp(250.0, 340.0);
                    final cards = [
                      for (final a in accounts)
                        SizedBox(
                          width: cardWidth,
                          child: _AccountEntries(
                            account: a,
                            builder: (entries) =>
                                AccountCard(state: AccountState(a, entries, subs), currency: currency),
                          ),
                        ),
                    ];
                    if (accounts.isEmpty) {
                      return Text('Add your bank cards to see each balance here.', style: TextStyle(color: p.muted));
                    }
                    return SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: cards.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => cards[i],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AccountEntries extends StatelessWidget {
  const _AccountEntries({required this.account, required this.builder});
  final Account account;
  final Widget Function(List<Entry>) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Entry>>(
    stream: context.db.watchAccountEntries(account.name),
    builder: (context, snap) => builder(snap.data ?? const <Entry>[]),
  );
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.state, required this.currency});
  final AccountState state;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final a = state.account;
    final color = Color(a.color);
    const fg = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.78);
    final next = state.recurring.where((s) => s.kind.sign < 0).firstOrNull;
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.35)!],
          ),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountPage(accountId: a.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (a.number.isNotEmpty)
                      Text('•••• ${a.number}', style: TextStyle(color: soft, fontSize: 13.5, letterSpacing: 0.5)),
                  ],
                ),
                const Spacer(),
                if (state.hasBalance) ...[
                  Text('Balance', style: TextStyle(color: soft, fontSize: 13)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      money(state.balance, currency),
                      style: const TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                    ),
                  ),
                ] else
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setAccountBalance(context, a),
                    child: const Text('Set balance'),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _Mini('In', money(state.monthIn, currency), soft)),
                    Expanded(child: _Mini('Out', money(state.monthOut, currency), soft)),
                    Expanded(
                      child: _Mini(
                        next == null ? 'Bills' : 'Next ${DateFormat('d MMM').format(next.nextDate)}',
                        next == null ? 'none' : '${next.name} ${money(next.amountCents, currency)}',
                        soft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.soft);
  final String label;
  final String value;
  final Color soft;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: soft, fontSize: 12),
      ),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

/// One account: balance, what is due, the recurring payments on it and every entry.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.accountId});
  final int accountId;

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    final currency = context.settings.currency;
    return StreamBuilder<List<Account>>(
      stream: db.watchAccounts(),
      builder: (context, snap) {
        final a = (snap.data ?? const <Account>[]).where((x) => x.id == accountId).firstOrNull;
        if (a == null) return Scaffold(appBar: AppBar());
        return StreamBuilder<List<Subscription>>(
          stream: db.watchSubscriptions(),
          builder: (context, subSnap) {
            final subs = subSnap.data ?? const <Subscription>[];
            return _AccountEntries(
              account: a,
              builder: (entries) {
                final s = AccountState(a, entries, subs);
                return Scaffold(
                  appBar: AppBar(
                    title: Text(a.name),
                    actions: [
                      IconButton(
                        tooltip: 'Edit card',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => editAccount(context, account: a),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  floatingActionButton: FloatingActionButton.extended(
                    heroTag: 'account-add',
                    onPressed: () => editEntry(context, account: a.name),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                  body: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    children: [
                      ContentWidth(
                        child: SizedBox(
                          height: 196,
                          child: AccountCard(state: s, currency: currency),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ContentWidth(
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => setAccountBalance(context, a),
                                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                                label: const Text('Set current balance'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (s.hasBalance) ...[
                        const SizedBox(height: 8),
                        ContentWidth(
                          child: Text(
                            'Set ${relativeTime(a.balanceAt!)}. Entries on ${a.name} since then are counted in. '
                            '${s.dueThisMonth != 0 ? 'After this month\'s recurring payments: ${money(s.afterBills, currency)}.' : ''}',
                            style: TextStyle(color: p.muted, fontSize: 13.5),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ContentWidth(
                        child: Section(
                          title: 'Paid from this card',
                          trailing: TextButton(
                            onPressed: () => _assignRecurring(context, a, subs),
                            child: const Text('Choose'),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                if (s.recurring.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: Text(
                                      'Pick which of your recurring payments and income go through ${a.name}.',
                                      style: TextStyle(color: p.muted),
                                    ),
                                  ),
                                for (final r in s.recurring)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                      categoryInfo(r.category).icon,
                                      color: categoryInfo(r.category).color,
                                      size: 20,
                                    ),
                                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    subtitle: Text('${periodLabel(r.periodMonths)} · next ${friendlyDay(r.nextDate)}'),
                                    trailing: Text(
                                      money(r.kind.sign * r.amountCents, currency, signed: true),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: r.kind.sign > 0 ? p.positive : p.ink,
                                      ),
                                    ),
                                  ),
                                if (s.recurring.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text('Per month', style: TextStyle(color: p.muted)),
                                        ),
                                        Text(
                                          money(s.monthly, currency, signed: true),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ContentWidth(
                        child: Section(
                          title: 'Activity',
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                if (entries.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: Text(
                                      'Nothing booked on ${a.name} yet. Entries whose account is "${a.name}" show up here, '
                                      'including bank imports and recurring payments.',
                                      style: TextStyle(color: p.muted),
                                    ),
                                  ),
                                for (final e in entries.take(60)) EntryTile(entry: e, currency: currency),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _assignRecurring(BuildContext context, Account a, List<Subscription> subs) async {
    final db = context.db;
    final chosen = {
      for (final s in subs)
        if (_onAccount(s.account, a)) s.id,
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Paid through ${a.name}', style: Theme.of(context).textTheme.titleMedium),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in subs)
                        CheckboxListTile(
                          value: chosen.contains(s.id),
                          title: Text(s.name),
                          subtitle: Text(
                            [
                              money(s.kind.sign * s.amountCents, context.settings.currency, signed: true),
                              if (s.account.isNotEmpty && !_onAccount(s.account, a)) 'now on ${s.account}',
                            ].join(' · '),
                          ),
                          onChanged: (v) => setState(() => v == true ? chosen.add(s.id) : chosen.remove(s.id)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    for (final s in subs) {
      final on = _onAccount(s.account, a);
      if (chosen.contains(s.id) && !on) await db.setSubscriptionAccount(s.id, a.name);
      if (!chosen.contains(s.id) && on) await db.setSubscriptionAccount(s.id, '');
    }
  }
}

/// Asks what is in the account right now.
Future<void> setAccountBalance(BuildContext context, Account a) async {
  final db = context.db;
  final c = TextEditingController(text: a.balanceAt == null ? '' : (a.balanceCents / 100).toStringAsFixed(2));
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${a.name} balance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What your banking app shows right now.', style: TextStyle(color: Palette.of(context).muted)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(prefixText: '${currencySymbol(context.settings.currency)} '),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ),
  );
  final cents = parseMoney(c.text);
  if (ok == true && cents != null) await db.setAccountBalance(a.id, cents);
}

Future<void> editAccount(BuildContext context, {Account? account}) async {
  final db = context.db;
  final name = TextEditingController(text: account?.name ?? '');
  final number = TextEditingController(text: account?.number ?? '');
  var color = account?.color ?? accountColors[3];
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(account == null ? 'New card' : 'Edit card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: account == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. ING'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: number,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Last 4 digits (optional)', counterText: ''),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in accountColors)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(c),
                      child: color == c ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (account != null)
            TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (result == 'delete' && account != null && context.mounted) {
    if (await confirmDelete(context, 'Remove ${account.name}? Its entries stay in your wallet.')) {
      await db.deleteAccount(account.id);
    }
    return;
  }
  final n = name.text.trim();
  if (result != 'save' || n.isEmpty) return;
  if (account != null && account.name != n) {
    // Keep entries and recurring payments on the renamed card.
    await db.customStatement('UPDATE entries SET account = ? WHERE lower(account) = lower(?)', [n, account.name]);
    await db.customStatement('UPDATE subscriptions SET account = ? WHERE lower(account) = lower(?)', [n, account.name]);
  }
  await db.saveAccount(
    AccountsCompanion(
      id: account == null ? const Value.absent() : Value(account.id),
      name: Value(n),
      color: Value(color),
      number: Value(number.text.trim()),
      balanceCents: Value(account?.balanceCents ?? 0),
      balanceAt: Value(account?.balanceAt),
      position: Value(account?.position ?? 99),
    ),
  );
}

/// Quick-pick chips under an "Account" field.
class AccountChips extends StatelessWidget {
  const AccountChips({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Account>>(
    stream: context.db.watchAccounts(),
    builder: (context, snap) {
      final list = snap.data ?? const <Account>[];
      if (list.isEmpty) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in list)
                ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(radius: 5, backgroundColor: Color(a.color)),
                  label: Text(a.name),
                  selected: _onAccount(controller.text, a),
                  onSelected: (v) {
                    controller.text = v ? a.name : '';
                    onChanged?.call();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
