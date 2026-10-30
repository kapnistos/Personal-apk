import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'insights.dart';

const goalColors = [0xFF1F7A5A, 0xFF3A78C9, 0xFFCF9418, 0xFFB5487A, 0xFF6650AE, 0xFF2D8C9E, 0xFFC0563F];

/// Months left until [deadline], counting the current one.
int monthsLeft(DateTime deadline, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return math.max(1, (deadline.year - n.year) * 12 + deadline.month - n.month + (deadline.day >= n.day ? 1 : 0));
}

class SavingsTab extends StatelessWidget {
  const SavingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final currency = context.settings.currency;
    final p = Palette.of(context);
    return StreamBuilder<List<SavingsGoal>>(
      stream: db.watchGoals(),
      builder: (context, gSnap) => StreamBuilder<List<SavingsMove>>(
        stream: db.watchMoves(),
        builder: (context, mSnap) {
          final goals = gSnap.data ?? const <SavingsGoal>[];
          final moves = mSnap.data ?? const <SavingsMove>[];
          final saved = <int, int>{};
          for (final m in moves) {
            saved[m.goalId] = (saved[m.goalId] ?? 0) + m.amountCents;
          }
          final total = saved.values.fold<int>(0, (a, b) => a + b);
          final now = DateTime.now();
          final thisMonth = moves
              .where((m) => m.date.year == now.year && m.date.month == now.month)
              .fold<int>(0, (a, m) => a + m.amountCents);
          final active = goals.where((g) => !g.archived).toList();
          final archived = goals.where((g) => g.archived).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              ContentWidth(child: NetWorthCard(currency: currency)),
              const SizedBox(height: 12),
              ContentWidth(
                child: _TotalCard(
                  label: 'Saved in total',
                  value: money(total, currency),
                  footer: thisMonth == 0
                      ? 'Nothing put aside yet this month'
                      : '${money(thisMonth, currency, signed: true)} this month',
                  color: const Color(0xFF1F7A5A),
                ),
              ),
              const SizedBox(height: 12),
              ContentWidth(child: RoundUpTile(goals: goals)),
              const SizedBox(height: 12),
              ContentWidth(
                child: PaydayTile(goals: goals, moves: moves),
              ),
              const SizedBox(height: 12),
              if (goals.isEmpty)
                const EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'No savings goals yet',
                  message: 'Make a goal like "Emergency fund" or "Summer trip" and track what you put aside.',
                ),
              for (final g in active)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GoalCard(goal: g, saved: saved[g.id] ?? 0, currency: currency),
                  ),
                ),
              if (archived.isNotEmpty) ...[
                const ContentWidth(
                  child: Padding(padding: EdgeInsets.fromLTRB(4, 10, 4, 8), child: SectionLabel('Reached or put away')),
                ),
                for (final g in archived)
                  ContentWidth(
                    child: Card(
                      child: ListTile(
                        leading: Icon(Icons.check_circle_rounded, color: Color(g.color)),
                        title: Text(g.name),
                        subtitle: Text(money(saved[g.id] ?? 0, currency), style: TextStyle(color: p.muted)),
                        onTap: () => showGoal(context, g),
                      ),
                    ),
                  ),
              ],
              if (moves.isNotEmpty) ...[
                const ContentWidth(
                  child: Padding(padding: EdgeInsets.fromLTRB(4, 14, 4, 8), child: SectionLabel('Latest moves')),
                ),
                ContentWidth(
                  child: Card(
                    child: Column(
                      children: [
                        for (final m in moves.take(8))
                          ListTile(
                            dense: true,
                            leading: Icon(
                              m.amountCents >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                              size: 18,
                              color: m.amountCents >= 0 ? p.positive : p.danger,
                            ),
                            title: Text(goals.where((g) => g.id == m.goalId).firstOrNull?.name ?? 'Goal'),
                            subtitle: Text([friendlyDay(m.date), if (m.note.isNotEmpty) m.note].join(' · ')),
                            trailing: Text(
                              money(m.amountCents, currency, signed: true),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.value, required this.footer, required this.color});
  final String label;
  final String value;
  final String footer;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          BigAmount(value, size: 38, color: Colors.white),
          const SizedBox(height: 6),
          Text(footer, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, required this.saved, required this.currency});
  final SavingsGoal goal;
  final int saved;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = Color(goal.color);
    final ratio = goal.targetCents <= 0 ? 0.0 : (saved / goal.targetCents).clamp(0.0, 1.0);
    final left = goal.targetCents - saved;
    String? pace;
    if (goal.deadline != null && left > 0) {
      final months = monthsLeft(goal.deadline!);
      pace =
          '${money((left / months).ceil(), currency)} a month to reach it by ${DateFormat('MMM y').format(goal.deadline!)}';
    }
    return Press(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showGoal(context, goal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(goal.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      '${(ratio * 100).round()}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: ratio, minHeight: 10, color: color, backgroundColor: p.raised),
                ),
                const SizedBox(height: 8),
                Text(
                  '${money(saved, currency)} of ${money(goal.targetCents, currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (left <= 0)
                  Text('Goal reached', style: TextStyle(color: p.positive, fontSize: 14))
                else if (pace != null)
                  Text(pace, style: TextStyle(color: p.muted, fontSize: 14)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => moveMoney(context, goal, deposit: true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add money'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: saved > 0 ? () => moveMoney(context, goal, deposit: false) : null,
                      child: const Text('Take out'),
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

Future<void> moveMoney(BuildContext context, SavingsGoal goal, {required bool deposit}) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  final db = context.db;
  final currency = context.settings.currency;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(deposit ? 'Add to ${goal.name}' : 'Take from ${goal.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount', prefixText: '${currencySymbol(currency)} '),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(deposit ? 'Add' : 'Take out')),
      ],
    ),
  );
  final cents = parseMoney(amount.text);
  if (ok == true && cents != null && cents > 0) {
    await db.addMove(goal.id, deposit ? cents : -cents, note: note.text.trim());
  }
}

void showGoal(BuildContext context, SavingsGoal goal) {
  final db = context.db;
  final currency = context.settings.currency;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Hub(
      db: db,
      settings: context.settings,
      child: StreamBuilder<List<SavingsMove>>(
        stream: db.watchMoves(),
        builder: (sheet, snap) {
          final moves = (snap.data ?? const <SavingsMove>[]).where((m) => m.goalId == goal.id).toList();
          final p = Palette.of(sheet);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(goal.name, style: Theme.of(sheet).textTheme.titleLarge)),
                    IconButton(
                      tooltip: 'Edit goal',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {
                        Navigator.pop(sheet);
                        editGoal(context, goal: goal);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (moves.isEmpty) Text('No money moved yet.', style: TextStyle(color: p.muted)),
                for (final m in moves)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(money(m.amountCents, currency, signed: true)),
                    subtitle: Text([DateFormat('d MMM y').format(m.date), if (m.note.isNotEmpty) m.note].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => db.deleteMove(m.id),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> editGoal(BuildContext context, {SavingsGoal? goal}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Hub(
      db: context.db,
      settings: context.settings,
      child: _GoalEditor(goal: goal),
    ),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.goal});
  final SavingsGoal? goal;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : (widget.goal!.targetCents / 100).toStringAsFixed(2).replaceAll('.00', ''),
  );
  late DateTime? _deadline = widget.goal?.deadline;
  late int _color = widget.goal?.color ?? goalColors.first;
  late bool _archived = widget.goal?.archived ?? false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_target.text);
    if (_name.text.trim().isEmpty || cents == null || cents <= 0) return;
    await context.db.saveGoal(
      SavingsGoalsCompanion(
        id: widget.goal == null ? const Value.absent() : Value(widget.goal!.id),
        name: Value(_name.text.trim()),
        targetCents: Value(cents),
        deadline: Value(_deadline),
        color: Value(_color),
        archived: Value(_archived),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = context.settings.currency;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.goal == null ? 'New savings goal' : 'Edit goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.goal == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Emergency fund'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Target', prefixText: '${currencySymbol(currency)} '),
          ),
          const SizedBox(height: 10),
          InputChip(
            avatar: Icon(Icons.flag_outlined, size: 18, color: p.muted),
            label: Text(_deadline == null ? 'No deadline' : 'By ${DateFormat('d MMM y').format(_deadline!)}'),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _deadline ?? DateTime(now.year + 1, now.month, 1),
                firstDate: now,
                lastDate: DateTime(now.year + 30),
              );
              if (d != null) setState(() => _deadline = d);
            },
            onDeleted: _deadline == null ? null : () => setState(() => _deadline = null),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (final c in goalColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(c),
                    child: _color == c ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                ),
            ],
          ),
          if (widget.goal != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reached or put away'),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.goal != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  onPressed: () async {
                    final yes = await confirmDelete(context, 'Delete "${widget.goal!.name}" and its history?');
                    if (!yes || !context.mounted) return;
                    await context.db.deleteGoal(widget.goal!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;
