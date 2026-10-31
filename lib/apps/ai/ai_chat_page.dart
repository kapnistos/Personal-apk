import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'ai_service.dart';
import 'ai_settings_sheet.dart';
import 'ai_usage.dart';
import 'ai_usage_sheet.dart';
import 'ai_widgets.dart';
import 'chat_history_page.dart';
import 'chat_memory.dart';
import 'claude_code.dart' show ClaudePlanUnavailable;
import 'hub_agent.dart';
import 'hub_tools.dart';

class _Turn {
  _Turn(
    this.role,
    this.text, {
    this.raw,
    this.error = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost,
    this.model,
    this.tools = const [],
    this.actions = const [],
    Map<int, String>? done,
    DateTime? at,
  }) : done = done ?? {},
       at = at ?? DateTime.now();
  final String role;
  final String text;

  /// What the model actually sent, kept for the next request.
  final String? raw;
  final bool error;
  final int inputTokens;
  final int outputTokens;
  final double? cost;
  final String? model;
  final List<String> tools;
  final List<AgentAction> actions;
  final Map<int, String> done; // action index to 'added' or 'skipped'
  final DateTime at;

  /// How to take back each card added in this session; not saved, so Undo goes once the chat closes.
  final undo = <int, Undo>{};

  /// Cards still waiting for a tap.
  List<int> get pending => [
    for (var i = 0; i < actions.length; i++)
      if (done[i] == null) i,
  ];

  /// "597 in, 114 out tokens", and the cost when it is known.
  String? get usage {
    if (inputTokens == 0 && outputTokens == 0) return null;
    final base = '$inputTokens in, $outputTokens out tokens';
    return cost == null ? base : '$base · ${formatUsd(cost!)}';
  }

  SavedTurn get saved => SavedTurn(
    role,
    text,
    raw: raw,
    error: error,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cost: cost,
    model: model,
    tools: tools,
    actions: [for (final a in actions) a.toJson()],
    done: done,
    at: at,
  );

  static _Turn restore(SavedTurn t) => _Turn(
    t.role,
    t.text,
    raw: t.raw,
    error: t.error,
    inputTokens: t.inputTokens,
    outputTokens: t.outputTokens,
    cost: t.cost,
    model: t.model,
    tools: t.tools,
    actions: [for (final a in t.actions) ?AgentAction.fromJson(a)],
    done: Map.of(t.done),
    at: t.at,
  );
}

