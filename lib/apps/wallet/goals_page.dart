import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'insights.dart';
import 'savings_page.dart' show GoalTrackLine, goalColors;

/// Icons a purchase goal can wear, by the key stored on the goal.
const purchaseIcons = <String, IconData>{
  'bag': Icons.shopping_bag_outlined,
  'laptop': Icons.laptop_mac_outlined,
  'phone': Icons.smartphone_outlined,
  'headphones': Icons.headphones_outlined,
  'camera': Icons.photo_camera_outlined,
  'game': Icons.sports_esports_outlined,
  'home': Icons.chair_outlined,
  'car': Icons.directions_car_outlined,
  'bike': Icons.pedal_bike_outlined,
  'travel': Icons.flight_outlined,
  'gift': Icons.card_giftcard_outlined,
  'watch': Icons.watch_outlined,
};

IconData purchaseIcon(String key) => purchaseIcons[key] ?? Icons.shopping_bag_outlined;

/// "€140 a month or €33 a week to make it", or null when there is nothing to plan.
String? neededLine(PurchasePlan plan, String currency) {
  if (plan.perMonth == null || plan.perWeek == null) return null;
  final days = plan.daysLeft ?? 0;
  if (days < 14) return 'Put ${money(plan.left, currency)} aside by then to make it';
  return '${money(plan.perMonth!, currency)} a month or ${money(plan.perWeek!, currency)} a week to make it';
}

