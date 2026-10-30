import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'accounts_page.dart';
import 'wallet_logic.dart';
import 'wallet_model.dart';

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = context.settings.currency;
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(
        title: const Text('Recurring'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) async {
              final messenger = ScaffoldMessenger.of(context);
              final n = await context.db.restoreRecurring();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(n == 0 ? 'All your usual payments are already here' : 'Added $n missing payments'),
                ),
              );
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'restore', child: Text('Add back my usual list'))],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      // Rebuilds when a cancel reminder is set or cleared.
      body: ListenableBuilder(
        listenable: context.settings,
        builder: (context, _) => StreamBuilder<List<Subscription>>(
          stream: context.db.watchSubscriptions(),
          builder: (context, snap) {
            final subs = snap.data ?? const <Subscription>[];
            if (subs.isEmpty) {
              return const EmptyState(
                icon: Icons.autorenew_rounded,
                title: 'No recurring items',
                message: 'Add rent, Netflix, insurance or your salary. Hub books each payment on its date.',
              );
            }
            final active = subs.where((s) => s.active);
            final now = DateTime.now();
            final bills = billCalendar(subs, now);
            final outPerMonth = active.where((s) => s.kind.sign < 0).fold<int>(0, (t, s) => t + monthlyCents(s));
            final inPerMonth = active.where((s) => s.kind.sign > 0).fold<int>(0, (t, s) => t + monthlyCents(s));
            return StreamBuilder<List<Entry>>(
              stream: context.db.watchEntries(addMonths(dateOnly(now), -13), addDays(dateOnly(now), 1)),
              builder: (context, booked) {
                final history = <int, List<Entry>>{};
                for (final e in booked.data ?? const <Entry>[]) {
                  if (e.subscriptionId != null) (history[e.subscriptionId!] ??= []).add(e);
                }
                final changes = {for (final s in subs) s.id: ?priceChangeOf(s.amountCents, history[s.id] ?? const [])};
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    ContentWidth(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Fixed costs per month', style: TextStyle(color: p.muted, fontSize: 13.5)),
                                    BigAmount(money(outPerMonth, currency), size: 30),
                                  ],
                                ),
                              ),
                              if (inPerMonth > 0)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Recurring income', style: TextStyle(color: p.muted, fontSize: 13.5)),
                                    Text(
                                      money(inPerMonth, currency),
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.positive),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (bills.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ContentWidth(
                        child: _BillStrip(bills: bills, currency: currency),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ContentWidth(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < subs.length; i++) ...[
                              if (i > 0) const Divider(indent: 64),
                              Builder(
                                builder: (context) {
                                  final s = subs[i];
                                  final info = categoryInfo(s.category);
                                  final change = changes[s.id];
                                  final cancelBy = DateTime.tryParse(
                                    context.settings.raw('$cancelReminderKey${s.id}') ?? '',
                                  );
                                  return Opacity(
                                    opacity: s.active ? 1 : 0.5,
                                    child: Press(
                                      child: ListTile(
                                        onTap: () => _edit(context, s),
                                        leading: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(color: info.color, shape: BoxShape.circle),
                                          child: Icon(info.icon, size: 20, color: Colors.white),
                                        ),
                                        title: Text(s.name),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.active
                                                  ? '${periodLabel(s.periodMonths)} · next ${friendlyDay(s.nextDate)}'
                                                  : 'Paused',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: p.muted, fontSize: 13.5),
                                            ),
                                            if (change != null && s.active)
                                              Text(
                                                change.up
                                                    ? 'Went up by ${money(change.diff, currency)} (was ${money(change.before, currency)})'
                                                    : 'Went down by ${money(-change.diff, currency)} (was ${money(change.before, currency)})',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: change.up == (s.kind.sign < 0) ? p.danger : p.positive,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            if (cancelBy != null && s.active)
                                              Text(
                                                'Cancel by ${friendlyDay(cancelBy)}',
                                                style: TextStyle(
                                                  color: p.danger,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: Text(
                                          money(s.kind.sign * s.amountCents, currency, signed: true),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: s.kind.sign > 0 ? p.positive : p.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Subscription? s) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubscriptionEditor(sub: s),
    );
  }
}

class _SubscriptionEditor extends StatefulWidget {
  const _SubscriptionEditor({this.sub});
  final Subscription? sub;

  @override
  State<_SubscriptionEditor> createState() => _SubscriptionEditorState();
}

class _SubscriptionEditorState extends State<_SubscriptionEditor> {
  late final _name = TextEditingController(text: widget.sub?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.sub == null ? '' : (widget.sub!.amountCents / 100).toStringAsFixed(2),
  );
  late final _account = TextEditingController(text: widget.sub?.account ?? '');
  late EntryKind _kind = widget.sub?.kind ?? EntryKind.subscription;
  late String _category = widget.sub?.category ?? categoriesByKind[_kind]!.first.name;
  late int _period = widget.sub?.periodMonths ?? 1;
  late DateTime _next = widget.sub?.nextDate ?? addDays(dateOnly(DateTime.now()), 1);
  late bool _active = widget.sub?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_amount.text);
    if (_name.text.trim().isEmpty || cents == null || cents == 0 || _saving) return;
    _saving = true;
    await context.db.saveSubscription(
      SubscriptionsCompanion(
        id: widget.sub == null ? const Value.absent() : Value(widget.sub!.id),
        name: Value(_name.text.trim()),
        amountCents: Value(cents.abs()),
        kind: Value(_kind),
        category: Value(_category),
        account: Value(_account.text.trim()),
        periodMonths: Value(_period),
        nextDate: Value(_next),
        active: Value(_active),
      ),
    );
    if (!mounted) return;
    await context.db.bookDueSubscriptions();
    if (mounted) Navigator.pop(context);
  }

  /// Thinking of cancelling? Adds a to-do with a reminder a few days before the next payment.
  Widget _cancelReminder(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final key = '$cancelReminderKey${widget.sub!.id}';
    final set = DateTime.tryParse(settings.raw(key) ?? '');
    if (set != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.alarm_on_rounded, color: p.danger),
        title: Text('Cancel by ${friendlyDay(set)}'),
        subtitle: const Text('It is on your to-do list'),
        trailing: TextButton(
          onPressed: () async {
            await settings.setRaw(key, '');
            if (mounted) setState(() {});
          },
          child: const Text('Clear'),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final s = widget.sub!;
          final messenger = ScaffoldMessenger.of(context);
          final now = DateTime.now();
          final due = addDays(dateOnly(s.nextDate), -1);
          var remind = DateTime(due.year, due.month, due.day - 2, 9);
          if (remind.isBefore(now)) remind = now.add(const Duration(hours: 1));
          await context.db.addTodo('Cancel ${s.name}', due: due, remindAt: remind, important: true);
          await settings.setRaw(key, due.toIso8601String());
          messenger.showSnackBar(
            SnackBar(content: Text('Added to your to-dos. Hub will remind you on ${friendlyDay(remind)}.')),
          );
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.alarm_add_rounded, size: 18),
        label: const Text('Remind me to cancel'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillToggle<EntryKind>(
              dense: true,
              options: const [
                (EntryKind.subscription, 'Payment'),
                (EntryKind.tax, 'Tax'),
                (EntryKind.income, 'Income'),
              ],
              value: _kind,
              onChanged: (k) => setState(() {
                _kind = k;
                _category = categoriesByKind[_kind]!.first.name;
              }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: widget.sub == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Name (e.g. Netflix, Rent)'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Amount',
                      prefixText: '${NumberFormat.simpleCurrency(name: context.settings.currency).currencySymbol} ',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _period,
                  underline: const SizedBox.shrink(),
                  items: [
                    // Imported or synced payments can repeat every 2 or 4 months; the list must hold them.
                    for (final m in {1, 3, 6, 12, _period}.toList()..sort())
                      DropdownMenuItem(value: m, child: Text(periodLabel(m))),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categoriesByKind[_kind]!)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(c.icon, size: 17, color: _category == c.name ? p.onAccent : c.color),
                    label: Text(c.name),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AccountChips(controller: _account),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _account,
                    decoration: const InputDecoration(hintText: 'Account'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _next.isBefore(DateTime(2000)) || _next.isAfter(DateTime(2100))
                          ? DateTime.now()
                          : _next,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _next = d);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('Next ${DateFormat('d MMM').format(_next)}'),
                ),
              ],
            ),
            if (widget.sub != null && _kind != EntryKind.income) _cancelReminder(context),
            if (widget.sub != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.sub != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: () async {
                      await context.db.deleteSubscription(widget.sub!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(widget.sub == null ? 'Add' : 'Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The next 30 days of bills as a row of day cards, Revolut style.
class _BillStrip extends StatelessWidget {
  const _BillStrip({required this.bills, required this.currency});
  final List<BillDay> bills;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final byDay = <DateTime, List<BillDay>>{};
    for (final b in bills) {
      (byDay[b.date] ??= []).add(b);
    }
    final out = bills.where((b) => b.sub.kind.sign < 0).fold<int>(0, (t, b) => t + b.sub.amountCents);
    return GroupSection(
      title: 'Coming up',
      trailing: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${money(out, currency)} in 30 days', style: TextStyle(color: p.muted, fontSize: 13)),
          ),
        ),
      ),
      child: SizedBox(
        // Grows with the text size so the day tiles never overflow.
        height: 32 + MediaQuery.textScalerOf(context).scale(86),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
          children: [
            for (final d in byDay.keys)
              Tooltip(
                message: byDay[d]!.map((b) => b.sub.name).join(', '),
                child: Container(
                  width: 84,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.E().format(d),
                        style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Text('${d.day}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15)),
                      const Spacer(),
                      Text(
                        byDay[d]!.length == 1 ? byDay[d]!.first.sub.name : '${byDay[d]!.length} payments',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11.5),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(
                            byDay[d]!.fold<int>(0, (t, b) => t + b.sub.kind.sign * b.sub.amountCents),
                            currency,
                            signed: true,
                          ),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
