import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../claude/claude_bridge.dart';
import 'ai_service.dart';
import 'chat_memory.dart';
import 'hub_agent.dart';

const _aiColor = Color(0xFF4D6BFE);

class _Turn {
  _Turn(this.role, this.text, {this.raw, this.usage, this.actions = const [], this.error = false});
  final String role;
  final String text;

  /// What the model actually sent, kept for the next request.
  final String? raw;
  final String? usage;
  final List<AgentAction> actions;
  final bool error;
  final done = <int, String>{}; // action index to 'added' or 'skipped'

  SavedTurn get saved => SavedTurn(role, text, raw: raw, error: error);

  /// Old proposals come back as text only, so nothing can be added twice.
  static _Turn restore(SavedTurn t) => _Turn(t.role, t.text, raw: t.raw, error: t.error);
}

/// A conversation with the chosen model, or the Hub agent that proposes changes to your data.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, this.agent = false});
  final bool agent;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> with WidgetsBindingObserver, ClaudeAnswerWatcher {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  late bool _agent = widget.agent;
  bool _busy = false;
  bool _answerForAgent = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _restore();
  }

  ChatMemory get _memory => ChatMemory(context.settings);

  void _restore() => _turns
    ..clear()
    ..addAll(_memory.load(_agent).map(_Turn.restore));

  void _save([bool? agent]) => _memory.save(agent ?? _agent, [for (final t in _turns) t.saved]);

  void _switchMode(bool agent) {
    if (agent == _agent) return;
    setState(() {
      _agent = agent;
      _restore();
    });
    _toBottom();
  }

  Future<void> _clear() async {
    await _memory.clear(_agent);
    if (mounted) setState(_turns.clear);
  }

  /// The system prompt, with today's summary when the user allowed it.
  Future<String?> _system(bool agent) async {
    final base = agent
        ? agentSystemPrompt(DateTime.now())
        : 'You are a helpful assistant inside Hub, the user\'s personal app. Answer plainly and briefly.';
    if (!_memory.shareContext) return agent ? base : null;
    final db = context.db;
    final currency = context.settings.currency;
    final data = await hubContext(db, currency: currency);
    return '$base\n\nWhat Hub knows about the user right now:\n$data';
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  _Turn _assistant(String raw, {String? usage, required bool agent}) {
    if (!agent) return _Turn('assistant', raw, raw: raw, usage: usage);
    final r = parseAgentReply(raw);
    return _Turn('assistant', r.reply, raw: raw, usage: usage, actions: r.actions);
  }

  @override
  Future<void> onClaudeAnswer(String text) async {
    setState(() => _turns.add(_assistant(text, agent: _answerForAgent)));
    _save(_answerForAgent);
    _toBottom();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final ai = AiSetup(context.settings);
    final agent = _agent;
    _input.clear();
    setState(() => _turns.add(_Turn('user', text)));
    _toBottom();
    if (!await ai.apiReady()) {
      if (ai.useApi) {
        setState(
          () => _turns.add(
            _Turn('assistant', 'Add your ${ai.model.provider.label} key in the AI tab first.', error: true),
          ),
        );
        _save(agent);
        return;
      }
      _answerForAgent = agent;
      if (!mounted) return;
      final system = await _system(agent);
      final prompt = system == null ? text : '$system\n\nMy request: $text';
      if (!mounted) return;
      setState(
        () => _turns.add(_Turn('note', 'Sent to Claude. Copy its answer, then come back to Hub to use it here.')),
      );
      _save(agent);
      await askClaude(prompt);
      return;
    }
    setState(() => _busy = true);
    final history = [
      for (final t in _turns)
        if (!t.error && t.role != 'note') AiMessage(t.role, t.raw ?? t.text),
    ];
    try {
      final system = await _system(agent);
      final reply = await ai.ask(history, system: system);
      if (!mounted) return;
      setState(() => _turns.add(_assistant(reply.text, usage: reply.usage, agent: agent)));
    } on AiException catch (e) {
      if (mounted) setState(() => _turns.add(_Turn('assistant', e.message, error: true)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_agent == agent) _save(agent);
      }
      _toBottom();
    }
  }

  Future<void> _act(_Turn t, int i, bool add) async {
    if (add) {
      final db = context.db;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await t.actions[i].apply(db);
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text('Could not add that')));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('${t.actions[i].label} added')));
    }
    if (mounted) setState(() => t.done[i] = add ? 'added' : 'skipped');
  }

  Future<void> _contextSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => ListenableBuilder(
      listenable: context.settings,
      builder: (sheet, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: SwitchListTile(
            title: const Text('Use my day'),
            subtitle: const Text(
              'Send a short summary with each question: today\'s tasks and events, what you spent this week and '
              'month, and your latest notes. Without it the model knows nothing about you.',
            ),
            value: _memory.shareContext,
            onChanged: _memory.setShareContext,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ai = AiSetup(context.settings);
    final where = ai.useApi ? '${ai.model.name} on your API key' : 'Claude app on your plan';
    return Scaffold(
      appBar: AppBar(title: Text(_agent ? 'Hub agent' : 'Chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final (agent, label) in [(false, 'Chat'), (true, 'Hub agent')]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _agent == agent,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    onSelected: _busy ? null : (_) => _switchMode(agent),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                IconButton(
                  tooltip: _memory.shareContext ? 'Using your day' : 'Not using your data',
                  isSelected: _memory.shareContext,
                  onPressed: _contextSheet,
                  icon: Icon(Icons.insights_outlined, color: p.muted),
                  selectedIcon: const Icon(Icons.insights_rounded, color: _aiColor),
                ),
                if (_turns.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear chat',
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _turns.isEmpty
                ? _Empty(
                    agent: _agent,
                    where: where,
                    onSuggestion: _send,
                    usingDay: _memory.shareContext,
                    onUseDay: () => _memory.setShareContext(true),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _turns.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _turns.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final t = _turns[i];
                      return _Bubble(turn: t, onAction: (j, add) => _act(t, j, add));
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _agent ? '12 euro lunch, note: call the landlord' : 'Ask anything',
                        helperText: where,
                        helperStyle: TextStyle(color: p.muted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: IconButton.filled(
                      tooltip: 'Send',
                      style: IconButton.styleFrom(backgroundColor: _aiColor, foregroundColor: Colors.white),
                      onPressed: _busy ? null : _send,
                      icon: Icon(ai.useApi ? Icons.arrow_upward_rounded : Icons.north_east_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.agent,
    required this.where,
    required this.onSuggestion,
    required this.usingDay,
    required this.onUseDay,
  });
  final bool agent;
  final String where;
  final void Function(String) onSuggestion;
  final bool usingDay;
  final VoidCallback onUseDay;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: _aiColor, shape: BoxShape.circle),
              child: Icon(
                agent ? Icons.support_agent_rounded : Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(agent ? 'Tell it what to add' : 'Ask anything', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              agent
                  ? 'Say "12 euro lunch", "dentist Friday at 2" or "buy milk". You see each change first and '
                        'nothing is saved until you tap Add.'
                  : 'Using $where.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final q in agent ? agentSuggestions : chatSuggestions)
                  ActionChip(label: Text(q), shape: const StadiumBorder(), onPressed: () => onSuggestion(q)),
              ],
            ),
            if (!agent && !usingDay) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onUseDay,
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: const Text('Let it see my tasks, events and spending'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn, required this.onAction});
  final _Turn turn;
  final void Function(int index, bool add) onAction;

  static IconData _icon(String type) => switch (type) {
    'expense' => Icons.arrow_outward_rounded,
    'income' => Icons.south_west_rounded,
    'note' => Icons.sticky_note_2_outlined,
    'task' => Icons.check_circle_outline_rounded,
    'event' => Icons.event_outlined,
    'shopping' => Icons.shopping_basket_outlined,
    _ => Icons.add_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mine = turn.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (turn.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: mine ? _aiColor : p.surface, borderRadius: BorderRadius.circular(18)),
              child: SelectableText(
                turn.text,
                style: TextStyle(
                  color: mine
                      ? Colors.white
                      : (turn.error
                            ? p.danger
                            : turn.role == 'note'
                            ? p.muted
                            : p.ink),
                  height: 1.4,
                ),
              ),
            ),
          if (turn.usage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: Text(turn.usage!, style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          for (var i = 0; i < turn.actions.length; i++)
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: _aiColor.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(_icon(turn.actions[i].type), color: _aiColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(turn.actions[i].label, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        Text(turn.actions[i].summary, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (turn.done[i] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        turn.done[i] == 'added' ? 'Added' : 'Skipped',
                        style: TextStyle(color: turn.done[i] == 'added' ? p.positive : p.muted),
                      ),
                    )
                  else ...[
                    TextButton(onPressed: () => onAction(i, false), child: const Text('Skip')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _aiColor,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => onAction(i, true),
                      child: const Text('Add'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