class GoalsTab extends StatelessWidget {
  const GoalsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final currency = context.settings.currency;
    return StreamBuilder<List<SavingsGoal>>(
      stream: db.watchGoals(),
      builder: (context, gSnap) => StreamBuilder<List<SavingsMove>>(
        stream: db.watchMoves(),
        builder: (context, mSnap) {
          if (!gSnap.hasData || !mSnap.hasData) return const SizedBox.shrink();
          final goals = gSnap.data!.where(isPurchase).toList();
          final moves = mSnap.data!;
          final active = sortPurchaseGoals(goals.where((g) => !g.archived));
          final bought = goals.where((g) => g.archived).toList()
            ..sort((a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt));
          final pad = EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.paddingOf(context).bottom);
          if (goals.isEmpty) {
            return ListView(
              padding: pad,
              children: [
                EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Nothing planned yet',
                  message:
                      'Set a target for something you want to buy, like a new laptop or a trip, '
                      'and put money aside for it bit by bit.',
                ),
              ],
            );
          }
          // Each goal counts up to its price, so one with extra does not hide what another still needs.
          final saved = active.fold(0, (t, g) => t + savedFor(g.id, moves).clamp(0, math.max(0, g.targetCents)));
          final target = active.fold(0, (t, g) => t + g.targetCents);
          return ListView(
            padding: pad,
            children: [
              if (active.isNotEmpty) ...[
                ContentWidth(
                  child: _Summary(saved: saved, target: target, count: active.length, currency: currency),
                ),
                const SizedBox(height: 12),
              ],
              for (final g in active)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PurchaseGoalCard(goal: g, plan: planFor(g, moves), currency: currency),
                  ),
                ),
              if (bought.isNotEmpty) ...[
                const ContentWidth(
                  child: Padding(padding: EdgeInsets.fromLTRB(4, 14, 4, 8), child: SectionLabel('Bought')),
                ),
                ContentWidth(
                  child: Card(
                    child: Column(
                      children: [
                        for (final g in bought)
                          ListTile(
                            leading: _GoalIcon(goal: g, size: 36, muted: true),
                            title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (g.doneAt != null) 'Bought ${DateFormat('d MMM y').format(g.doneAt!)}',
                                money(savedFor(g.id, moves), currency),
                              ].join(' · '),
                            ),
                            onTap: () => showPurchaseGoal(context, g),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.saved, required this.target, required this.count, required this.currency});
  final int saved;
  final int target;
  final int count;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final left = target - saved;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: const Color(0xFF2F5FA8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Put aside for purchases',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          BigAmount(money(saved, currency), size: 38, color: Colors.white),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: target <= 0 ? 0 : (saved / target).clamp(0, 1).toDouble(),
              minHeight: 6,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            left > 0
                ? '${money(left, currency)} to go across $count ${count == 1 ? 'goal' : 'goals'}'
                : 'Everything on your list is covered',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

class _GoalIcon extends StatelessWidget {
  const _GoalIcon({required this.goal, this.size = 44, this.muted = false});
  final SavingsGoal goal;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = muted ? Palette.of(context).muted : Color(goal.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(purchaseIcon(goal.icon), color: c, size: size * 0.52),
    );
  }
}

/// The plan line under the progress bar: on track or not, and what is needed.
class _PlanLines extends StatelessWidget {
  const _PlanLines({required this.plan, required this.currency});
  final PurchasePlan plan;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final muted = TextStyle(color: p.muted, fontSize: 14);
    if (plan.reached) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: p.positive),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'You have the full amount',
              style: TextStyle(color: p.positive, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    if (plan.overdue) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: paceAmber(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'The date has passed with ${money(plan.left, currency)} to go',
              style: TextStyle(color: paceAmber(context), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    final needed = neededLine(plan, currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.pace != null) GoalTrackLine(track: plan.pace!, currency: currency),
        if (needed != null) Text(needed, style: muted),
        if (plan.date == null && plan.projected != null)
          Text('At your pace so far, around ${DateFormat('MMM y').format(plan.projected!)}', style: muted),
      ],
    );
  }
}

class PurchaseGoalCard extends StatelessWidget {
  const PurchaseGoalCard({super.key, required this.goal, required this.plan, required this.currency});
  final SavingsGoal goal;
  final PurchasePlan plan;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = Color(goal.color);
    final when = goal.deadline == null ? null : 'by ${DateFormat('d MMM y').format(goal.deadline!)}';
    return Press(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showPurchaseGoal(context, goal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _GoalIcon(goal: goal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${money(plan.saved, currency)} of ${money(plan.target, currency)}',
                            style: TextStyle(color: p.muted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(plan.fraction * 100).floor()}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: plan.fraction,
                    minHeight: 8,
                    color: color,
                    backgroundColor: p.raised,
                  ),
                ),
                const SizedBox(height: 8),
                if (!plan.reached)
                  Text(
                    ['${money(plan.left, currency)} to go', ?when].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 2),
                _PlanLines(plan: plan, currency: currency),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (plan.reached)
                      FilledButton.tonal(
                        onPressed: () => markBought(context, goal),
                        child: const Text('Mark as bought'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => moveGoalMoney(context, goal, deposit: true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add money'),
                      ),
                    TextButton(
                      onPressed: plan.saved > 0 ? () => moveGoalMoney(context, goal, deposit: false) : null,
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

/// Asks for an amount to put into (or take out of) [goal]. Taking out is capped at what is there.
Future<void> moveGoalMoney(BuildContext context, SavingsGoal goal, {required bool deposit}) async {
  final db = context.db;
  final currency = context.settings.currency;
  final available = savedFor(goal.id, await db.watchMoves().first);
  if (!context.mounted) return;
  final result = await showDialog<(int, String)>(
    context: context,
    builder: (_) => _MoveDialog(goal: goal, deposit: deposit, available: available, currency: currency),
  );
  if (result == null) return;
  await db.addMove(goal.id, deposit ? result.$1 : -result.$1, note: result.$2);
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.goal, required this.deposit, required this.available, required this.currency});
  final SavingsGoal goal;
  final bool deposit;
  final int available;
  final String currency;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseMoney(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    if (!widget.deposit && cents > widget.available) {
      setState(() => _error = 'There is ${money(widget.available, widget.currency)} in this goal');
      return;
    }
    Navigator.pop(context, (cents, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.deposit ? 'Add to ${widget.goal.name}' : 'Take from ${widget.goal.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _error == null ? null : setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${currencySymbol(widget.currency)} ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.deposit ? 'Add' : 'Take out')),
      ],
    );
  }
}

Future<void> markBought(BuildContext context, SavingsGoal goal) async {
  final db = context.db;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await db.setGoalBought(goal.id, true);
  messenger
    ?..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${goal.name} moved to Bought'),
        action: SnackBarAction(label: 'Undo', onPressed: () => db.setGoalBought(goal.id, false)),
      ),
    );
}

/// Deletes [goal] and its history, with an Undo that brings both back.
Future<void> deletePurchaseGoal(BuildContext context, SavingsGoal goal) async {
  final db = context.db;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final moves = (await db.watchMoves().first).where((m) => m.goalId == goal.id).toList();
  await db.deleteGoal(goal.id);
  messenger
    ?..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${goal.name} deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreGoal(goal, moves)),
      ),
    );
}

Uri? linkUri(String link) {
  final t = link.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
  return uri == null || uri.host.isEmpty ? null : uri;
}

/// Details, plan and history of one purchase goal, in a sheet.
void showPurchaseGoal(BuildContext context, SavingsGoal goal) {
  final db = context.db;
  final settings = context.settings;
  // Actions run on the page, so their snack bars and dialogs outlive the sheet.
  final page = context;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Hub(
      db: db,
      settings: settings,
      child: StreamBuilder<List<SavingsGoal>>(
        stream: db.watchGoals(),
        builder: (sheet, gSnap) => StreamBuilder<List<SavingsMove>>(
          stream: db.watchMoves(),
          builder: (sheet, mSnap) {
            if (!gSnap.hasData || !mSnap.hasData) return const SizedBox(height: 200);
            final g = gSnap.data!.where((x) => x.id == goal.id).firstOrNull;
            if (g == null) return const SizedBox(height: 200);
            final allMoves = mSnap.data!;
            final moves = allMoves.where((m) => m.goalId == g.id).toList();
            return _GoalSheet(
              goal: g,
              moves: moves,
              plan: planFor(g, allMoves),
              currency: settings.currency,
              page: page,
            );
          },
        ),
      ),
    ),
  );
}

