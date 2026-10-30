import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'ai_service.dart';
import 'ai_settings_sheet.dart';
import 'ai_widgets.dart';
import 'chat_memory.dart';
import 'claude_code.dart' show ClaudePlanUnavailable;
import 'hub_agent.dart';

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

/// The AI tab, and the same chat when opened from elsewhere: a switch between a general chat and
/// the Hub agent, the conversation, and a composer. The model chip opens AI settings.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, this.agent = false, this.initialText, this.inTab = false});
  final bool agent;

  /// Sent as the first message once the chat opens, e.g. from the quick-ask bar on Home.
  final String? initialText;

  /// Shown as the AI tab: no back button, and it remembers the last mode.
  final bool inTab;

  /// The mode the AI tab last showed: 'agent' or 'chat'.
  static const modeKey = 'ai.mode';

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

  /// Bumped by Stop, New chat and mode switches, so a late answer is dropped.
  int _gen = 0;
  AiSetup? _running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    if (widget.inTab) _agent = context.settings.raw(AiChatPage.modeKey) == 'agent';
    _restore();
    final first = widget.initialText?.trim() ?? '';
    if (first.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _send(first) : null);
  }

  ChatMemory get _memory => ChatMemory(context.settings);

  void _restore() => _turns
    ..clear()
    ..addAll(_memory.load(_agent).map(_Turn.restore));

  void _save([bool? agent]) => _memory.save(agent ?? _agent, [for (final t in _turns) t.saved]);

  void _switchMode(bool agent) {
    if (agent == _agent) return;
    _stop(note: false);
    if (widget.inTab) context.settings.setRaw(AiChatPage.modeKey, agent ? 'agent' : 'chat', quiet: true);
    setState(() {
      _agent = agent;
      _restore();
    });
    _toBottom(jump: true);
  }

  Future<void> _newChat() async {
    _stop(note: false);
    await _memory.clear(_agent);
    if (mounted) setState(_turns.clear);
  }

  /// Drops the answer still on its way. With [note], the chat says so.
  void _stop({bool note = true}) {
    if (!_busy) return;
    _gen++;
    _running?.close();
    _running = null;
    setState(() {
      _busy = false;
      if (note) _turns.add(_Turn('note', 'Stopped.'));
    });
    if (note) _save();
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
    _running?.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(end);
    } else {
      _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  });

  _Turn _assistant(String raw, {String? usage, required bool agent}) {
    if (!agent) return _Turn('assistant', raw, raw: raw, usage: usage);
    final r = parseAgentReply(raw);
    return _Turn('assistant', r.reply, raw: raw, usage: usage, actions: r.actions);
  }

  @override
  Future<void> onClaudeAnswer(String text) async {
    if (_answerForAgent != _agent) _switchMode(_answerForAgent);
    setState(() => _turns.add(_assistant(text, agent: _answerForAgent)));
    _save(_answerForAgent);
    _toBottom();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final ai = AiSetup(context.settings);
    final agent = _agent;
    final gen = ++_gen;
    _input.clear();
    setState(() => _turns.add(_Turn('user', text)));
    _toBottom();
    if (!await ai.apiReady()) {
      if (!mounted || gen != _gen) return;
      if (ai.useApi) {
        setState(
          () => _turns.add(
            _Turn('assistant', 'Add your ${ai.model.provider.label} key in AI settings first.', error: true),
          ),
        );
        _save(agent);
        return;
      }
      await _handOff(text, agent);
      return;
    }
    if (!mounted || gen != _gen) return;
    setState(() => _busy = true);
    _running = ai;
    final history = [
      for (final t in _turns)
        if (!t.error && t.role != 'note') AiMessage(t.role, t.raw ?? t.text),
    ];
    try {
      final system = await _system(agent);
      final reply = await ai.ask(history, system: system);
      if (!mounted || gen != _gen) return;
      setState(() => _turns.add(_assistant(reply.text, usage: reply.usage, agent: agent)));
    } on ClaudePlanUnavailable catch (e) {
      // Claude Code could not be reached: ask in the Claude app instead.
      if (mounted && gen == _gen) await _handOff(text, agent, why: e.note);
    } on AiException catch (e) {
      if (mounted && gen == _gen) setState(() => _turns.add(_Turn('assistant', e.message, error: true)));
    } finally {
      ai.close();
      if (mounted && gen == _gen) {
        _running = null;
        setState(() => _busy = false);
        if (_agent == agent) _save(agent);
        _toBottom();
      }
    }
  }

  /// Hands the request to the Claude app; its answer comes back by clipboard.
  Future<void> _handOff(String text, bool agent, {String? why}) async {
    _answerForAgent = agent;
    if (!mounted) return;
    final system = await _system(agent);
    final prompt = system == null ? text : '$system\n\nMy request: $text';
    if (!mounted) return;
    final sent = why ?? 'Sent to Claude';
    setState(() => _turns.add(_Turn('note', '$sent. Copy its answer, then come back to Hub to use it here.')));
    _save(agent);
    await askClaude(prompt);
  }

  Future<void> _act(_Turn t, int i, bool add) async {
    if (t.done[i] != null) return;
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

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final ai = AiSetup(settings);
    final canPop = !widget.inTab && Navigator.of(context).canPop();
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ContentWidth(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    if (canPop) ...[
                      AiRoundButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text('AI', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _ModelChip(label: ai.label, onTap: () => showAiSettings(context)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AiRoundButton(icon: Icons.add_comment_outlined, tooltip: 'New chat', onTap: _newChat),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillToggle<bool>(
                    options: const [(false, 'Chat'), (true, 'Hub agent')],
                    value: _agent,
                    onChanged: _switchMode,
                  ),
                ),
              ),
              Expanded(
                child: _turns.isEmpty
                    ? _Empty(
                        agent: _agent,
                        onSuggestion: _send,
                        usingDay: _memory.shareContext,
                        onUseDay: () => _memory.setShareContext(true),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _turns.length + (_busy ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _turns.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('Thinking…', style: TextStyle(color: p.muted)),
                            );
                          }
                          final t = _turns[i];
                          return _Bubble(turn: t, onAction: (j, add) => _act(t, j, add), onCopy: () => _copy(t.text));
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10 + bottom),
                child: _Composer(
                  controller: _input,
                  hint: _agent ? '12 euro lunch, note: call the landlord' : 'Ask anything',
                  busy: _busy,
                  inApp: ai.inApp,
                  onSend: _send,
                  onStop: _stop,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What answers, as a small pill; tap for AI settings.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: 'AI settings',
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Pressable(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: ShapeDecoration(color: p.raised, shape: const StadiumBorder()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      key: const ValueKey('ai-model-chip'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, size: 20, color: p.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.inApp,
    required this.onSend,
    required this.onStop,
  });
  final TextEditingController controller;
  final String hint;
  final bool busy;
  final bool inApp;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(26)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: hint,
                  hintMaxLines: 1,
                  hintStyle: TextStyle(color: p.muted, fontSize: 16, overflow: TextOverflow.ellipsis),
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            AiRoundButton(icon: Icons.stop_rounded, tooltip: 'Stop', filled: true, onTap: onStop)
          else
            AiRoundButton(
              icon: inApp ? Icons.arrow_upward_rounded : Icons.north_east_rounded,
              tooltip: 'Send',
              filled: true,
              onTap: onSend,
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.agent, required this.onSuggestion, required this.usingDay, required this.onUseDay});
  final bool agent;
  final void Function(String) onSuggestion;
  final bool usingDay;
  final VoidCallback onUseDay;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppGlyph(icon: agent ? Icons.support_agent_rounded : Icons.auto_awesome_rounded, color: aiColor, size: 52),
          const SizedBox(height: 16),
          Text(
            agent ? 'Tell it what to add' : 'Ask anything',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            agent
                ? 'Expenses, notes, to-dos, events and shopping. You see each change first, and nothing is saved '
                      'until you tap Add.'
                : usingDay
                ? 'A general assistant that also knows your day.'
                : 'A general assistant. It knows nothing about you unless you let it see your day.',
            style: TextStyle(color: p.muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in agent ? agentSuggestions : chatSuggestions)
                AiPill(label: q, onTap: () => onSuggestion(q)),
            ],
          ),
          if (!agent && !usingDay) ...[
            const SizedBox(height: 16),
            AiPill(label: 'Let it see my day', icon: Icons.insights_rounded, onTap: onUseDay),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn, required this.onAction, required this.onCopy});
  final _Turn turn;
  final void Function(int index, bool add) onAction;
  final VoidCallback onCopy;

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
    final note = turn.role == 'note';
    final answer = turn.role == 'assistant' && !turn.error && turn.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (turn.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: mine ? const EdgeInsets.symmetric(horizontal: 16, vertical: 11) : EdgeInsets.zero,
              decoration: mine ? BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(22)) : null,
              child: SelectableText(
                turn.text,
                style: TextStyle(
                  color: turn.error
                      ? p.danger
                      : note
                      ? p.muted
                      : p.ink,
                  fontSize: note ? 14 : 16,
                  height: 1.45,
                ),
              ),
            ),
          for (var i = 0; i < turn.actions.length; i++)
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  AppGlyph(icon: _icon(turn.actions[i].type), color: aiColor, size: 40),
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
                  const SizedBox(width: 8),
                  if (turn.done[i] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        turn.done[i] == 'added' ? 'Added' : 'Skipped',
                        style: TextStyle(
                          color: turn.done[i] == 'added' ? p.positive : p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else ...[
                    AiPill(label: 'Skip', onTap: () => onAction(i, false)),
                    const SizedBox(width: 6),
                    AiPill(label: 'Add', filled: true, onTap: () => onAction(i, true)),
                  ],
                ],
              ),
            ),
          if (answer)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Copy',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onCopy,
                      child: Pressable(
                        child: SizedBox.square(
                          dimension: 44,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(Icons.copy_rounded, size: 18, color: p.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (turn.usage != null) Text(turn.usage!, style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