/// The AI tab, and the same chat when opened from elsewhere: a switch between a general chat and
/// the Hub agent, the conversation, and a composer. Conversations are saved and listed under History;
/// the model chip opens AI settings.
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

  /// The open conversation; null until the first message of a new chat.
  Conversation? _conv;

  /// What the model is looking at right now, for the line under the conversation.
  String? _activity;

  /// Bumped by Stop, New chat and mode switches, so a late answer is dropped.
  int _gen = 0;
  AiSetup? _running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    if (widget.inTab) _agent = context.settings.raw(AiChatPage.modeKey) == 'agent';
    final first = widget.initialText?.trim() ?? '';
    // The list is updated in memory at once; the database catches up in the background.
    _memory.migrate();
    // A quick ask from Home starts its own conversation.
    if (first.isNotEmpty) _memory.clear(_agent);
    _openConv(_memory.current(_agent));
    _toBottom(jump: true);
    if (first.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _send(first) : null);
  }

  ChatMemory get _memory => ChatMemory(context.settings);

  void _openConv(Conversation? c) {
    _conv = c;
    _turns
      ..clear()
      ..addAll((c?.turns ?? const <SavedTurn>[]).map(_Turn.restore));
  }

  /// Saves the open conversation. [agent] guards against a late answer for the other mode.
  Future<void> _save([bool? agent]) async {
    final c = _conv;
    if (c == null || (agent != null && agent != c.agent)) return;
    c.turns = [for (final t in _turns) t.saved];
    c.updated = DateTime.now();
    await _memory.save(c);
    await _memory.setCurrent(c.agent, c.id);
  }

  /// The conversation the next message goes into, made on the first message.
  Conversation _ensureConv() {
    if (_conv != null) return _conv!;
    final now = DateTime.now();
    return _conv = Conversation(id: ChatMemory.newId(now), agent: _agent, created: now, updated: now);
  }

  void _switchMode(bool agent) {
    if (agent == _agent) return;
    _stop(note: false);
    if (widget.inTab) context.settings.setRaw(AiChatPage.modeKey, agent ? 'agent' : 'chat', quiet: true);
    setState(() {
      _agent = agent;
      _openConv(_memory.current(agent));
    });
    _toBottom(jump: true);
  }

  Future<void> _newChat() async {
    _stop(note: false);
    _memory.clear(_agent);
    setState(() => _openConv(null));
  }

  Future<void> _openHistory() async {
    _stop(note: false);
    final picked = await Navigator.of(context)
        .push<ChatPick>(MaterialPageRoute(builder: (_) => ChatHistoryPage(agent: _agent)));
    if (!mounted) return;
    if (picked == null) {
      // The open conversation may have been renamed or deleted there.
      setState(() => _openConv(_conv == null ? null : _memory.open(_conv!.id)));
      return;
    }
    if (picked.agent != _agent && widget.inTab) {
      context.settings.setRaw(AiChatPage.modeKey, picked.agent ? 'agent' : 'chat', quiet: true);
    }
    final c = picked.id == null ? null : _memory.open(picked.id!);
    _memory.setCurrent(picked.agent, c?.id);
    setState(() {
      _agent = picked.agent;
      _openConv(c);
    });
    _toBottom(jump: true);
  }

  /// Drops the answer still on its way. With [note], the chat says so.
  void _stop({bool note = true}) {
    if (!_busy) return;
    _gen++;
    _running?.close();
    _running = null;
    setState(() {
      _busy = false;
      _activity = null;
      if (note) _turns.add(_Turn('note', 'Stopped.'));
    });
    if (note) _save();
  }

  /// Chat: a general assistant that knows the date, the user's name and that it is read on a phone.
  String _chatBase(DateTime now) {
    final s = context.settings;
    return 'You are a helpful assistant inside Hub, the user\'s personal app. Answer plainly and briefly, '
        'like a knowledgeable friend. Avoid headings and filler.\n'
        '${hubWhen(now, currency: s.currency, name: s.name)}\n$phoneStyle';
  }

  /// The system prompt for a model that reads the app with tools, in two parts: the fixed instructions, which
  /// the provider can cache, and the time and today at a glance, which change on every call.
  Future<(String, String)> _toolSystem(bool agent) async {
    final now = DateTime.now();
    final currency = context.settings.currency;
    final name = context.settings.name;
    final glance = await hubContext(context.db, now: now, currency: currency);
    final base = agent
        ? agentToolPrompt(now, currency: currency, name: name, withWhen: false)
        : '$_chatIntro\n$phoneStyle\nYou can read the user\'s calendar, tasks, money, notes, habits, spaces and '
              'more with the tools. Look before answering questions about their life. You cannot change anything '
              'from Chat; for that the user switches to Hub agent.';
    final when = hubWhen(now, currency: currency, name: name);
    return (base, '$when\n\nToday at a glance (use the tools for anything more):\n$glance');
  }

  /// The system prompt with the data written in, for setups that cannot call tools. Null for a plain chat.
  Future<String?> _fullSystem(bool agent) async {
    final now = DateTime.now();
    if (!agent && !_memory.shareContext) return null;
    final db = context.db;
    final currency = context.settings.currency;
    final base = agent ? agentSystemPrompt(now, currency: currency, name: context.settings.name) : _chatBase(now);
    final data = await HubTools(db, currency: currency).snapshot();
    return '$base\n\nThe user\'s Hub right now (${HubTools.day(now)}):\n$data';
  }

  /// Most messages sent with a question.
  static const maxHistory = 20;

  /// The last [maxHistory] of [all], starting on a user message so the conversation still opens correctly.
  static List<AiMessage> _recent(List<AiMessage> all) {
    if (all.length <= maxHistory) return all;
    final tail = all.sublist(all.length - maxHistory);
    final firstUser = tail.indexWhere((m) => m.role == 'user');
    return firstUser <= 0 ? tail : tail.sublist(firstUser);
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
      _scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    }
  });

  _Turn _assistant(AiReply r, {required bool agent, List<AgentAction> proposed = const []}) {
    var text = r.text;
    var actions = proposed;
    // A model without tools answers in JSON; one with tools sometimes does too.
    if (agent && (proposed.isEmpty || text.trimLeft().startsWith('{'))) {
      final parsed = parseAgentReply(text);
      if (parsed.actions.isNotEmpty || text.trimLeft().startsWith('{')) {
        text = parsed.reply;
        actions = [...proposed, ...parsed.actions];
      }
    }
    if (text.isEmpty && actions.isNotEmpty) text = 'Here is what I can add:';
    return _Turn(
      'assistant',
      text,
      raw: r.text,
      inputTokens: r.inputTokens,
      outputTokens: r.outputTokens,
      cost: r.cost,
      model: r.model,
      tools: r.toolsUsed.where((t) => !t.startsWith('propose_')).toSet().toList(),
      actions: actions,
    );
  }

  @override
  Future<void> onClaudeAnswer(String text) async {
    if (_answerForAgent != _agent) _switchMode(_answerForAgent);
    setState(() => _turns.add(_assistant(AiReply(text), agent: _answerForAgent)));
    await _save(_answerForAgent);
    _toBottom();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final ai = AiSetup(context.settings);
    final agent = _agent;
    final gen = ++_gen;
    _input.clear();
    _ensureConv();
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
        await _save(agent);
        return;
      }
      await _handOff(text, agent);
      return;
    }
    if (!mounted || gen != _gen) return;
    setState(() {
      _busy = true;
      _activity = null;
    });
    _running = ai;
    // Only the latest turns are sent: every call is billed for all of them, and older ones rarely matter.
    final history = _recent([
      for (final t in _turns)
        if (!t.error && t.role != 'note') AiMessage(t.role, t.raw ?? t.text),
    ]);
    final db = context.db;
    final currency = context.settings.currency;
    final usage = AiUsage(context.settings);
    try {
      AiReply? reply;
      var proposed = const <AgentAction>[];
      if (ai.canUseTools && (agent || _memory.shareContext)) {
        final tools = HubTools(db, currency: currency, writes: agent);
        try {
          final (system, systemTail) = await _toolSystem(agent);
          reply = await ai.ask(
            history,
            system: system,
            systemTail: systemTail,
            tools: tools.tools,
            runTool: (name, args) {
              final label = HubTools.labelFor(name);
              if (mounted && gen == _gen && label.isNotEmpty) setState(() => _activity = 'Looking at $label…');
              return tools.run(name, args);
            },
          );
          proposed = tools.proposals;
        } on AiToolsUnsupported {
          await ai.markNoTools();
        } on AiException catch (e) {
          // A request the provider rejected mid-way through the tool rounds: answer from the snapshot this time
          // rather than showing an error, without giving up on tools for later questions.
          if (e is ClaudePlanUnavailable || !(e.status == 400 || e.status == 422)) rethrow;
          proposed = const [];
        }
      }
      if (!mounted || gen != _gen) return;
      if (reply == null) {
        // A plain chat still knows the date, the name and that it is read on a phone.
        final system = await _fullSystem(agent);
        if (!mounted || gen != _gen) return;
        reply = await ai.ask(history, system: system ?? _chatBase(DateTime.now()));
      }
      if (!mounted || gen != _gen) return;
      await usage.record(reply.model ?? ai.modelId, reply.inputTokens, reply.outputTokens, reply.cost);
      if (!mounted || gen != _gen) return;
      setState(() => _turns.add(_assistant(reply!, agent: agent, proposed: proposed)));
    } on ClaudePlanUnavailable catch (e) {
      // Claude Code could not be reached: ask in the Claude app instead.
      if (mounted && gen == _gen) await _handOff(text, agent, why: e.note);
    } on AiException catch (e) {
      if (mounted && gen == _gen) setState(() => _turns.add(_Turn('assistant', e.message, error: true)));
    } finally {
      ai.close();
      if (mounted && gen == _gen) {
        _running = null;
        setState(() {
          _busy = false;
          _activity = null;
        });
        await _save(agent);
        _toBottom();
      }
    }
  }

  /// Hands the request to the Claude app; its answer comes back by clipboard.
  Future<void> _handOff(String text, bool agent, {String? why}) async {
    _answerForAgent = agent;
    if (!mounted) return;
    final system = await _fullSystem(agent);
    final prompt = system == null ? text : '$system\n\nMy request: $text';
    if (!mounted) return;
    final sent = why ?? 'Sent to Claude';
    setState(() => _turns.add(_Turn('note', '$sent. Copy its answer, then come back to Hub to use it here.')));
    await _save(agent);
    await askClaude(prompt);
  }

  /// Runs one card. Returns whether it went through.
  Future<bool> _apply(_Turn t, int i) async {
    final a = t.actions[i];
    try {
      final undo = await a.apply(context.db, settings: context.settings);
      t.undo[i] = undo;
      t.done[i] = 'added';
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _failed(AgentAction a) => switch (a.type) {
    'complete' || 'edit_task' || 'delete_task' => 'Could not find that task',
    'edit_event' || 'delete_event' => 'Could not find that event',
    'edit_note' => 'Could not find that note',
    _ => 'Could not do that',
  };

  Future<void> _act(_Turn t, int i, bool add) async {
    if (t.done[i] != null) return;
    final a = t.actions[i];
    final messenger = ScaffoldMessenger.of(context);
    if (add) {
      HapticFeedback.lightImpact();
      if (!await _apply(t, i)) {
        messenger.showSnackBar(SnackBar(content: Text(_failed(a))));
        return;
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(a.doneMessage),
          action: SnackBarAction(label: 'Undo', onPressed: () => _undo(t, [i])),
        ),
      );
    } else {
      t.done[i] = 'skipped';
    }
    if (mounted) setState(() {});
    await _save();
  }

  /// "Add all": every waiting card except deletes, which always get their own tap.
  Future<void> _actAll(_Turn t) async {
    final todo = [
      for (final i in t.pending)
        if (!t.actions[i].destructive) i,
    ];
    if (todo.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.lightImpact();
    final done = <int>[];
    for (final i in todo) {
      if (await _apply(t, i)) done.add(i);
    }
    if (!mounted) return;
    setState(() {});
    final failed = todo.length - done.length;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(failed == 0 ? 'All ${done.length} done' : '${done.length} done, $failed could not be added'),
        action: done.isEmpty ? null : SnackBarAction(label: 'Undo', onPressed: () => _undo(t, done)),
      ),
    );
    await _save();
  }

  /// Takes cards back, newest first, and offers them again.
  Future<void> _undo(_Turn t, List<int> which) async {
    var ok = true;
    for (final i in which.reversed) {
      final undo = t.undo.remove(i);
      if (undo == null) continue;
      try {
        await undo();
        t.done.remove(i);
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? 'Undone' : 'Could not undo all of it')));
    await _save();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.settings;
    final ai = AiSetup(settings);
    final canPop = !widget.inTab && Navigator.of(context).canPop();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final conv = _conv;
    final tokens = _turns.fold(0, (a, t) => a + t.inputTokens + t.outputTokens);
    final priced = _turns.where((t) => t.cost != null);
    final cost = priced.isEmpty ? null : priced.fold<double>(0, (a, t) => a + t.cost!);
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
                    AiRoundButton(icon: Icons.history_rounded, tooltip: 'History', onTap: _openHistory),
                    const SizedBox(width: 8),
                    AiRoundButton(icon: Icons.edit_square, tooltip: 'New chat', onTap: _newChat),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final showConv = conv != null && _turns.isNotEmpty;
                    return Row(
                      children: [
                        // Shrinks on very narrow screens rather than overflowing.
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: showConv ? box.maxWidth - 96 : box.maxWidth),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: PillToggle<bool>(
                              options: const [(false, 'Chat'), (true, 'Hub agent')],
                              value: _agent,
                              onChanged: _switchMode,
                            ),
                          ),
                        ),
                        if (showConv) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ConvLine(
                              title: Conversation.autoTitle([for (final t in _turns) t.saved]),
                              custom: conv.title,
                              tokens: tokens,
                              cost: cost,
                              onTap: () => showAiUsage(context, conversation: (conv.name, tokens, cost)),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: _turns.isEmpty
                    ? _Empty(
                        agent: _agent,
                        onSuggestion: _send,
                        usingDay: _memory.shareContext,
                        onUseDay: () => _memory.setShareContext(true),
                        recent: _memory.list(agent: _agent).take(3).toList(),
                        onOpen: (id) {
                          final c = _memory.open(id);
                          _memory.setCurrent(_agent, id);
                          setState(() => _openConv(c));
                          _toBottom(jump: true);
                        },
                        onAll: _openHistory,
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _turns.length + (_busy ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _turns.length) return _Thinking(label: _activity ?? 'Thinking…');
                          final t = _turns[i];
                          final newDay = i == 0 || dateOnly(_turns[i - 1].at) != dateOnly(t.at);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (newDay && i > 0) _DayDivider(day: t.at),
                              _Bubble(
                                turn: t,
                                currency: settings.currency,
                                onAction: (j, add) => _act(t, j, add),
                                onAll: () => _actAll(t),
                                onUndo: (j) => _undo(t, [j]),
                                onCopy: () => _copy(t.text),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10 + bottom),
                child: _Composer(
                  controller: _input,
                  hint: _agent ? 'Ask, or add something' : 'Ask anything',
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

/// The open conversation's name and what it has used so far; tap for usage.
class _ConvLine extends StatelessWidget {
  const _ConvLine({required this.title, required this.custom, required this.tokens, this.cost, required this.onTap});
  final String title;
  final String custom;
  final int tokens;
  final double? cost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final name = custom.trim().isNotEmpty ? custom.trim() : title;
    final used = tokens == 0 ? '' : '${formatTokens(tokens)} tokens${cost == null ? '' : ' · ${formatUsd(cost!)}'}';
    return Semantics(
      button: true,
      label: 'This chat: $name. $used',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              if (used.isNotEmpty)
                Text(
                  used,
                  key: const ValueKey('ai-conv-usage'),
                  maxLines: 1,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Text(friendlyDay(day), style: TextStyle(color: Palette.of(context).muted, fontSize: 12.5)),
    ),
  );
}

/// A soft pulsing dot and what the model is doing.
class _Thinking extends StatefulWidget {
  const _Thinking({required this.label});
  final String label;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: aiColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                widget.label,
                key: ValueKey(widget.label),
                style: TextStyle(color: p.muted),
              ),
            ),
          ),
        ],
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
  const _Empty({
    required this.agent,
    required this.onSuggestion,
    required this.usingDay,
    required this.onUseDay,
    required this.recent,
    required this.onOpen,
    required this.onAll,
  });
  final bool agent;
  final void Function(String) onSuggestion;
  final bool usingDay;
  final VoidCallback onUseDay;
  final List<ChatSummary> recent;
  final void Function(String id) onOpen;
  final VoidCallback onAll;

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
            agent ? 'Ask your Hub' : 'Ask anything',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            agent
                ? 'It can see your calendar, wallet, tasks, notes, habits and spaces. Ask what is coming up, '
                      'or tell it what to add. You see each change first; nothing is saved until you tap Add.'
                : usingDay
                ? 'A general assistant that can also look at your Hub.'
                : 'A general assistant. It knows nothing about you unless you let it see your Hub.',
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
            AiPill(label: 'Let it see my Hub', icon: Icons.insights_rounded, onTap: onUseDay),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent',
                    style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: onAll, child: const Text('See all')),
              ],
            ),
            for (final c in recent) ChatRow(chat: c, onTap: () => onOpen(c.id)),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.turn,
    required this.currency,
    required this.onAction,
    required this.onAll,
    required this.onUndo,
    required this.onCopy,
  });
  final _Turn turn;
  final String currency;
  final void Function(int index, bool add) onAction;
  final VoidCallback onAll;
  final void Function(int index) onUndo;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mine = turn.role == 'user';
    final note = turn.role == 'note';
    final answer = turn.role == 'assistant' && !turn.error && turn.text.isNotEmpty;
    final style = TextStyle(
      color: turn.error
          ? p.danger
          : note
          ? p.muted
          : p.ink,
      fontSize: note ? 14 : 16,
      height: 1.45,
    );
    final looked = [for (final t in turn.tools) HubTools.labelFor(t)].where((s) => s.isNotEmpty).toSet().toList();
    final allable = [
      for (final i in turn.pending)
        if (!turn.actions[i].destructive) i,
    ];
    return Padding(
      padding: EdgeInsets.only(top: mine ? 10 : 4, bottom: 4),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (looked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.manage_search_rounded, size: 16, color: p.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Looked at ${_list(looked)}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          if (turn.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: mine ? const EdgeInsets.symmetric(horizontal: 16, vertical: 11) : EdgeInsets.zero,
              decoration: mine ? BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(22)) : null,
              child: answer
                  ? SelectableText.rich(aiMarkdown(turn.text, base: style, codeBackground: p.raised))
                  : SelectableText(turn.text, style: style),
            ),
          for (var i = 0; i < turn.actions.length; i++)
            _ActionCard(
              key: ValueKey('ai-card-$i'),
              action: turn.actions[i],
              currency: currency,
              state: turn.done[i],
              canUndo: turn.undo.containsKey(i),
              onAdd: () => onAction(i, true),
              onSkip: () => onAction(i, false),
              onUndo: () => onUndo(i),
            ),
          if (allable.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AiPill(
                    label: allable.length == turn.pending.length
                        ? 'Add all ${allable.length}'
                        : 'Add the other ${allable.length}',
                    icon: Icons.done_all_rounded,
                    filled: true,
                    onTap: onAll,
                  ),
                ),
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
                  if (turn.usage != null)
                    Flexible(
                      child: Text(turn.usage!, style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _list(List<String> l) =>
      l.length == 1 ? l.first : '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';
}

/// One proposed change: what it is, what it changes, and the button that does it. Deletes are red.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.action,
    required this.currency,
    required this.state,
    required this.canUndo,
    required this.onAdd,
    required this.onSkip,
    required this.onUndo,
  });
  final AgentAction action;
  final String currency;

  /// null while waiting, 'added' or 'skipped'.
  final String? state;
  final bool canUndo;
  final VoidCallback onAdd;
  final VoidCallback onSkip;
  final VoidCallback onUndo;

  static IconData icon(String type) => switch (type) {
    'expense' => Icons.arrow_outward_rounded,
    'income' => Icons.south_west_rounded,
    'note' => Icons.sticky_note_2_outlined,
    'edit_note' => Icons.edit_note_rounded,
    'task' => Icons.check_circle_outline_rounded,
    'edit_task' => Icons.edit_calendar_rounded,
    'complete' => Icons.task_alt_rounded,
    'event' => Icons.event_outlined,
    'edit_event' => Icons.edit_calendar_rounded,
    'delete_event' || 'delete_task' => Icons.delete_outline_rounded,
    'shopping' => Icons.shopping_basket_outlined,
    'recurring' || 'edit_recurring' => Icons.autorenew_rounded,
    'saving' => Icons.savings_outlined,
    'budget_target' => Icons.speed_rounded,
    'work_day' => Icons.schedule_rounded,
    'space_date' => Icons.flag_outlined,
    'habit' => Icons.local_fire_department_outlined,
    _ => Icons.add_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final danger = action.destructive;
    final tint = danger ? p.danger : aiColor;
    final detail = action.detailIn(currency);
    final added = state == 'added';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          action.label,
          style: TextStyle(
            color: danger ? p.danger : p.muted,
            fontSize: 12.5,
            fontWeight: danger ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          action.summaryIn(currency),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            height: 1.3,
            decoration: danger && added ? TextDecoration.lineThrough : null,
            color: state == 'skipped' ? p.muted : p.ink,
          ),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(detail, style: TextStyle(color: p.muted, fontSize: 13, height: 1.3)),
          ),
      ],
    );
    final Widget buttons = state != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (added) Icon(Icons.check_rounded, size: 18, color: danger ? p.muted : p.positive),
              if (added) const SizedBox(width: 4),
              Text(
                added ? action.doneLabel : 'Skipped',
                style: TextStyle(color: added && !danger ? p.positive : p.muted, fontWeight: FontWeight.w600),
              ),
              if (canUndo) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onUndo,
                  style: TextButton.styleFrom(minimumSize: const Size(56, 44)),
                  child: const Text('Undo'),
                ),
              ] else
                const SizedBox(width: 8),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiPill(label: 'Skip', onTap: onSkip),
              const SizedBox(width: 6),
              AiPill(label: action.verb, filled: true, color: danger ? p.danger : null, onTap: onAdd),
            ],
          );
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger && state == null ? Color.alphaBlend(p.danger.withValues(alpha: 0.07), p.surface) : p.surface,
        borderRadius: BorderRadius.circular(20),
        border: danger && state == null ? Border.all(color: p.danger.withValues(alpha: 0.35)) : null,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final glyph = AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: state == null ? 1 : 0.55,
            child: AppGlyph(icon: icon(action.type), color: tint, size: 40),
          );
          // On a phone the buttons sit under the text, so the text keeps the width.
          // A short line, or a card already answered, keeps everything on one row.
          final short = detail == null && action.summaryIn(currency).length <= (box.maxWidth < 360 ? 12 : 20);
          if (box.maxWidth < 440 && !short && state == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    glyph,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(padding: const EdgeInsets.only(top: 1), child: text),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: buttons),
              ],
            );
          }
          return Row(
            children: [
              glyph,
              const SizedBox(width: 12),
              Expanded(child: text),
              const SizedBox(width: 8),
              buttons,
            ],
          );
        },
      ),
    );
  }
}