class _GoalSheet extends StatelessWidget {
  const _GoalSheet({
    required this.goal,
    required this.moves,
    required this.plan,
    required this.currency,
    required this.page,
  });
  final SavingsGoal goal;
  final List<SavingsMove> moves;
  final PurchasePlan plan;
  final String currency;
  final BuildContext page;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    final bought = goal.archived;
    final uri = linkUri(goal.link);
    void close() => Navigator.pop(context);
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: p.muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              _GoalIcon(goal: goal, muted: bought),
              const SizedBox(width: 12),
              Expanded(child: Text(goal.name, style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                tooltip: 'Edit goal',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  close();
                  editPurchaseGoal(page, goal: goal);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          BigAmount(money(plan.saved, currency), size: 34),
          Text('of ${money(plan.target, currency)}', style: TextStyle(color: p.muted)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: plan.fraction,
              minHeight: 8,
              color: bought ? p.muted : Color(goal.color),
              backgroundColor: p.raised,
            ),
          ),
          const SizedBox(height: 10),
          if (!bought) _PlanLines(plan: plan, currency: currency),
          const SizedBox(height: 8),
          if (bought && goal.doneAt != null) fact('Bought', DateFormat('d MMM y').format(goal.doneAt!)),
          if (!bought && !plan.reached) fact('Still to go', money(plan.left, currency)),
          if (goal.deadline != null) fact('Target date', DateFormat('d MMM y').format(goal.deadline!)),
          if (!bought && plan.perMonth != null) fact('Each month', money(plan.perMonth!, currency)),
          if (!bought && plan.perWeek != null) fact('Each week', money(plan.perWeek!, currency)),
          if (goal.link.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text('Link', style: TextStyle(color: p.muted)),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: uri == null ? null : () => launchUrl(uri, mode: LaunchMode.externalApplication),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          uri?.host ?? goal.link.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: uri == null ? null : p.accent,
                            decoration: uri == null ? null : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (goal.note.trim().isNotEmpty) fact('Notes', goal.note.trim()),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!bought) ...[
                FilledButton.icon(
                  onPressed: () => moveGoalMoney(page, goal, deposit: true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add money'),
                ),
                OutlinedButton(
                  onPressed: plan.saved > 0 ? () => moveGoalMoney(page, goal, deposit: false) : null,
                  child: const Text('Take out'),
                ),
                OutlinedButton(
                  onPressed: () {
                    close();
                    markBought(page, goal);
                  },
                  child: const Text('Mark as bought'),
                ),
              ] else
                OutlinedButton(onPressed: () => db.setGoalBought(goal.id, false), child: const Text('Back to goals')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: p.danger),
                onPressed: () {
                  close();
                  deletePurchaseGoal(page, goal);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('History'),
          const SizedBox(height: 4),
          if (moves.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing put aside yet.', style: TextStyle(color: p.muted)),
            ),
          for (final m in moves)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                m.amountCents >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 18,
                color: m.amountCents >= 0 ? p.positive : p.danger,
              ),
              title: Text(
                money(m.amountCents, currency, signed: true),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text([DateFormat('d MMM y').format(m.date), if (m.note.isNotEmpty) m.note].join(' · ')),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(page);
                  await db.deleteMove(m.id);
                  messenger
                    ?..removeCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Removed from history'),
                        action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreMove(m)),
                      ),
                    );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> editPurchaseGoal(BuildContext context, {SavingsGoal? goal}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => Hub(
    db: context.db,
    settings: context.settings,
    child: _PurchaseEditor(goal: goal, page: context),
  ),
);

class _PurchaseEditor extends StatefulWidget {
  const _PurchaseEditor({this.goal, required this.page});
  final SavingsGoal? goal;
  final BuildContext page;

