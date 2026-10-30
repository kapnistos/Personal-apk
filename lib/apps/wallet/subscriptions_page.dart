import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'accounts_page.dart';
import 'wallet_model.dart';

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = context.settings.currency;
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(
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
      body: StreamBuilder<List<Subscription>>(
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
          final outPerMonth = active.where((s) => s.kind.sign < 0).fold<int>(0, (t, s) => t + monthlyCents(s));
          final inPerMonth = active.where((s) => s.kind.sign > 0).fold<int>(0, (t, s) => t + monthlyCents(s));
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
                            return Opacity(
                              opacity: s.active ? 1 : 0.5,
                              child: ListTile(
                                onTap: () => _edit(context, s),
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: info.color.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(info.icon, size: 20, color: info.color),
                                ),
                                title: Text(s.name),
                                subtitle: Text(
                                  s.active
                                      ? '${periodLabel(s.periodMonths)} · next ${friendlyDay(s.nextDate)}'
                                      : 'Paused',
                                  style: TextStyle(color: p.muted, fontSize: 13.5),
                                ),
                                trailing: Text(
                                  money(s.kind.sign * s.amountCents, currency, signed: true),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: s.kind.sign > 0 ? p.positive : p.ink,
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

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_amount.text);
    if (_name.text.trim().isEmpty || cents == null || cents == 0) return;
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
            SegmentedButton<EntryKind>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: EntryKind.subscription, label: Text('Payment')),
                ButtonSegment(value: EntryKind.tax, label: Text('Tax')),
                ButtonSegment(value: EntryKind.income, label: Text('Income')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
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
                    for (final m in [1, 3, 6, 12]) DropdownMenuItem(value: m, child: Text(periodLabel(m))),
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
                      initialDate: _next,
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
