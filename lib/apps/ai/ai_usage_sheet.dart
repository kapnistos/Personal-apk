import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'ai_service.dart';
import 'ai_usage.dart';
import 'ai_widgets.dart';

/// Opens the usage sheet: tokens and cost today, this month and all time, by model, and for
/// [conversation] (name, tokens, cost) when one is open.
Future<void> showAiUsage(BuildContext context, {(String, int, double?)? conversation}) {
  final settings = context.settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => AiUsageSheet(settings: settings, conversation: conversation),
  );
}

class AiUsageSheet extends StatefulWidget {
  const AiUsageSheet({super.key, required this.settings, this.conversation});
  final AppSettings settings;
  final (String, int, double?)? conversation;

  @override
  State<AiUsageSheet> createState() => _AiUsageSheetState();
}

class _AiUsageSheetState extends State<AiUsageSheet> {
  bool _allTime = false;

  /// A readable model name: "Claude Haiku 4.5" for an OpenRouter id, "Claude Code · haiku" on the plan.
  String _name(AiSetup ai, String id) {
    if (id.startsWith('claude-code/')) return 'Claude Code · ${id.substring(12)}';
    if (id.contains('/')) return ai.openRouterName(id);
    final known = aiModels.where((m) => m.defaultModelId == id).firstOrNull;
    return known?.name ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final usage = AiUsage(widget.settings);
    final ai = AiSetup(widget.settings);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final month = DateTime(now.year, now.month);
    final models = usage.byModel(from: _allTime ? null : month);
    final conv = widget.conversation;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: ContentWidth(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Usage', style: Theme.of(context).textTheme.titleLarge),
            if (conv != null) ...[
              const AiLabel('This chat', top: 16),
              _Line(title: conv.$1, detail: '${formatTokens(conv.$2)} tokens', cost: conv.$3),
            ],
            const AiLabel('Totals', top: 16),
            Row(
              children: [
                for (final (label, total) in [
                  ('Today', usage.total(from: today)),
                  ('This month', usage.total(from: month)),
                  ('All time', usage.total()),
                ]) ...[
                  if (label != 'Today') const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(label: label, total: total),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'By model',
                      style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  PillToggle<bool>(
                    dense: true,
                    options: const [(false, 'This month'), (true, 'All time')],
                    value: _allTime,
                    onChanged: (v) => setState(() => _allTime = v),
                  ),
                ],
              ),
            ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing used yet.', style: TextStyle(color: p.muted)),
              )
            else
              for (final (id, t) in models)
                _Line(
                  title: _name(ai, id),
                  detail:
                      '${formatTokens(t.inputTokens)} in, ${formatTokens(t.outputTokens)} out · '
                      '${t.calls} answer${t.calls == 1 ? '' : 's'}',
                  cost: t.priced ? t.cost : null,
                ),
            const SizedBox(height: 16),
            Text(
              'Costs are estimates from OpenRouter\'s prices. Claude Code and the Claude app run on your plan, '
              'and other keys show tokens only; check their sites for the bill.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.total});
  final String label;
  final UsageTotal total;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: p.muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatTokens(total.tokens), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Text('tokens', style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            total.priced ? formatUsd(total.cost) : '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.detail, this.cost});
  final String title;
  final String detail;
  final double? cost;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: TextStyle(color: p.muted, fontSize: 13.5)),
                ],
              ),
            ),
            if (cost != null) ...[
              const SizedBox(width: 12),
              Text(formatUsd(cost!), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
