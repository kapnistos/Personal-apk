import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'claude_bridge.dart';

class ClaudePage extends StatefulWidget {
  const ClaudePage({super.key});

  @override
  State<ClaudePage> createState() => _ClaudePageState();
}

class _ClaudePageState extends State<ClaudePage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds a prompt that carries today's tasks and events as context.
  Future<String> _planMyDay() async {
    final db = context.db;
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = addDays(today, 1);
    final todos = (await db.watchTodos().first)
        .where((t) => !t.done && (t.due == null || t.due!.isBefore(addDays(tomorrow, 2))))
        .take(20)
        .toList();
    final events = await db.watchEventsBetween(today, tomorrow).first;
    final b = StringBuffer('Help me plan my day (${DateFormat('EEEE d MMMM').format(now)}).\n');
    if (events.isNotEmpty) {
      b.writeln('\nCalendar:');
      for (final e in events) {
        b.writeln('- ${e.allDay ? 'All day' : DateFormat.Hm().format(e.start)} ${e.title}');
      }
    }
    if (todos.isNotEmpty) {
      b.writeln('\nTasks:');
      for (final t in todos) {
        b.writeln('- ${t.title}${t.due != null ? ' (due ${friendlyDay(t.due!)})' : ''}${t.important ? ' [important]' : ''}');
      }
    }
    b.writeln('\nSuggest an order and realistic time blocks.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final quick = <(IconData, String, Future<String> Function())>[
      (Icons.wb_sunny_outlined, 'Plan my day', _planMyDay),
      (Icons.mail_outline_rounded, 'Draft an email', () async => 'Help me write a short, friendly email about: '),
      (Icons.translate_rounded, 'Translate', () async => 'Translate this into Dutch and Greek:\n\n'),
      (Icons.lightbulb_outline_rounded, 'Explain simply', () async => 'Explain this simply, with an example:\n\n'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Claude')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ContentWidth(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TileColors.claude.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppGlyph(icon: Icons.auto_awesome_rounded, color: TileColors.claude, size: 44),
                  const SizedBox(height: 14),
                  Text('Ask Claude', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Opens a new chat in the Claude app with your prompt, on your own plan.',
                    style: TextStyle(color: p.muted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'What do you need?',
                      fillColor: p.surface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: TileColors.claude, foregroundColor: Colors.white),
                        onPressed: () => ClaudeBridge.ask(context, _controller.text),
                        icon: const Icon(Icons.north_east_rounded, size: 18),
                        label: const Text('Ask in Claude'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => ClaudeBridge.ask(context, ''),
                      child: const Text('Open app'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ContentWidth(child: const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: SectionLabel('Starters'))),
          ContentWidth(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (icon, label, build) in quick)
                  ActionChip(
                    avatar: Icon(icon, size: 18, color: TileColors.claude),
                    label: Text(label),
                    onPressed: () async {
                      final text = await build();
                      if (!context.mounted) return;
                      if (label == 'Plan my day') {
                        ClaudeBridge.ask(context, text);
                      } else {
                        _controller.text = text;
                        _controller.selection = TextSelection.collapsed(offset: text.length);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ContentWidth(
            child: Text(
              'Hub never uses the paid Claude API. Prompts go to the official Claude app or claude.ai, '
              'where your Pro or Max usage limits apply. Very long prompts are copied to the clipboard for you to paste.',
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