  @override
  State<_PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<_PurchaseEditor> {
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : (widget.goal!.targetCents / 100).toStringAsFixed(2).replaceAll('.00', ''),
  );
  final _start = TextEditingController();
  late final _link = TextEditingController(text: widget.goal?.link ?? '');
  late final _note = TextEditingController(text: widget.goal?.note ?? '');
  late DateTime? _date = widget.goal?.deadline;
  late int _color = widget.goal?.color ?? goalColors[1];
  late String _icon = widget.goal == null || !purchaseIcons.containsKey(widget.goal!.icon) ? 'bag' : widget.goal!.icon;
  String? _nameError;
  String? _targetError;
  String? _startError;
  bool _saving = false;

  /// The icon follows the name ("New laptop" gets the laptop) until one is picked by hand.
  late bool _iconPicked = widget.goal != null;

  /// What an existing goal holds, for the plan preview.
  int _saved = 0;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    if (g != null) {
      context.db.watchMoves().first.then((m) {
        if (mounted) setState(() => _saved = savedFor(g.id, m));
      });
    }
    _name.addListener(() {
      if (_iconPicked) return;
      final guess = purchaseIconFor(_name.text);
      if (guess != _icon) setState(() => _icon = guess);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _target, _start, _link, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final cents = parseMoney(_target.text);
    final start = _start.text.trim().isEmpty ? 0 : parseMoney(_start.text);
    setState(() {
      _nameError = name.isEmpty ? 'Give it a name' : null;
      _targetError = cents == null || cents <= 0 ? 'Enter what it costs' : null;
      _startError = start == null || start < 0 ? 'Enter an amount, or leave it empty' : null;
    });
    if (_nameError != null || _targetError != null || _startError != null) return;
    _saving = true;
    final db = context.db;
    try {
      final id = await db.saveGoal(
        SavingsGoalsCompanion(
          id: widget.goal == null ? const Value.absent() : Value(widget.goal!.id),
          name: Value(name),
          targetCents: Value(cents!),
          deadline: Value(_date),
          color: Value(_color),
          purpose: const Value(purchasePurpose),
          icon: Value(_icon),
          link: Value(_link.text.trim()),
          note: Value(_note.text.trim()),
        ),
      );
      if (widget.goal == null && start! > 0) await db.addMove(id, start, note: 'Already put aside');
    } finally {
      _saving = false;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final last = DateTime(now.year + 30);
    final d = await showDatePicker(
      context: context,
      // A date that has passed opens on today instead of crashing the picker.
      initialDate: clampDay(_date ?? addMonths(dateOnly(now), 6), now, last),
      firstDate: dateOnly(now),
      lastDate: last,
      helpText: 'When do you want to buy it?',
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = context.settings.currency;
    final cents = parseMoney(_target.text);
    final saved = widget.goal == null ? (parseMoney(_start.text) ?? 0) : _saved;
    final preview = _date == null || cents == null || cents <= 0
        ? null
        : neededLine(
            purchasePlan(target: cents, saved: saved, start: DateTime.now(), date: _date, now: DateTime.now()),
            currency,
          );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.goal == null ? 'Plan a purchase' : 'Edit goal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: widget.goal == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'What is it?', hintText: 'New laptop', errorText: _nameError),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _targetError = null),
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '${currencySymbol(currency)} ',
                errorText: _targetError,
              ),
            ),
            if (widget.goal == null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _start,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _startError = null),
                decoration: InputDecoration(
                  labelText: 'Already put aside (optional)',
                  prefixText: '${currencySymbol(currency)} ',
                  errorText: _startError,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: Icon(Icons.event_outlined, size: 18, color: p.muted),
                label: Text(_date == null ? 'Add a target date' : 'By ${DateFormat('d MMM y').format(_date!)}'),
                onPressed: _pickDate,
                onDeleted: _date == null ? null : () => setState(() => _date = null),
              ),
            ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(preview, style: TextStyle(color: p.muted, fontSize: 13.5)),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link (optional)', hintText: 'Where you would buy it'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Icon'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in purchaseIcons.entries)
                  Semantics(
                    button: true,
                    selected: _icon == e.key,
                    label: e.key,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _icon = e.key;
                        _iconPicked = true;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _icon == e.key ? Color(_color).withValues(alpha: 0.16) : p.raised,
                          border: Border.all(color: _icon == e.key ? Color(_color) : Colors.transparent, width: 1.5),
                        ),
                        child: Icon(e.value, size: 22, color: _icon == e.key ? Color(_color) : p.muted),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionLabel('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final c in goalColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(c),
                      child: _color == c ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.goal != null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    onPressed: () {
                      Navigator.pop(context);
                      deletePurchaseGoal(widget.page, widget.goal!);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(widget.goal == null ? 'Create goal' : 'Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
